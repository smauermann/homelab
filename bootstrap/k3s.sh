#!/usr/bin/env bash

# copy k3s config to the correct place
cp config/k3s.yaml /etc/rancher/k3s/config.yaml

# install k3s
curl -sfL https://get.k3s.io | sh -s - --cluster-init

# cp kubeconfig to the standard location
mkdir -p $HOME/.kube
sudo cp -i /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
