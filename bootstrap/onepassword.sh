#!/usr/bin/env bash

kubectl kustomize --enable-helm ../kubernetes/infrastructure/workloads/onepassword | kubectl apply -f -
