#!/usr/bin/env bash

# install k3s with flannel disabled since we are going to use cilium
 curl -sfL https://get.k3s.io | sh -s - \
   --write-kubeconfig-mode='0600' \
   --flannel-backend=none \
   --disable-kube-proxy \
   --disable servicelb \
   --disable-network-policy \
   --disable traefik \
   --disable-helm-controller \
   --cluster-init

# cp kubeconfig to the standard location
mkdir -p $HOME/.kube
sudo cp -i /etc/rancher/k3s/k3s.yaml $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
