#!/usr/bin/env bash

set -e

# setup onepassword credentials (connect to 1password auth) and token (operator to connect auth)
kubectl create namespace onepassword
cat 1password-credentials.json | base64 | tr -d \\n > credentials.b64
kubectl -n onepassword create secret generic onepassword-credentials --from-file credentials=credentials.b64
rm credentials.b64
kubectl -n onepassword create secret generic onepassword-token --from-env-file token.env

kubectl kustomize --enable-helm ../kubernetes/infrastructure/workloads/onepassword | kubectl apply -f -

