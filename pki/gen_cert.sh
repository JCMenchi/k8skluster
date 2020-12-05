#!/bin/bash

# Packages needed:
#  - openssl
#  - cfssl, cfssljson

# Main variables
VERBOSE=0
CA_ROOT_DIR=${1:-./root}

declare -a ETCD_HOST_NAMES
declare -a ETCD_HOST_IP

ETCD_HOST_NAMES=(prodcontrol1 prodcontrol2 prodcontrol3)
ETCD_HOST_IP=(11.0.0.20 11.0.0.21 11.0.0.22)

KLUSTER_FQDN=busterkeen.francecentral.cloudapp.azure.com 
KLUSTER_PUBLIC_IP=20.40.132.148

function init_ca () {
  # check if folder exists
  if [ -e "${CA_ROOT_DIR}/root-ca-key.pem" ]; then
    echo "CA root '${CA_ROOT_DIR}' exists."
  else 
    echo "Create CA root"
    # ceate Root CA
    cfssl gencert -initca ${CA_ROOT_DIR}/root-ca-csr.json | cfssljson -bare ${CA_ROOT_DIR}/root-ca
    rm ${CA_ROOT_DIR}/root-ca.csr
  fi

  # DEBUG
  if [ ${VERBOSE} -eq 1 ]; then
    openssl x509 -in ${CA_ROOT_DIR}/root-ca.pem -text -noout
    openssl pkey -in ${CA_ROOT_DIR}/root-ca-key.pem -text -noout
  fi
}

function generate_cert () {
  local PROFILE=${1:-server}
  local SERVER_NAME=${2:-myserver}
  local SERVER_IP=${3:-127.0.0.1}
  
  # Check if certificate exists
  if [ -e ../keystore/${SERVER_NAME}_${PROFILE}.crt ]; then
    echo "Certificate ${SERVER_NAME}_${PROFILE}.crt exists."
    return 1
  else 
    echo "Create certificate ${SERVER_NAME}_${PROFILE}.crt."
  fi

  # prepare request for server certificate
  cat > /tmp/cert.csr.json <<CERT_SIGN_REQ_EOF
  {
    "CN": "${SERVER_NAME}",
    "hosts": [
      "${SERVER_NAME}",
      "11.0.0.20",
      "11.0.0.21",
      "11.0.0.22"
    ],
    "key": {
      "algo": "rsa",
      "size": 4096
    },
    "names": [
      {
        "C": "FR",
        "L": "Velizy",
        "O": "IKSTEST",
        "OU": "cloud"
      }
    ]
  }
CERT_SIGN_REQ_EOF

  cfssl gencert -ca=${CA_ROOT_DIR}/root-ca.pem -ca-key=${CA_ROOT_DIR}/root-ca-key.pem -config=config.json -profile=${PROFILE} /tmp/cert.csr.json | cfssljson -bare ${SERVER_NAME}

  # DEBUG
  if [ ${VERBOSE} -eq 1 ]; then
    openssl x509 -in ${SERVER_NAME}.pem -text -noout
    openssl pkey -in ${SERVER_NAME}-key.pem -text -noout
  fi

  # PEM
  mv ${SERVER_NAME}.pem ../keystore/${SERVER_NAME}_${PROFILE}.crt
  mv ${SERVER_NAME}-key.pem ../keystore/${SERVER_NAME}_${PROFILE}.key

  # cleanup
  rm /tmp/cert.csr.json
  rm ${SERVER_NAME}.csr
}

