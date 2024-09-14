#!/usr/bin/env bash

K3S_TOKEN=$(sudo cat /var/lib/rancher/k3s/server/token)
API_SERVER_IP=$(hostname -I | cut -d ' ' -f 1)
API_SERVER_PORT=6443

cat <<EOF
# Run this command on the node that should join as an agent
curl -sfL https://get.k3s.io | sh -s - agent \
  --token "${K3S_TOKEN}" \
  --server "https://${API_SERVER_IP}:${API_SERVER_PORT}"
EOF
