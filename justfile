set dotenv-load
set dotenv-path := "talos/cluster.env"

clusterName := "homelab"
clusterEndpoint := "https://192.168.178.201:6443"
nodes := "192.168.178.100 192.168.178.101 192.168.178.102"
talosDir := "talos"

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

@get-schematic:
  curl -X POST --silent --data-binary @{{ talosDir }}/schematic.yaml https://factory.talos.dev/schematics | yq .id

get-talos-image:
  #!/usr/bin/env bash
  SCHEMATIC=$(just get-schematic)
  echo -n factory.talos.dev/installer/${SCHEMATIC}:${TALOS_VERSION}

parse-machine-config node:
  #!/usr/bin/env bash
  SCHEMATIC=$(just get-schematic)
  sops -d {{ talosDir }}/{{ node }}.sops.yaml | sed -e "s|\$SCHEMATIC|$SCHEMATIC|g" -e "s|\$TALOS_VERSION|$TALOS_VERSION|g" -e "s|\$KUBERNETES_VERSION|$KUBERNETES_VERSION|g"

apply-insecure node:
  just parse-machine-config {{ node }} | talosctl apply-config --insecure --nodes {{ node }} --file /dev/stdin

bootstrap node:
  talosctl bootstrap --nodes {{node}} --endpoints {{ node }}

apply node:
  just parse-machine-config {{ node }} | talosctl apply-config --nodes {{ node }} --file /dev/stdin && just health {{ node }}

apply-reboot node:
  just parse-machine-config {{ node }} | talosctl apply-config --nodes {{ node }} --file /dev/stdin --mode reboot

apply-all:
  #!/usr/bin/env bash
  set -euxo pipefail
  for node in {{ nodes }}; do
    just apply $node
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

upgrade node:
  #!/usr/bin/env bash
  TALOS_IMAGE=$(just get-talos-image)
  talosctl upgrade --image $TALOS_IMAGE --nodes {{ node }} --endpoints {{ node }} --debug
  just health {{ node }}

upgrade-all:
  #!/usr/bin/env bash
  set -euxo pipefail
  for node in {{ nodes }}; do
    just upgrade $node
  done

upgrade-k8s:
  # all nodes will be upgraded sequentially, just pick one node for the command
  talosctl upgrade-k8s --to $KUBERNETES_VERSION -n 192.168.178.100 -e 192.168.178.100

health node:
  talosctl health --nodes {{ node }} --server=false

kubeconfig node:
  talosctl kubeconfig --nodes {{ node }} --force --force-context-name talos {{ talosDir }}

services node:
  talosctl services --nodes {{ node }}

logs node service:
  talosctl logs --nodes {{ node }} {{ service }}

etcd-defrag:
  #!/usr/bin/env bash
  set -euxo pipefail
  for node in {{ nodes }}; do
    talosctl etcd defrag --nodes $node
    sleep 2
    just health $node
  done

tail-dmesg node:
  talosctl dmesg --tail --follow --nodes {{ node }}

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

#########
# Misc
#######
@dump-adguard-conf:
  kubectl exec -it -n dns deploy/adguard -c adguard -- cat /opt/adguardhome/conf/AdGuardHome.yaml | yq 'del(.users)'

get-failed-pods:
  kubectl get pods -A -o wide | grep -v Running

clean-pods:
  kubectl delete pods --field-selector=status.phase==Succeeded -A
  kubectl delete pods --field-selector=status.phase==Failed -A
