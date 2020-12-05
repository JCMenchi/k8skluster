#!/bin/bash

# setup your login and account information before calling this script
#   az login  ...
#   az account set -s ACCOUNT_ID
#
# this script assume that a jumpbox exists and is configured
# the jumpbox is in the test resource group.
# A VPC named vpcadm is supposed to exist too.
#
# This can be replaced by terraform in the future,
# but before we need to understand what is possible with azure.
#

# ----------------------------------------------------------------------
# Common variables
#

declare -a CONTROLLER_HOST_NAMES
declare -a WORKER_HOST_NAMES

CONTROLLER_HOST_NAMES=(prodcontrol1 prodcontrol2 prodcontrol3)
WORKER_HOST_NAMES=(prodworker1 prodworker2 prodworker3 prodworker4 prodworker5)

# Group and location
RESGROUP=KLUSTER
LOCATION=francecentral

ADMRESGROUP=RG-ADM

# VM Virtual Network
VPCNAME=vpcprod
ADMVPC=vpcadm

# VM login info
ADMINNAME=oper
ADMINPRIVKEY=keystore/prod_rsa
ADMINPUBKEY=${ADMINPRIVKEY}.pub

# ----------------------------------------------------------------------
# Everything is now based on variables set above. 
#

# ----------------------------------------------------------------------
# Check for pre requisite 
#

# check for admin resource group
# az group exists --name RG-ADM

t=$(az network vnet show --resource-group ${ADMRESGROUP} --name ${ADMVPC} --query id --out tsv > /dev/null 2>&1; echo $?)
if [ "$t" = 0 ]; then
    echo "Admin VPC exists"
else
    echo "please create admin VPC ${ADMVPC}"
    exit 1
fi

state=$(az vm get-instance-view --resource-group ${ADMRESGROUP} --name jumpbox --query instanceView.statuses[1].displayStatus --output json)
echo "jumpbox exists: ${state}"
if [ "${state}" == "\"VM deallocated\"" ]; then
    echo "   start vm..."
    az vm start --no-wait --resource-group ${ADMRESGROUP} --name jumpbox
else

    if [ "${state}" == "\"VM running\"" ]; then
        echo "  jumpbox is running"
    else
        echo "please create jumpbox VM"
        exit 2
    fi

fi

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


# Standard_B1s
# Standard_B2s

create_vm_if_needed () {
    
    vmname=$1
    vmip=$2
    vmtype=$3
    avset=$4
    vmrole=$5
    
    t=$(az vm show -g ${RESGROUP} -n "${vmname}" > /dev/null 2>&1; echo $?)
    if [ "$t" = 3 ]; then
        echo "Create ${vmname}"
        # use --storage-sku Standard_LRS to create standard HDD instead of SDD
        az vm create --resource-group ${RESGROUP} --name "${vmname}" --location ${LOCATION} --image UbuntuLTS \
        --availability-set "${avset}" --size "${vmtype}" --private-ip-address "${vmip}" --public-ip-address "" \
        --vnet-name ${VPCNAME} --subnet k8ssubnet  --admin-username ${ADMINNAME}  \
        --ssh-key-value @${ADMINPUBKEY} --authentication-type ssh --tags zonetype=prod role="${vmrole}"

        # ssh is disabled outside the VPC, only jumpbox can used ssh
        az network nsg rule delete --resource-group ${RESGROUP} --nsg-name "${vmname}"NSG -n default-allow-ssh 
    else
        
        state=$(az vm get-instance-view --resource-group ${RESGROUP} --name "${vmname}" --query instanceView.statuses[1].displayStatus --output json)
        echo "${vmname} exists: ${state}"
        if [ "${state}" == "\"VM deallocated\"" ]; then
            echo "   start vm..."
            az vm start --no-wait --resource-group ${RESGROUP} --name "${vmname}"
        fi
    fi
    
}

create_avset_if_needed () {
    
    avset=$1
    
    t=$(az vm availability-set show -n "${avset}" --resource-group ${RESGROUP} > /dev/null 2>&1; echo $?)
    if [ "$t" = 3 ]; then
        echo "Create availibility set ${avset}"
        az vm availability-set create -n "${avset}" --resource-group ${RESGROUP} --location ${LOCATION} --tags zonetype=prod
    else
        echo "Availibility set ${avset} exists."
    fi
}

#--------------------------------------------------------------------------------------------------------
# Create and setup VPC for k8S kluster
#
t=$(az network vnet show -n ${VPCNAME} --resource-group ${RESGROUP} > /dev/null 2>&1; echo $?)
if [ "$t" = 3 ]; then
    echo "Create VPC ${VPCNAME}"
    az network vnet create -n ${VPCNAME} --resource-group ${RESGROUP} --address-prefix 11.0.0.0/8 --subnet-name k8ssubnet \
       --subnet-prefix 11.0.0.0/24 --location ${LOCATION} --tags zonetype=prod
