#!/usr/bin/env bash

kubectl kustomize --enable-helm ../kubernetes/infrastructure/network/cilium | kubectl apply -f -

cilium status --wait
