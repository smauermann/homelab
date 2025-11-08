set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

set dotenv-load
set dotenv-path := "talos/cluster.env"

clusterEndpoint := `talosctl config info -o yaml | yq -e '.endpoints[0]'`
talosDir := "talos"

get-hostname node:
  @echo -n {{ replace(replace(node, ".talos.internal", ""), "", "") }}.talos.internal

default:
  @just --list

#########
# SOPS
#######
encrypt:
  #!/usr/bin/env bash
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
gen-secrets:
  talosctl gen secrets --output {{ talosDir }}/secrets.sops.yaml

gen-config:
  talosctl gen config --with-secrets {{ talosDir }}/secrets.sops.yaml homelab {{ clusterEndpoint }} --output {{ talosDir }}

@get-schematic:
  curl -X POST --silent --data-binary @{{ talosDir }}/schematic.yaml https://factory.talos.dev/schematics | yq .id

get-talos-image:
  echo -n factory.talos.dev/installer/$(just get-schematic):${TALOS_VERSION}

[doc('Download Talos machine image')]
download-image:
  curl -sfL --remove-on-error --retry 5 --retry-delay 5 --retry-all-errors \
     -o "{{ talosDir }}/talos-${TALOS_VERSION}-$(just get-schematic).iso" \
    "https://factory.talos.dev/image/$(just get-schematic)/$TALOS_VERSION/metal-amd64.iso"

parse-machine-config node:
  #!/usr/bin/env bash
  SCHEMATIC=$(just get-schematic)
  sops exec-file {{ talosDir }}/base.sops.yaml "talosctl machineconfig patch {} -p @{{ talosDir }}/patches/{{ node }}.yaml" \
    | sed -e "s|\$SCHEMATIC|$SCHEMATIC|g" -e "s|\$TALOS_VERSION|$TALOS_VERSION|g" -e "s|\$KUBERNETES_VERSION|$KUBERNETES_VERSION|g"

apply-insecure node:
  @just parse-machine-config {{ node }} | talosctl apply-config --insecure --nodes $(just get-hostname {{ node }}) --file /dev/stdin

bootstrap-etcd:
  talosctl bootstrap --nodes {{ clusterEndpoint }} --endpoints {{ clusterEndpoint }}

apply node *args:
  @just parse-machine-config {{ node }} | talosctl apply-config --nodes $(just get-hostname {{ node }}) --file /dev/stdin {{ args }}
  @just health {{ node }}

apply-reboot node:
  @just parse-machine-config {{ node }} | talosctl apply-config --nodes $(just get-hostname {{ node }}) --file /dev/stdin --mode reboot

[confirm('Do you really want to reset this node?')]
reset node *args:
  talosctl reset --nodes $(just get-hostname {{ node }}) {{ args }}

[confirm('Do you really want to hard reset this node?')]
reset-hard node *args:
  talosctl reset --graceful=false --nodes $(just get-hostname {{ node }}) {{ args }}

upgrade node:
  talosctl upgrade --nodes $(just get-hostname {{ node }}) --image $(just get-talos-image) --endpoints {{ clusterEndpoint }} --debug
  just health {{ node }}

upgrade-k8s:
  talosctl upgrade-k8s --to "${KUBERNETES_VERSION}" -n {{ clusterEndpoint }} -e {{ clusterEndpoint }}

health node:
  talosctl health --nodes $(just get-hostname {{ node }}) --server=false

kubeconfig node:
  talosctl kubeconfig --nodes $(just get-hostname {{ node }}) --force --force-context-name talos {{ talosDir }}

services node:
  talosctl services --nodes $(just get-hostname {{ node }})

logs node service:
  talosctl logs --nodes $(just get-hostname {{ node }}) "{{ service }}"

tail-dmesg node:
  talosctl dmesg --tail --follow --nodes $(just get-hostname {{ node }})

#########
# Bootstrap Apps
#######
# Helper recipe to bootstrap a Kubernetes app with optional namespace and secrets
_bootstrap-app app_dir secrets="":
  #!/usr/bin/env bash
  set -euxo pipefail
  [[ -f "{{ app_dir }}/namespace.yaml" ]] && kubectl apply -f "{{ app_dir }}/namespace.yaml"
  [[ -n "{{ secrets }}" ]] && sops -d "{{ secrets }}" | kubectl apply -f -
  rm -rf "{{ app_dir }}/charts"
  kubectl kustomize --enable-helm "{{ app_dir }}" | kubectl apply --server-side=true -f - 

bootstrap-apps:
  #!/usr/bin/env bash
  set -uo pipefail
  just bootstrap-cilium || echo "⚠️  cilium bootstrap failed, continuing..."
  just bootstrap-onepassword || echo "⚠️  onepassword bootstrap failed, continuing..."
  just bootstrap-certmanager || echo "⚠️  certmanager bootstrap failed, continuing..."
  just bootstrap-external-secrets || echo "⚠️  external-secrets bootstrap failed, continuing..."
  # just bootstrap-argocd || echo "⚠️  argocd bootstrap failed, continuing..."

bootstrap-cilium:
  just _bootstrap-app kubernetes/infrastructure/network/cilium

bootstrap-onepassword:
  just _bootstrap-app kubernetes/infrastructure/workloads/onepassword bootstrap/onepassword/op-secrets.sops.yaml

bootstrap-certmanager:
  just _bootstrap-app kubernetes/infrastructure/network/cert-manager bootstrap/cert-manager/cloudflare-token.sops.yaml

bootstrap-external-secrets:
  just _bootstrap-app kubernetes/infrastructure/workloads/external-secrets bootstrap/external-secrets/op-secrets.sops.yaml

bootstrap-argocd:
  #!/usr/bin/env bash
  set -euxo pipefail
  just _bootstrap-app kubernetes/infrastructure/workloads/argocd || true
  kubectl apply --server-side=true -k bootstrap/argo-apps

#########
# VolSync
#######
[doc('Snapshot VolSync PVCs')]
backup-volumes:
  kubectl get replicationsources --no-headers -A | while read -r ns name _; do \
    kubectl -n "$ns" patch replicationsources "$name" --type merge -p "{\"spec\":{\"trigger\":{\"manual\":\"$(date +%s)\"}}}"; \
  done

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
