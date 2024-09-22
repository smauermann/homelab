#!/usr/bin/env bash

set -ex

kubectl kustomize --enable-helm ../kubernetes/infrastructure/workloads/argocd | kubectl apply -f -

# create the meta apps (root apps that apply all other apps)
kubectl apply -k ../kubernetes/meta

# we don't want that pesky % sign at the end of the password output
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
