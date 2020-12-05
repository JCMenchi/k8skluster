#!/bin/bash

# setup your login and account information before calling this script
#   az login  ...
#   az account set -s ACCOUNT_ID

RESGROUP=kluster
LOCATION=francecentral

VPCNAME=vpcprod
ADMINNAME=oper
ADMINPUBKEY=prod_rsa.pub

vmlist="prodetcd1 prodetcd2 prodetcd3 prodgluster1 prodgluster2 prodgluster3 prodcontrol1 prodcontrol2 prodcontrol3 prodworker1 prodworker2 prodworker3"
vmlist="prodcontrol1 prodcontrol2 prodcontrol3 prodworker1 prodworker2 prodworker3"

for vm in ${vmlist}; do
    echo "Stop ${vm}"
    az vm deallocate --no-wait -g ${RESGROUP} --name ${vm}
done

az vm deallocate --no-wait -g test --name jumpbox