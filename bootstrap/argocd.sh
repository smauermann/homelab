#!/usr/bin/env bash

set -ex

# clean up old charts
APP_DIR="../kubernetes/infrastructure/workloads/argocd"
rm -rf $APP_DIR/charts

kubectl kustomize --enable-helm $APP_DIR | kubectl apply -f -

# create the meta apps (root apps that apply all other apps)
kubectl apply -k ../kubernetes/meta

# we don't want that pesky % sign at the end of the password output
cat <<EOF
To get the admin secret run the following command. It takes some time before the secret becomes available (~1m).
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath={.data.password} | base64 -d; echo
EOF
