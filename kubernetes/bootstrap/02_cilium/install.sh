#!/usr/bin/env bash

if ! command -v helm &> /dev/null; then
  echo "helm not found, installing ..."
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

helm repo add cilium https://helm.cilium.io/
helm repo update

if ! command -v cilium &> /dev/null; then
  echo "cilium cli not found, installing ..."
  CILIUM_CLI_VERSION=$(curl -s https://raw.githubusercontent.com/cilium/cilium-cli/main/stable.txt)
  CLI_ARCH=amd64
  curl -L --fail --remote-name-all https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-${CLI_ARCH}.tar.gz
  sudo tar xzvfC cilium-linux-${CLI_ARCH}.tar.gz /usr/local/bin
  rm cilium-linux-${CLI_ARCH}.tar.gz
fi

cilium install -f values.yaml

cilium status --wait