else
    echo "VPC ${VPCNAME} exists."
fi

# set up access between admin VPC and k8s VPC
t=$(az network vnet peering show -n prod2adm --vnet-name ${VPCNAME} --resource-group ${RESGROUP} > /dev/null 2>&1; echo $?)
if [ "$t" = 3 ]; then
    echo "Create VPC peering"
    # search for existing admin VPC
    vpcadmid=$(az network vnet show --resource-group ${ADMRESGROUP} --name vpcadm --query id --out tsv)

    vpcprodid=$(az network vnet show --resource-group ${RESGROUP} --name ${VPCNAME} --query id --out tsv)

    az network vnet peering create --name adm2prod --remote-vnet "${vpcprodid}" \
    --resource-group ${ADMRESGROUP} --vnet-name ${ADMVPC} --allow-vnet-access

    az network vnet peering create --name prod2adm --remote-vnet "${vpcadmid}" \
    --resource-group ${RESGROUP} --vnet-name ${VPCNAME} --allow-vnet-access
    
else
    echo "VPC peering exists."
fi

# create route table
t=$(az network route-table show --resource-group ${RESGROUP} --name k8sroutes > /dev/null 2>&1; echo $?)
if [ "$t" = 3 ]; then
    echo "Create route table"
    az network route-table create --name k8sroutes --resource-group ${RESGROUP} --location ${LOCATION}
    az network vnet subnet update -g ${RESGROUP} -n k8ssubnet --vnet-name ${VPCNAME} --route-table k8sroutes

else
    echo "Route table exists."
fi

#--------------------------------------------------------------------------------------------------------
# Create and setup VM for k8S kluster
#

create_avset_if_needed k8scontrol_avset
create_avset_if_needed k8sworker_avset

