#!/bin/bash

# setup your login and account information before calling this script
#   az login  ...
#   az account set -s ACCOUNT_ID

RESGROUP=kluster
ADMRESGROUP=RG-ADM

vmlist="prodcontrol1 prodcontrol2 prodcontrol3 prodworker1 prodworker2 prodworker3 prodworker4 prodworker5"

for vm in ${vmlist}; do
    echo "Stop ${vm}"
    az vm deallocate --no-wait -g ${RESGROUP} --name "${vm}"
done

az vm deallocate --no-wait -g ${ADMRESGROUP} --name jumpbox