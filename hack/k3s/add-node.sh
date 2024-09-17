#!/usr/bin/env bash

K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/token)
API_SERVER_IP=$(hostname -I | cut -d ' ' -f 1)
API_SERVER_PORT=6443

cat <<EOF
# Run this command on a machine that should join as a worker
curl -sfL https://get.k3s.io | sh -s - agent \
  --token "${K3S_TOKEN}" \
  --server "https://${API_SERVER_IP}:${API_SERVER_PORT}"
EOF

cat <<EOF
# Run this command on the machine that should join as a control plane node
curl -sfL https://get.k3s.io | sh -s - server \
  --token ${K3S_TOKEN} \
  --server "https://${API_SERVER_IP}:${API_SERVER_PORT}" \
  --flannel-backend=none \
  --disable-kube-proxy \
  --disable servicelb \
  --disable-network-policy \
  --disable traefik
EOF
