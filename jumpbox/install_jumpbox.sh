#!/bin/bash

# Run this script with root privilege
#

#--------------------------------------------------------------------------
# update base OS
apt update
apt upgrade

# install common prerequisite
apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg apache2-utils

#--------------------------------------------------------------------------
# install ansible
apt-add-repository ppa:ansible/ansible
apt update
apt install -y ansible

#--------------------------------------------------------------------------
# install kubectl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt update
apt install -y kubeadm kubectl

#--------------------------------------------------------------------------
# install Azure cli
curl -sL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list

apt-get update
apt-get install -y azure-cli

#--------------------------------------------------------------------------
# Install CFSSL

if [ -e /bin/cfssl ]; then
    echo "CFSSl already installed"
else
    curl -s -L -o /bin/cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
    curl -s -L -o /bin/cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
    chmod +x /bin/cfssl*
fi

t=$(grep -q prodcontrol1 /etc/hosts; echo $?)
if [ $t == 1 ]; then
    echo "Edit /etc/hosts"
    echo "11.0.0.20 prodcontrol1" >> /etc/hosts
    echo "11.0.0.21 prodcontrol2" >> /etc/hosts
    echo "11.0.0.22 prodcontrol3" >> /etc/hosts
    echo "" >> /etc/hosts
    echo "11.0.0.30 prodworker1" >> /etc/hosts
    echo "11.0.0.31 prodworker2" >> /etc/hosts
    echo "11.0.0.32 prodworker3" >> /etc/hosts
    echo "11.0.0.33 prodworker4" >> /etc/hosts
    echo "11.0.0.34 prodworker5" >> /etc/hosts
fi

t=$(grep -q prodcontrol1 /etc/ansible/hosts; echo $?)
if [ $t == 1 ]; then
    echo edit ansible /etc/ansible/hosts
    echo "[etcd]" >> /etc/ansible/hosts
    echo "prodcontrol1" >> /etc/ansible/hosts
    echo "prodcontrol2" >> /etc/ansible/hosts
    echo "prodcontrol3" >> /etc/ansible/hosts
    echo "" >> /etc/ansible/hosts
    echo "[k8s]" >> /etc/ansible/hosts
    echo "prodcontrol1" >> /etc/ansible/hosts
    echo "prodcontrol2" >> /etc/ansible/hosts
    echo "prodcontrol3" >> /etc/ansible/hosts
    echo "prodworker1" >> /etc/ansible/hosts
    echo "prodworker2" >> /etc/ansible/hosts
    echo "prodworker3" >> /etc/ansible/hosts
    echo "prodworker4" >> /etc/ansible/hosts
    echo "prodworker5" >> /etc/ansible/hosts
    echo "" >> /etc/ansible/hosts
    echo "[k8smaster]" >> /etc/ansible/hosts
    echo "prodcontrol1" >> /etc/ansible/hosts
    echo "" >> /etc/ansible/hosts
    echo "[k8scontrol]" >> /etc/ansible/hosts
    echo "prodcontrol2" >> /etc/ansible/hosts
    echo "prodcontrol3" >> /etc/ansible/hosts
    echo "" >> /etc/ansible/hosts
    echo "[k8sworker]" >> /etc/ansible/hosts
    echo "prodworker1" >> /etc/ansible/hosts
    echo "prodworker2" >> /etc/ansible/hosts
    echo "prodworker3" >> /etc/ansible/hosts
    echo "prodworker4" >> /etc/ansible/hosts
    echo "prodworker5" >> /etc/ansible/hosts
fi

#--------------------------------------------------------------------------
# Add 2-factor authentication
apt install -y libpam-google-authenticator

# As normal user run:
#       google-authenticator -t -d -f -r 3 -R 30 -W
# edit /etc/pam.d/sshd  add the following line at the begining
#   auth sufficient pam_google_authenticator.so
#
# edit /etc/ssh/sshd_config
#   ChallengeResponseAuthentication yes
#   UsePAM yes
#   AuthenticationMethods publickey,keyboard-interactive
#
# cf https://systemoverlord.com/2018/03/03/openssh-two-factor-authentication-but-not-service-accounts.html
#

# end
echo "Everything is setup. Next step as normal user:"
echo ""
echo " - connect to azure account"
echo "     az login  ..."
echo "     az account set -s ACCOUNT_ID"
echo ""
echo " - setup 2-Factor auth (Optional)"
echo ""
echo " - add env var with secrets"
echo "     DOCKER_REGISTRY_SERVER DOCKER_USER DOCKER_PASSWORD"
echo "     SLACK_WEBHOOK_API KLUSTER_LOGGING_PWD KLUSTER_MONITORING_PWD"
