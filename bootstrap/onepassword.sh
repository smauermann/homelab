#!/usr/bin/env bash

set -e

kubectl create namespace onepassword
cat 1password-credentials.json | base64 | tr -d \\n > credentials.b64
kubectl -n onepassword create secret generic onepassword-credentials --from-file credentials=credentials.b64
kubectl -n onepassword create secret generic onepassword-token --from-file token=token.txt

kubectl kustomize --enable-helm ../kubernetes/infrastructure/workloads/onepassword | kubectl apply -f -

