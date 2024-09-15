#!/usr/bin/env bash

NODE_NAME=$(hostname)
NODE_ROLE="worker"
if kubectl get node $NODE_NAME -o jsonpath='{.metadata.labels}' | grep -q "node-role.kubernetes.io/control-plane"; then
    NODE_ROLE="control"
fi
kubectl drain $NODE_NAME --ignore-daemonsets --delete-emptydir-data
kubectl delete node $NODE_NAME

if [ $NODE_ROLE = "control" ]; then
  /usr/local/bin/k3s-uninstall.sh
else
  /usr/local/bin/k3s-agent-uninstall.sh
fi

sudo ip link delete cilium_host
sudo ip link delete cilium_net
sudo ip link delete cilium_vxlan

rm /etc/cni/net.d