function generate_client_cert () {
  local CLIENT_NAME=${1:-client}
  
  # Check if certificate exists
  if [ -e ../keystore/${CLIENT_NAME}.crt ]; then
    echo "Certificate ${CLIENT_NAME}.crt exists."
    return 1
  else 
    echo "Create certificate ${CLIENT_NAME}.crt."
  fi

  # prepare request for server certificate
  cat > /tmp/cert.csr.json <<CERT_SIGN_REQ_EOF
  {
    "CN": "${CLIENT_NAME}",
    "hosts": [""],
    "key": {
      "algo": "rsa",
      "size": 2048
    },
    "names": [
      {
        "C": "FR",
        "L": "Velizy",
        "O": "IKSTEST",
        "OU": "cloud"
      }
    ]
  }
CERT_SIGN_REQ_EOF

  cfssl gencert -ca=${CA_ROOT_DIR}/root-ca.pem -ca-key=${CA_ROOT_DIR}/root-ca-key.pem -config=config.json -profile=client /tmp/cert.csr.json | cfssljson -bare ${CLIENT_NAME}

  # DEBUG
  if [ ${VERBOSE} -eq 1 ]; then
    openssl x509 -in ${CLIENT_NAME}.pem -text -noout
    openssl pkey -in ${CLIENT_NAME}-key.pem -text -noout
  fi

  # PEM
  mv ${CLIENT_NAME}.pem ../keystore/${CLIENT_NAME}.crt
  mv ${CLIENT_NAME}-key.pem ../keystore/${CLIENT_NAME}.key

  # cleanup
  rm /tmp/cert.csr.json
  rm ${CLIENT_NAME}.csr
}

# prepare folder
if [ -e ../keystore ]; then
  echo "keystore folder exists"
else
  mkdir ../keystore
fi

# Create Root CA config
init_ca

# generate certificate for ingress
generate_cert server ${KLUSTER_FQDN} ${KLUSTER_PUBLIC_IP}

# Generate certificates and key for ETCD cluster
nb=${#ETCD_HOST_NAMES[@]}

for ((i=0;i<$nb;i++)); do
  etcdhost=${ETCD_HOST_NAMES[i]}
 
  if [ -e ../playbook/roles/etcd/files/${etcdhost} ]; then
    echo "Certificates exist for ${etcdhost}"
  else
    generate_cert server ${ETCD_HOST_NAMES[i]} ${ETCD_HOST_IP[i]}
    generate_cert peer ${ETCD_HOST_NAMES[i]} ${ETCD_HOST_IP[i]}
    echo "Copy certificates for ${etcdhost}"
    mkdir ../playbook/roles/etcd/files/${etcdhost}
    cp ../keystore/${etcdhost}_server.crt ../playbook/roles/etcd/files/${etcdhost}/server.crt
    cp ../keystore/${etcdhost}_server.key ../playbook/roles/etcd/files/${etcdhost}/server.key
    cp ../keystore/${etcdhost}_peer.crt ../playbook/roles/etcd/files/${etcdhost}/peer.crt
    cp ../keystore/${etcdhost}_peer.key ../playbook/roles/etcd/files/${etcdhost}/peer.key
    cp root/root-ca.pem ../playbook/roles/etcd/files/${etcdhost}/ca.crt
  fi
done

# Generate certificate and key for clients of ETCD cluster
generate_client_cert etcd_client

# copy etcd client certificates for kubeadm
for role in k8smaster k8scontrol; do
  if [ -e ../playbook/roles/${role}/files/apiserver-etcd-client.crt ]; then
    echo "Certificates exist for kubeadm"
  else
    echo "Copy certificates for kubeadm"
    if [ -e ../playbook/roles/${role}/files ]; then
      echo ""
    else
      mkdir ../playbook/roles/${role}/files
    fi
    if [ -e ../playbook/roles/${role}/files/etcd ]; then
      echo ""
    else
      mkdir ../playbook/roles/${role}/files/etcd
    fi
    cp ../keystore/etcd_client.crt ../playbook/roles/${role}/files/apiserver-etcd-client.crt
    cp ../keystore/etcd_client.key ../playbook/roles/${role}/files/apiserver-etcd-client.key
    cp root/root-ca.pem ../playbook/roles/${role}/files/etcd/ca.crt
  fi
done
