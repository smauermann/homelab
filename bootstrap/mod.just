set positional-arguments := true
set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

bootstrap_dir := justfile_dir() + '/bootstrap'
kubernetes_dir := justfile_dir() + '/kubernetes'
talosDir := justfile_dir() + '/talos'
controller := `talosctl config info -o yaml | yq -e '.endpoints[0]'`
nodes := `talosctl config info -o yaml | yq -e '.nodes | join (" ")'`

[private]
default: talos k8s wait kubeconfig namespaces secrets cert-manager external-secrets argocd apps

[private]
apply file:
  kubectl apply --server-side --force-conflicts --field-manager bootstrap -f {{ file }}

[private]
wait-app ns:
  just log info "Waiting for applications in namespace {{ ns }} to be ready..."
  if kubectl get deployment -n {{ ns }} -o name | grep -q .; then \
    kubectl wait --for=condition=available --timeout=300s deployment --all -n {{ ns }}; \
  fi
  if kubectl get statefulset -n {{ ns }} -o name | grep -q .; then \
    kubectl rollout status statefulset -n {{ ns }} --timeout=300s; \
  fi

[doc('Install Talos')]
talos:
  just log info "Installing Talos..."
  for n in {{ nodes }}; do \
    just talos apply "$n" --insecure
  done

[doc('Install Kubernetes')]
k8s:
  just log info "Bootstrapping Kubernetes..." "stage" foo
  until op=$(talosctl -n "{{ controller }}" bootstrap 2>&1 || true) && [[ "$op" == *"AlreadyExists"* ]]; do \
    just log info "Kubernetes bootstrap in progress. Retrying in 5 seconds..."; \
    sleep 5; \
  done

[doc('Fetch kubeconfig')]
kubeconfig:
  just log info "Fetching Kubeconfig..."
  if ! talosctl kubeconfig -n "{{ controller }}" -f --force-context-name talos {{ talosDir }}; then \
    just log fatal "Failed to fetch kubeconfig"; \
  fi

[doc('Wait for nodes to be not-ready')]
wait:
  just log info "Waiting for nodes to be up..."
  if ! kubectl wait nodes --for=condition=Ready=True --all --timeout=10s &>/dev/null; then \
    until kubectl wait nodes --for=condition=Ready=False --all --timeout=10s &>/dev/null; do \
      just log info "Nodes not available, waiting for nodes to be available. Retrying in 5 seconds..."; \
        sleep 5; \
    done \
  fi

[doc('Apply Kubernetes namespaces')]
namespaces:
  just log info "Applying Namespaces..." && pwd
  rg -l "kind: Namespace" -g "*.yaml" {{ kubernetes_dir }} | while IFS= read -r namespace; do \
    just bootstrap apply "$namespace"; \
  done

[doc('Apply Kubernetes Secrets')]
secrets:
  just log info "Applying Secrets..."
  for secret in {{ bootstrap_dir }}/secrets/*.yaml; do \
    just template "$secret"| just bootstrap apply /dev/stdin; \
  done

[doc('Deploy cert-manager')]
cert-manager:
  just log info "Deploying cert-manager..."
  just kube kustomize-helm {{ kubernetes_dir }}/infrastructure/network/cert-manager | just bootstrap apply /dev/stdin
  just bootstrap wait-app cert-manager

[doc('Deploy External Secrets Operator')]
external-secrets:
  just log info "Deploying External Secrets Operator..."
  just kube kustomize-helm {{ kubernetes_dir }}/infrastructure/workloads/external-secrets | just bootstrap apply /dev/stdin
  just bootstrap wait-app external-secrets

[doc('Deploy ArgoCD')]
argocd:
  just log info "Deploying ArgoCD..."
  just kube kustomize-helm {{ kubernetes_dir }}/infrastructure/workloads/argocd | just bootstrap apply /dev/stdin
  just bootstrap wait-app argocd

[doc('Apply ArgoCD Applications')]
apps:
  just log info "Applying ArgoCD Applications..."
  kubectl kustomize ./argo-apps | just bootstrap apply /dev/stdin

