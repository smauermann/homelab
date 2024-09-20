#!/usr/bin/env bash

#kubectl create namespace onepassword
#kubectl create secret generic onepassword-credentials -n onepassword \
#  --from-literal=credentials=your-credentials-here \
#  --from-literal=token=your-token-here

kubectl kustomize --enable-helm ../kubernetes/infrastructure/workloads/onepassword | kubectl apply -f -
