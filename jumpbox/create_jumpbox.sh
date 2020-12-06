#!/bin/bash

# setup your login and account information before calling this script
#   az login  ...
#   az account set -s ACCOUNT_ID

# ----------------------------------------------------------------------
# Common variables
#

# Group and location
RESGROUP=RG-ADM
LOCATION=francecentral

VPCNAME=vpcadm
VPCIPPREFIX=12.0.0
VMNAME=jumpbox

DNSNAME=busterkeenadm

# VM login info
ADMINNAME=jboper
ADMINPRIVKEY=../keystore/azadm_rsa
ADMINPUBKEY=${ADMINPRIVKEY}.pub

# Create resource group if needed
v=$(az group exists --output json --name ${RESGROUP})
if [ "$v" = "false" ]; then
    az group create --name ${RESGROUP} --location ${LOCATION}
fi

# Check if a keypair exists, for VM login
if [ -e "${ADMINPRIVKEY}" ]; then
    echo "VM login keypair exists"
else
    echo "Generate VM login keypair"
    ssh-keygen -f ${ADMINPRIVKEY} -q -N ""
fi

#--------------------------------------------------------------------------------------------------------
# Create and setup VPC for admin
#
t=$(az network vnet show -n ${VPCNAME} --resource-group ${RESGROUP} > /dev/null 2>&1; echo $?)
if [ "$t" = 3 ]; then
    echo "Create VPC ${VPCNAME}"
    az network vnet create -n ${VPCNAME} --resource-group ${RESGROUP} --address-prefix ${VPCIPPREFIX}.0/8 --subnet-name adm2subnet \
       --subnet-prefix ${VPCIPPREFIX}.0/24 --location ${LOCATION} --tags zonetype=adm
else
    echo "VPC ${VPCNAME} exists."
fi

#--------------------------------------------------------------------------------------------------------
# Create jumpbox VM
#

t=$(az vm show -g ${RESGROUP} -n ${VMNAME} > /dev/null 2>&1; echo $?)
if [ "$t" = 3 ]; then
    
    t=$(az network public-ip list --resource-group ${RESGROUP} | grep -c jb-publicip)
    if [ "$t" = 0 ]; then
        echo "Create Public IP"
        az network public-ip create --resource-group ${RESGROUP} --name jb-publicip \
          --allocation-method Static --sku Standard --dns-name ${DNSNAME}
    else
        echo "Public IP exists"
    fi

    echo "Create ${VMNAME}"
    
    az vm create --resource-group ${RESGROUP} --name ${VMNAME} --location ${LOCATION} --image UbuntuLTS \
    --size Standard_B1s --private-ip-address ${VPCIPPREFIX}.5 --public-ip-address jb-publicip \
    --vnet-name ${VPCNAME} --subnet adm2subnet --admin-username ${ADMINNAME}  \
    --ssh-key-value @${ADMINPUBKEY} --authentication-type ssh --tags zonetype=adm

else
    
    state=$(az vm get-instance-view --resource-group ${RESGROUP} --name ${VMNAME} --query instanceView.statuses[1].displayStatus --output json)
    echo "${VMNAME} exists: ${state}"
    if [ "${state}" == "\"VM deallocated\"" ]; then
        echo "   start vm..."
        az vm start --no-wait --resource-group ${RESGROUP} --name ${VMNAME}
    fi
fi