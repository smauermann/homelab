#!/usr/bin/env bash

# clean up old charts
APP_DIR="../kubernetes/infrastructure/network/cilium"
rm -rf $APP_DIR/charts

kubectl kustomize --enable-helm $APP_DIR | kubectl apply -f -

cilium status --wait
