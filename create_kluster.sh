#!/bin/bash

# run all command to create a working kluster
# with admin app

# Check needed variables
n=0
for v in DOCKER_REGISTRY_SERVER DOCKER_USER DOCKER_PASSWORD SLACK_WEBHOOK_API KLUSTER_LOGGING_PWD KLUSTER_MONITORING_PWD; do
    if [[ ! -v ${v} ]]; then
        echo "${v} is unset"
        n=$((n + 1))
    fi
done

if [ $n -gt 0 ]; then
    echo "FATAL: Set env var before creating cluster"
    exit 1
fi

# Check azure connection
res=$(az group list > /dev/null 2>/dev/null; echo $?)
if [ $res = 1 ]; then
    echo "FATAL: No connection to azure. (az login)"
    exit 2
fi

# ready to go
if [ ! -e keystore ]; then
    mkdir keystore
fi
cd pki
./gen_cert.sh
cd ..

# create IaaS
./create_vm.sh

# use kubeadm to generate certificates
if [ ! -e pki/ca.key ]; then
    kubeadm init phase certs --cert-dir $(pwd)/pki ca
    kubeadm init phase certs --cert-dir $(pwd)/pki front-proxy-ca
    kubeadm init phase certs --cert-dir $(pwd)/pki sa

    cp pki/ca.* pki/sa.* pki/front-proxy-ca.* playbook/roles/k8scontrol/files
    cp pki/ca.* pki/sa.* pki/front-proxy-ca.* playbook/roles/k8smaster/files

    kubeadm init phase kubeconfig admin --control-plane-endpoint=busterkeenpro.francecentral.cloudapp.azure.com \
                      --cert-dir=$(pwd)/pki --kubeconfig-dir=$(pwd)
    if [ ! -e ${HOME}/.kube ]; then
        mkdir ${HOME}/.kube
    fi
    mv admin.conf ${HOME}/.kube/config
fi

#  copy private key to connect to host
# add ssh config file
cp keystore/prod_rsa ${HOME}/.ssh
if [ ! -e ${HOME}/.ssh/config ]; then
    echo "Host prodcontrol*" > ${HOME}/.ssh/config
    echo "    User oper" >> ${HOME}/.ssh/config
    echo "    IdentityFile ~/.ssh/prod_rsa" >> ${HOME}/.ssh/config
    echo "" >> ${HOME}/.ssh/config
    echo "Host prodworker*" >> ${HOME}/.ssh/config
    echo "    User oper" >> ${HOME}/.ssh/config
    echo "    IdentityFile ~/.ssh/prod_rsa" >> ${HOME}/.ssh/config
fi

export ANSIBLE_HOST_KEY_CHECKING=False
# configure OS and deploy k8s
ansible-playbook playbook/site.yml -e 'ansible_python_interpreter=/usr/bin/python3'
# give sometime to nodes to join the cluster
sleep 60

# update azure routing table for kuberouter
./update_az_route.sh

# install admin app
cd k8saddon
./install_addons.sh
cd ..

# reupdate azure routing table for kuberouter
./update_az_route.sh
