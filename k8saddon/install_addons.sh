#!/bin/bash

kubectl apply -f dashboard/metrics
kubectl apply -f dashboard

kubectl apply -f ingress/nginx_ingress.yaml

kubectl apply -f volume.yaml

# add docker registry info
# the following variables must point to an existing registry
# DOCKER_USER
# DOCKER_PASSWORD
# DOCKER_REGISTRY_SERVER
DOCKER_EMAIL=user@foo.com

n=$(kubectl get secrets | grep -q busterregistry; echo $?)
if [ $n == 1 ]; then
kubectl create secret docker-registry busterregistry --docker-server=${DOCKER_REGISTRY_SERVER} --docker-username=${DOCKER_USER} \
            --docker-password=${DOCKER_PASSWORD} --docker-email=${DOCKER_EMAIL}
fi


kubectl -n kubernetes-dashboard describe secret $(kubectl -n kubernetes-dashboard get secret | grep admin-user | awk '{print $1}')

# Install monitoring
kubectl apply -f monitoring/prometheus.yaml
kubectl apply -f monitoring/prometheus-configmap.yaml 
kubectl apply -f monitoring/prometheus-rules.yaml
cat monitoring/alertmanager-config.yaml | envsubst | kubectl apply -f -
kubectl apply -f monitoring/alertmanager-templates.yaml
kubectl apply -f monitoring/alertmanager.yaml 
kubectl apply -f monitoring/node-exp-daemonset.yaml  
kubectl apply -f monitoring/node-exp-service.yaml

n=$(kubectl get secrets -n monitoring | grep -q grafana; echo $?)
if [ $n == 1 ]; then
    echo -n monit > ./admin-username
    echo -n ${KLUSTER_MONITORING_PWD} > ./admin-password
    kubectl create -n monitoring secret generic grafana --from-file=./admin-username --from-file=./admin-password
    rm admin-username admin-password
fi

kubectl apply -f monitoring/grafana.yaml
kubectl apply -f monitoring/grafana-configmap.yaml
kubectl apply -f monitoring/grafana-job.yaml

n=$(kubectl get secrets -n monitoring | grep -q monitoringauth; echo $?)
if [ $n == 1 ]; then
    htpasswd -b -c ./auth monit ${KLUSTER_MONITORING_PWD}
    kubectl create secret generic -n monitoring monitoringauth --from-file auth
    rm auth
fi

n=$(kubectl get secrets -n monitoring | grep -q monitoring-certificate; echo $?)
if [ $n == 1 ]; then
    kubectl create secret -n monitoring tls monitoring-certificate \
        --key ../keystore/busterkeen.francecentral.cloudapp.azure.com_server.key \
        --cert ../keystore/busterkeen.francecentral.cloudapp.azure.com_server.crt 
fi

# Install logging
kubectl apply -f logging/ns.yaml
kubectl apply -f logging/es.yaml

# give sometime to elasticsearch
sleep 30

kubectl annotate pods --namespace=ingress-nginx --overwrite --all fluentbit.io/exclude=true
kubectl annotate pods --namespace=kube-node-lease --overwrite  --all fluentbit.io/exclude=true
kubectl annotate pods --namespace=kube-public --overwrite  --all fluentbit.io/exclude=true
kubectl annotate pods --namespace=kube-system --overwrite --all fluentbit.io/exclude=true
kubectl annotate pods --namespace=kubernetes-dashboard --overwrite --all fluentbit.io/exclude=true
kubectl annotate pods --namespace=monitoring --overwrite --all fluentbit.io/exclude=true

kubectl apply -f logging/ns.yaml
kubectl apply -f logging/es.yaml
kubectl apply -f logging/fluent-bit-configmap.yaml  
kubectl apply -f logging/fluent-bit-role-binding.yaml  
kubectl apply -f logging/fluent-bit-role.yaml 
kubectl apply -f logging/fluent-bit-service-account.yaml
kubectl apply -f logging/fluent-bit-ds.yaml  

n=$(kubectl get secrets -n logging | grep -q loggingauth; echo $?)
if [ $n == 1 ]; then
    htpasswd -b -c ./auth monit ${KLUSTER_LOGGING_PWD}
    kubectl create secret generic -n logging loggingauth --from-file auth
    rm auth
fi

kubectl apply -f logging/kibana.yaml

kubectl annotate pods --namespace=logging --overwrite --all fluentbit.io/exclude=true
