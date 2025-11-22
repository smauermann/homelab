set quiet := true
set shell := ['bash', '-euo', 'pipefail', '-c']

kubernetes_dir := justfile_dir() + '/kubernetes'

[private]
default:
  just -l kube

[doc('Render kustomized Helm app')]
kustomize-helm ks:
  # app-template installs pick the wrong gateway api version, set explicitly here
  kubectl kustomize --enable-helm --helm-api-versions=gateway.networking.k8s.io/v1/HTTPRoute "{{ ks }}"

[doc('Apply Kustomization')]
apply ks:
  just kube kustomize-helm "{{ ks }}" | kubectl apply --server-side --force-conflicts --field-manager=kube-kustomize -f /dev/stdin

[doc('Delete Kustomization')]
delete-ks ks:
  just kube kustomize-helm "{{ ks }}" | kubectl delete -f /dev/stdin

[doc('Prune pods in Failed, Pending, or Succeeded state')]
prune-pods:
  for phase in Failed Pending Succeeded; do \
    kubectl delete pods -A --field-selector status.phase="$phase" --ignore-not-found=true; \
  done

[doc('Snapshot VolSync PVCs')]
backup-volumes:
  kubectl get replicationsources --no-headers -A | while read -r ns name _; do \
    kubectl -n "$ns" patch replicationsources "$name" --type merge -p '{"spec":{"trigger":{"manual":"$(date +%s)"}}}'; \
    kubectl -n "$ns" wait  --for=jsonpath='{.status.conditions[*].message}'="Synchronization in-progress" replicationsources "$name"; \
    kubectl -n "$ns" patch replicationsources "$name" --type json -p '[{"op":"remove","path":"/spec/trigger/manual"}]'; \
  done

[doc('Dump AdGuard configuration without user data')]
dump-adguard-conf:
  kubectl exec -it -n dns deploy/adguard -c adguard -- cat /opt/adguardhome/conf/AdGuardHome.yaml | yq 'del(.users)'

