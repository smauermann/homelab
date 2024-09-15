#!/usr/bin/env bash

helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

kubectl create namespace argocd
helm install argocd argo/argo-cd  --namespace argocd -f ../../kubernetes/argo-apps/values.yaml

kubectl apply -f app-project.yaml
kubectl apply -f root-app.yaml
