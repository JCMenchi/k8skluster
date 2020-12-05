#!/bin/bash

# This script create a config file for a new user in a namespace
# it must be run with k8s admin priviledges
#
# Namespace will be created if needed.
# 
# Usage: k8s_create_user.sh USERNAME NAMESPACE [GROUP ...]

show_help () {
    echo "Usage: $0 [-u USERNAME] NAMESPACE [GROUP1 GROUP2 ...]"
    echo "  Create namespace and config file with admin rights for this namespace."
    echo "      -u USERNAME : create config for USERNAME (default same as namespace)"
}

# Decode args
OPTIND=1  # Reset in case getopts has been used previously in the shell.

K8SUSER=""

while getopts "h?u:" opt; do
    case "$opt" in
    h|\?)
        show_help
        exit 0
        ;;
    u)  K8SUSER=$OPTARG
        ;;
    esac
done

shift $((OPTIND-1))

if [ $# -eq 0 ]; then
    echo "Bad number of arguments."
    show_help
    exit 1
fi

K8SNAMESPACE=$1

if [ x${K8SUSER} == "x" ]; then
    K8SUSER=${K8SNAMESPACE}
fi

OTHERGROUP=""
shift 1
while [ $# -gt 0 ]; do
    OTHERGROUP=${OTHERGROUP}/O=$1
    shift
done

# check if namespace exists
v=$(kubectl get ns | grep -q ${K8SNAMESPACE} ; echo $?)
if [ $v = 0 ]; then
    echo "Namespace ${K8SNAMESPACE} exists"
else
    kubectl create ns ${K8SNAMESPACE}
fi

# admin account
v=$(kubectl -n ${K8SNAMESPACE} get serviceaccounts | grep -q admin-${K8SNAMESPACE} ; echo $?)
if [ $v = 0 ]; then
    echo "Service Account for ${K8SNAMESPACE} exists"
else
    kubectl -n ${K8SNAMESPACE} create serviceaccount admin-${K8SNAMESPACE}
    kubectl -n ${K8SNAMESPACE} describe secret admin-${K8SNAMESPACE} | awk '{print $1}'
fi

# check if role binding exists
v=$(kubectl get rolebinding -n ${K8SNAMESPACE} | grep -q admin-${K8SNAMESPACE} ; echo $?)
if [ $v = 0 ]; then
    echo "Role binding admin-${K8SNAMESPACE} exists."
else
    kubectl create rolebinding admin-${K8SNAMESPACE} --namespace=${K8SNAMESPACE} --clusterrole=admin --serviceaccount=${K8SNAMESPACE}:admin-${K8SNAMESPACE}
fi

# check if config file exists exists
if [ -e ${K8SUSER}-k8s-config ]; then
    echo "Config file ${K8SUSER}-k8s-config exists."
else
    # create key and CSR
    export MSYS_NO_PATHCONV=1
    openssl req -new -newkey rsa:4096 -nodes -keyout ${K8SUSER}-k8s.key -out ${K8SUSER}-k8s.csr -subj "/CN=${K8SUSER}/O=${K8SNAMESPACE}${OTHERGROUP}"
    MYCSR=$(cat ${K8SUSER}-k8s.csr | base64 | tr -d '\n')

    # create file to send CSR to kubernetes cluster
    echo "apiVersion: certificates.k8s.io/v1beta1" > ${K8SUSER}-k8s-csr.yaml
    echo "kind: CertificateSigningRequest" >> ${K8SUSER}-k8s-csr.yaml
    echo "metadata:" >> ${K8SUSER}-k8s-csr.yaml
    echo "  name: ${K8SUSER}-k8s-access" >> ${K8SUSER}-k8s-csr.yaml
    echo "spec:" >> ${K8SUSER}-k8s-csr.yaml
    echo "  groups:" >> ${K8SUSER}-k8s-csr.yaml
    echo "  - system:authenticated" >> ${K8SUSER}-k8s-csr.yaml
    echo -n "  request: " >> ${K8SUSER}-k8s-csr.yaml
    echo ${MYCSR} >> ${K8SUSER}-k8s-csr.yaml
    echo "  usages:" >> ${K8SUSER}-k8s-csr.yaml
    echo "  - client auth" >> ${K8SUSER}-k8s-csr.yaml

    kubectl create -f ${K8SUSER}-k8s-csr.yaml

    # to check pending CSR list use command below
    # kubectl get csr

    # Approve CSR
    kubectl certificate approve ${K8SUSER}-k8s-access

    # Get user Certificate
    kubectl get csr ${K8SUSER}-k8s-access -o jsonpath='{.status.certificate}' | base64 --decode > ${K8SUSER}-k8s-access.crt
 
    # Get cluster Root CA certificate
    kubectl config view -o jsonpath='{.clusters[0].cluster.certificate-authority-data}' --raw | base64 --decode - > k8s-ca.crt
 
    # Create config file
    kubectl config set-cluster $(kubectl config view -o jsonpath='{.clusters[0].name}') --server=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}') --certificate-authority=k8s-ca.crt --kubeconfig=${K8SUSER}-k8s-config --embed-certs

    kubectl config set-credentials ${K8SUSER} --client-certificate=${K8SUSER}-k8s-access.crt --client-key=${K8SUSER}-k8s.key --embed-certs --kubeconfig=${K8SUSER}-k8s-config

    kubectl config set-context ${K8SUSER} --cluster=$(kubectl config view -o jsonpath='{.clusters[0].name}') --namespace=${K8SNAMESPACE} --user=${K8SUSER} --kubeconfig=${K8SUSER}-k8s-config

    kubectl config use-context ${K8SUSER} --kubeconfig=${K8SUSER}-k8s-config

    # cleanup
    rm k8s-ca.crt ${K8SUSER}-k8s-access.crt ${K8SUSER}-k8s.key ${K8SUSER}-k8s-csr.yaml ${K8SUSER}-k8s.csr
fi

# check if role binding exists
v=$(kubectl get rolebinding -n ${K8SNAMESPACE} | grep -q ${K8SNAMESPACE}-admin ; echo $?)
if [ $v = 0 ]; then
    echo "Role binding ${K8SNAMESPACE}-admin exists."
else
    kubectl create rolebinding ${K8SNAMESPACE}-admin --namespace=${K8SNAMESPACE} --clusterrole=admin --group=${K8SNAMESPACE}
fi

echo ""
echo "NAMESPACE ACCOUNT TOKEN"
kubectl -n ${K8SNAMESPACE} describe secret admin-${K8SNAMESPACE} | grep token: | awk '{print $2}'

# To set your new config file
# kubectl get pods --kubeconfig=${K8SUSER}-k8s-config
# To cleanup everything 
# kubectl delete namespace ${K8SNAMESPACE} 

