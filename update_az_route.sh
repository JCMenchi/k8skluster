#!/bin/bash

# 
# this script call gobgp in kube-router to find the list of route to create in azure
#
# BEFORE CALLING THIS SCRIPT
# install azure cli and kubectl
#
# setup your login and account information before calling this script
#   az login  ...
#   az account set -s ACCOUNT_ID
#
# setup your authentication to the kubernetes cluster
#   ~/.kube/config must exists

# azure resource group
RESGROUP=KLUSTER

# find name of one of the kube-router
KROUTER_NAME=$(kubectl get --all-namespaces pod -l k8s-app=kube-router -o=custom-columns=NAME:.metadata.name  --no-headers=true | head -1)

# call gobgp to get list of routes in the form CIDR NEXT_HOP
declare -a ROUTE_CIDR
declare -a ROUTE_NEXT_HOP
# shellcheck disable=SC2207
ROUTE_CIDR=($(kubectl exec -it -n kube-system  "${KROUTER_NAME}" -- gobgp global rib | grep Origin | cut -d\  -f 2))
# shellcheck disable=SC2207
ROUTE_NEXT_HOP=($(kubectl exec -it -n kube-system  "${KROUTER_NAME}" -- gobgp global rib | grep Origin | cut -d\  -f 10))

nb=${#ROUTE_CIDR[@]}

for ((i=0;i<nb;i++)); do
  # check if route exists
  n=$(az network route-table route list -o table -g ${RESGROUP} --route-table-name k8sroutes | grep -c "${ROUTE_CIDR[$i]}")
  if [ "$n" = 1 ]; then
    # check if hop is the same
    n=$(az network route-table route list -o table -g ${RESGROUP} --route-table-name k8sroutes | grep "${ROUTE_CIDR[$i]}" | grep -c "${ROUTE_NEXT_HOP[$i]}")
    if [ "$n" = 1 ]; then
        echo "Route exist for ${ROUTE_CIDR[$i]} hoping to ${ROUTE_NEXT_HOP[$i]}"
    else
        # delete route
        ROUTE_NAME=k8sroute${ROUTE_NEXT_HOP[$i]}
        echo "Delete route ${ROUTE_NAME}"
        az network route-table route delete -g ${RESGROUP} --route-table-name k8sroutes -n "${ROUTE_NAME}"
        echo "Create route for ${ROUTE_CIDR[$i]} hoping to ${ROUTE_NEXT_HOP[$i]}"
        az network route-table route create -g ${RESGROUP} --route-table-name k8sroutes -n "${ROUTE_NAME}" \
           --next-hop-type VirtualAppliance --address-prefix "${ROUTE_CIDR[$i]}" --next-hop-ip-address "${ROUTE_NEXT_HOP[$i]}"
    fi
  else
    echo "Create route for ${ROUTE_CIDR[$i]} hoping to ${ROUTE_NEXT_HOP[$i]}"
    ROUTE_NAME=k8sroute${ROUTE_NEXT_HOP[$i]}
    az network route-table route create -g ${RESGROUP} --route-table-name k8sroutes -n "${ROUTE_NAME}" \
       --next-hop-type VirtualAppliance --address-prefix "${ROUTE_CIDR[$i]}" --next-hop-ip-address "${ROUTE_NEXT_HOP[$i]}"
  fi
done