nb=${#CONTROLLER_HOST_NAMES[@]}
for ((i=0;i<nb;i++)); do
    controllerhost=${CONTROLLER_HOST_NAMES[i]}
    
    create_vm_if_needed "${controllerhost}" 11.0.0.$((20 + i)) Standard_B2s k8scontrol_avset k8scontrol
done

nb=${#WORKER_HOST_NAMES[@]}
for ((i=0;i<nb;i++)); do
    workerhost=${WORKER_HOST_NAMES[i]}
    create_vm_if_needed "${workerhost}" 11.0.0.$((30 + i)) Standard_B2s k8sworker_avset k8sworker
done

#--------------------------------------------------------------------------------------------------------
# Create and setup Load Balancer for k8S kluster
#

# Public IP busterkeen.francecentral.cloudapp.azure.com
t=$(az network public-ip list --resource-group ${RESGROUP} | grep -c klb-publicip)
if [ "$t" = 0 ]; then
    echo "Create Public IP"
    az network public-ip create --resource-group ${RESGROUP} --name klb-publicip --allocation-method Static \
       --sku Standard --dns-name busterkeen
else
    echo "Public IP exists"
fi

# Public IP busterkeenpro.francecentral.cloudapp.azure.com
t=$(az network public-ip list --resource-group ${RESGROUP} | grep -c klbadm-publicip)
if [ "$t" = 0 ]; then
    echo "Create Public IP for k8s adm"
    az network public-ip create --resource-group ${RESGROUP} --name klbadm-publicip --allocation-method Static \
       --sku Standard --dns-name busterkeenpro
else
    echo "K8S admin Public IP exists"
fi

t=$(az network lb show -n klb --resource-group ${RESGROUP} > /dev/null 2>&1; echo $?)
if [ "$t" = 3 ]; then
    echo "Create Load Balancer"
    # LB frontend
    az network lb create --name klb --resource-group ${RESGROUP} --sku Standard \
       --location ${LOCATION} --public-ip-zone 1 --public-ip-address klb-publicip \
       --backend-pool-name klbhttpbackend --frontend-ip-name klbfrontend
    
    # create def for http for nginx ingress on NodePort 31080
    # az network lb address-pool create --resource-group ${RESGROUP} --lb-name klb --name klbhttpbackend

    # az network lb probe create --resource-group ${RESGROUP} --lb-name klb --name http-probe --protocol tcp --port 31080
                                  
    # az network lb rule create --resource-group ${RESGROUP} --lb-name klb --name K8SLoadBalancerRuleHttp \
    #    --protocol tcp --frontend-port 80 --backend-port 31080 --frontend-ip-name klbfrontend \
    #    --backend-pool-name klbhttpbackend --probe-name http-probe

    # create def for https 443 frontend -> 31443 backend (nginx pod)
    az network lb address-pool create --resource-group ${RESGROUP} --lb-name klb --name klbhttpsbackend

    az network lb probe create --resource-group ${RESGROUP} --lb-name klb --name https-probe --protocol tcp --port 31443
    
    az network lb rule create --resource-group ${RESGROUP} --lb-name klb --name K8SLoadBalancerRuleHttps \
       --protocol tcp --frontend-port 443 --backend-port 31443 --frontend-ip-name klbfrontend \
       --backend-pool-name klbhttpsbackend --probe-name https-probe
    
    # create def for k8s admin 6443
    az network lb address-pool create --resource-group ${RESGROUP} --lb-name klb --name k8sbackend

    az network lb probe create --resource-group ${RESGROUP} --lb-name klb --name kpr-probe --protocol tcp --port 6443
    
    az network lb frontend-ip create --name klbadmfrontend --lb-name klb --resource-group ${RESGROUP} \
       --public-ip-address klbadm-publicip
    
    az network lb rule create --resource-group ${RESGROUP} --lb-name klb --name K8SLoadBalancerRuleK8Sadm \
       --protocol tcp --frontend-port 443 --backend-port 6443 --frontend-ip-name klbadmfrontend \
       --backend-pool-name k8sbackend --probe-name kpr-probe

else
    echo "Load Balancer exists."
fi

# Add VM to pool
update_backend_pool () {
    poolname=$1
    vmname=$2

    vm1=$(az network lb address-pool show --resource-group ${RESGROUP} --lb-name klb --name "${poolname}" --query backendIpConfigurations --output tsv | grep -c "${vmname}"VMNic)
    if [ "$vm1" = 0 ]; then
        echo "Add VM ${vmname} to pool ${poolname}"
        az network nic ip-config address-pool add --address-pool "${poolname}" \
           --lb-name klb --resource-group ${RESGROUP} --nic-name "${vmname}"VMNic \
           --ip-config-name ipconfig"${vmname}"
    fi
}

nb=${#CONTROLLER_HOST_NAMES[@]}
for ((i=0;i<nb;i++)); do
    controllerhost=${CONTROLLER_HOST_NAMES[i]}
    # for k8s admin
    update_backend_pool k8sbackend "${controllerhost}"
    # ingress may run on any node
    update_backend_pool klbhttpsbackend "${controllerhost}"
done

nb=${#WORKER_HOST_NAMES[@]}
for ((i=0;i<nb;i++)); do
    workerhost=${WORKER_HOST_NAMES[i]}
    update_backend_pool klbhttpsbackend "${workerhost}"
done

# tune security group
# external ssh can be disabled for all VM except jumpbox
# allow HTTP HTTPS and K8S cli
update_nsg_control () {
    vmname=$1
    port=$2
    priority=$3

    ipforwarding=$(az network nic show -g ${RESGROUP} --name "${vmname}"VMNic --query enableIpForwarding --out tsv)
    if [ "${ipforwarding}" = "false" ]; then
        echo "Activate IP forwarding for ${vmname}VMNic"
        az network nic update --resource-group ${RESGROUP} --name "${vmname}"VMNic --ip-forwarding true
    fi

    n=$(az network nsg rule list --resource-group ${RESGROUP} --nsg-name "${vmname}"NSG | grep -c default-allow-ssh)
    if [ "$n" = 1 ]; then
        az network nsg rule delete --resource-group ${RESGROUP} --nsg-name "${vmname}"NSG -n default-allow-ssh 
    fi

    n=$(az network nsg rule list --resource-group ${RESGROUP} --nsg-name "${vmname}"NSG | grep -c allow_port_"${port}")
    if [ "$n" = 0 ]; then
        az network nsg rule create --resource-group ${RESGROUP} --nsg-name "${vmname}"NSG --name allow_port_"${port}" \
           --priority "${priority}" --source-address-prefixes Internet --destination-port-ranges "${port}" \
           --access Allow --protocol Tcp
    fi
}

nb=${#CONTROLLER_HOST_NAMES[@]}
for ((i=0;i<nb;i++)); do
    controllerhost=${CONTROLLER_HOST_NAMES[i]}
    update_nsg_control "${controllerhost}" 31443 501
    update_nsg_control "${controllerhost}" 6443 502
    update_nsg_control "${controllerhost}" 80 503
done

nb=${#WORKER_HOST_NAMES[@]}
for ((i=0;i<nb;i++)); do
    workerhost=${WORKER_HOST_NAMES[i]}
    update_nsg_control "${workerhost}" 31443 501
done
