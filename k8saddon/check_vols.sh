#!/bin/bash


for vol in $(kubectl get pv | grep Released | awk '{print $1}'); do 
    echo "$vol"
    volpath=$(kubectl describe pv "${vol}" | grep "Path:" | awk '{print $2;}')
    volhost=$(kubectl describe pv "${vol}" | grep "kubernetes.io/hostname" | awk '{print $5;}' | tr -d [])
    ssh "${volhost}" rm -rf "${volpath}"/*
    # shellcheck disable=SC2029
    ssh "${volhost}" ls "${volpath}"
    kubectl delete pv "${vol}"
done

kubectl apply -f volume.yaml
