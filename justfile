clusterName := "homelab"
clusterEndpoint := "https://192.168.178.201:6443"
nodes := "192.168.178.100 192.168.178.101 192.168.178.102"
talosDir := "talos"
talosVersion := "v1.9.1"

default:
  @just --list

#########
# SOPS
#######
encrypt:
  #!/usr/bin/env bash
  set -euo pipefail
  # Find all files ending with sops.yaml recursively from current directory
  find . -type f -name "*sops.yaml" ! -name ".sops.yaml" | while read -r file; do
    # Check if file is already encrypted by looking for sops metadata in the file
    if grep -q "^sops:" "$file"; then
        echo "Skipping already encrypted file: $file"
        continue
    fi

    if sops -e -i "$file"; then
        echo "Successfully encrypted: $file"
    else
        echo "Failed to encrypt: $file"
        exit 1
    fi
  done

#########
# Talos
#######
dashboard:
  talosctl dashboard --nodes $(echo {{ nodes }} | tr ' ' ',')

gen-secrets:
  talosctl gen secrets --output {{ talosDir }}/secrets.sops.yaml

gen-config:
  talosctl gen config --with-secrets {{ talosDir }}/secrets.sops.yaml {{ clusterName }} {{ clusterEndpoint }} --output {{ talosDir }}

get-schematic:
  #!/usr/bin/env bash
  set -euxo pipefail
  cat {{ talosDir}}/schematic.yaml
  schematic=$(curl -X POST --silent --data-binary @{{ talosDir }}/schematic.yaml https://factory.talos.dev/schematics | yq .id)
  echo factory.talos.dev/installer/$schematic:{{ talosVersion }}

apply-insecure node:
  sops -d {{ talosDir }}/{{ node }}.sops.yaml | talosctl apply-config --insecure --nodes {{ node }} --file /dev/stdin

bootstrap node:
  talosctl bootstrap --nodes {{node}} --endpoints {{ node }}

apply node:
  sops -d {{ talosDir }}/{{ node }}.sops.yaml | talosctl apply-config --nodes {{ node }} --file /dev/stdin

apply-reboot node:
  sops -d {{ talosDir }}/{{ node }}.sops.yaml | talosctl apply-config --nodes {{ node }} --file /dev/stdin --mode reboot

apply-all:
  #!/usr/bin/env bash
  set -euxo pipefail
  for node in {{ nodes }}; do
    sops -d ${node}.sops.yaml | talosctl apply-config --insecure --nodes $node --file /dev/stdin
  done

[confirm('Do you really want to reset this node?')]
reset node:
  talosctl reset --reboot --nodes {{ node }}

[confirm('Do you really want to hard reset this node?')]
reset-hard node:
  talosctl reset --graceful=false --reboot --nodes {{ node }}

[confirm('Do you really want to reset all nodes?')]
reset-all:
  #!/usr/bin/env bash
  set -euxo pipefail
  for node in {{ nodes }}; do
    talosctl reset --graceful=false --reboot --nodes $node
  done

upgrade node image:
  talosctl upgrade --nodes {{ node }} --image {{ image }}

upgrade-all image:
  #!/usr/bin/env bash
  set -euxo pipefail
  for node in {{ nodes }}; do
    talosctl upgrade --nodes $node --image {{ image }}
  done

health node:
  talosctl health --nodes {{ node }}

kubeconfig:
  talosctl kubeconfig --nodes {{ nodes }} {{ talosDir }}

services node:
  talosctl services --nodes {{ node }}

logs node service:
  talosctl logs --nodes {{ node }} {{ service }}

#########
# Bootstrap Apps
#######
bootstrap-apps:
  just bootstrap-cilium
  just bootstrap-onepassword
  just bootstrap-argocd

bootstrap-cilium:
  #!/usr/bin/env bash
  set -euxo pipefail

  APP_DIR="kubernetes/infrastructure/network/cilium"
  rm -rf $APP_DIR/charts

  kubectl kustomize --enable-helm $APP_DIR | kubectl apply -f -

bootstrap-onepassword:
  #!/usr/bin/env bash
  set -euxo pipefail

  kubectl apply kubernetes/infrastructure/workloads/onepassword/namespace.yaml
  sops -d bootstrap/onepassword/op-secrets.sops.yaml | kubectl apply -f -

  APP_DIR="kubernetes/infrastructure/workloads/onepassword"
  rm -rf $APP_DIR/charts
  kubectl kustomize --enable-helm $APP_DIR | kubectl apply -f -

bootstrap-argocd:
  #!/usr/bin/env bash
  set -euxo pipefail

  APP_DIR="kubernetes/infrastructure/workloads/argocd"
  rm -rf $APP_DIR/charts

  kubectl kustomize --enable-helm $APP_DIR | kubectl apply -f -

  # create the meta apps (root apps that apply all other apps)
  kubectl apply -k bootstrap/argo-apps
