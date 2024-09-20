#!/usr/bin/env bash

#source .envrc
#
#kubectl create namespace onepassword
#kubectl create secret generic onepassword-credentials -n onepassword --from-literal=credentials=$credentials
#kubectl create secret generic onepassword-token -n onepassword --from-literal=token=$token

kubectl kustomize --enable-helm ../kubernetes/infrastructure/workloads/onepassword | kubectl apply -f -
