# OpenClaw Homelab Install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add OpenClaw as a new ArgoCD-managed app under `kubernetes/applications/openclaw/`, reachable over Tailscale at `openclaw.costanza.cloud`, with its config and workspace living on a backed-up PVC (nothing OpenClaw-owned in git).

**Architecture:** kustomize → Helm (`bjw-s/app-template` + `smauermann/pvc-backup`) → ArgoCD. One namespace, one Deployment, one Service, one PVC, one HTTPRoute, one ExternalSecret. A separate `pvc-backup` release snapshots the PVC via VolSync. Secrets come from 1Password via the existing `onepassword-connect` ClusterSecretStore.

**Tech Stack:** Kubernetes, Talos, ArgoCD, Envoy Gateway (HTTPRoute), bjw-s `app-template` v4.6.2, `smauermann/pvc-backup` v2.2.1, External Secrets Operator, 1Password Connect, `just` command runner.

**Design spec:** `docs/superpowers/specs/2026-04-17-openclaw-homelab-install-design.md`

**Prerequisites on branch:** Work continues on `feat/openclaw` (already branched from `origin/main`; spec commits already present). All commits land there; a PR opens in Task 9.

---

## File plan

| File | Action | Purpose |
|---|---|---|
| `kubernetes/applications/openclaw/namespace.yaml` | Create | Namespace `openclaw`. |
| `kubernetes/applications/openclaw/secrets.yaml` | Create | `ExternalSecret` pulling `OPENCLAW_GATEWAY_TOKEN` + `OPENROUTER_API_KEY` from 1Password into a K8s Secret. |
| `kubernetes/applications/openclaw/values.yaml` | Create | `app-template` values: Deployment (single container, no init), Service, PVC, HTTPRoute, homepage annotations. |
| `kubernetes/applications/openclaw/kustomization.yaml` | Create | Stitches `app-template` + `pvc-backup` helm charts. |

The `ApplicationSet` at `kubernetes/applications/application-set.yaml` auto-discovers directories under `kubernetes/applications/*` — **no edit needed**.

---

## Task 1: Discover and pin the OpenClaw image digest

**Files:** none (research only; digest captured for Task 4)

Why first: pinning images by digest is a repo invariant (see mealie, paperless). The digest feeds Task 4's `values.yaml`.

- [ ] **Step 1: List available OpenClaw image tags**

Run:
```bash
gh api -H "Accept: application/vnd.github+json" \
  '/users/openclaw/packages/container/openclaw/versions?per_page=20' \
  --jq '.[] | {tags: .metadata.container.tags, updated: .updated_at}' | head -60
```

Pick the most recent **non-floating** tag that corresponds to `:slim` variant (typically named `<version>-slim`, e.g. `v0.4.2-slim`). If no `-slim`-suffixed versioned tag exists, fall back to `slim` and accept the tag is floating (note this in the PR description).

- [ ] **Step 2: Resolve the digest**

Run:
```bash
docker buildx imagetools inspect ghcr.io/openclaw/openclaw:<TAG> --format '{{json .Manifest.Digest}}'
```

Record the output (format: `sha256:…`). Also record the chosen `<TAG>`. Example result to carry forward:
```
TAG=v0.4.2-slim
DIGEST=sha256:abc123...
```

- [ ] **Step 3: Sanity-check the image's entrypoint and user**

Run:
```bash
docker buildx imagetools inspect ghcr.io/openclaw/openclaw:<TAG> --format '{{json .Image}}' \
  | jq '{User: .config.User, Cmd: .config.Cmd, Entrypoint: .config.Entrypoint, Env: .config.Env}'
```

Expected: `User: "1000"` (or empty — UID enforced by pod `securityContext`), and an entrypoint/cmd that runs `node /app/dist/index.js gateway run` (matches upstream deployment). If either diverges, stop and reconcile before continuing — the spec assumes upstream's shape.

No commit in this task — values captured for Task 4.

---

## Task 2: Create namespace

**Files:**
- Create: `kubernetes/applications/openclaw/namespace.yaml`

- [ ] **Step 1: Make the directory**

Run:
```bash
mkdir -p kubernetes/applications/openclaw
```

- [ ] **Step 2: Write namespace.yaml**

File: `kubernetes/applications/openclaw/namespace.yaml`
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: openclaw
```

- [ ] **Step 3: Commit**

```bash
git add kubernetes/applications/openclaw/namespace.yaml
git commit -m "feat(openclaw): add namespace"
```

---

## Task 3: Create the 1Password item and ExternalSecret

**Files:**
- Create: `kubernetes/applications/openclaw/secrets.yaml`

The 1Password item must exist before ArgoCD syncs this manifest — otherwise `ExternalSecret` stays in `SecretSyncError` and the pod crashloops on missing env. Operator action is required, outside of git.

- [ ] **Step 1: Generate the gateway token**

Run (locally):
```bash
openssl rand -hex 32
```

Save the output — this is `OPENCLAW_GATEWAY_TOKEN`. Needed again in Task 10 for `curl` verification.

- [ ] **Step 2: Get the OpenRouter API key**

Log in to https://openrouter.ai, create a key named "homelab-openclaw", save its value.

- [ ] **Step 3: Create the 1Password item**

In 1Password's web UI or via `op`:
- Vault: whichever vault `onepassword-connect` is configured to read (same one mealie uses; confirm with:
  ```bash
  kubectl --context talos -n external-secrets get clustersecretstore onepassword-connect \
    -o jsonpath='{.spec.provider.onepassword.vaults}'
  ```
  )
- Item name: `openclaw-secrets`
- Fields (concealed type for both):
  - `OPENCLAW_GATEWAY_TOKEN` = output of Step 1
  - `OPENROUTER_API_KEY` = output of Step 2

- [ ] **Step 4: Write secrets.yaml**

File: `kubernetes/applications/openclaw/secrets.yaml`
```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1.json
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: openclaw-secrets
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: onepassword-connect
  target:
    name: openclaw-secrets
    template:
      engineVersion: v2
      data:
        OPENCLAW_GATEWAY_TOKEN: "{{ .OPENCLAW_GATEWAY_TOKEN }}"
        OPENROUTER_API_KEY: "{{ .OPENROUTER_API_KEY }}"
  dataFrom:
    - extract:
        key: openclaw-secrets
```

- [ ] **Step 5: Commit**

```bash
git add kubernetes/applications/openclaw/secrets.yaml
git commit -m "feat(openclaw): add external secret for gateway token + openrouter key"
```

---

## Task 4: Write the app-template values

**Files:**
- Create: `kubernetes/applications/openclaw/values.yaml`

Substitute `<TAG>` and `<DIGEST>` from Task 1 into the image line before committing.

- [ ] **Step 1: Write values.yaml**

File: `kubernetes/applications/openclaw/values.yaml`
```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/library/common/values.schema.json
---
controllers:
  openclaw:
    strategy: Recreate
    pod:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile:
          type: RuntimeDefault
    containers:
      app:
        image:
          repository: ghcr.io/openclaw/openclaw
          tag: <TAG>@<DIGEST>
        command:
          - node
          - /app/dist/index.js
          - gateway
          - run
        env:
          HOME: /home/node
          OPENCLAW_CONFIG_DIR: /home/node/.openclaw
          NODE_ENV: production
        envFrom:
          - secretRef:
              name: openclaw-secrets
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              exec:
                command:
                  - node
                  - -e
                  - "require('http').get('http://127.0.0.1:18789/healthz', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))"
              initialDelaySeconds: 60
              periodSeconds: 30
              timeoutSeconds: 10
          readiness:
            enabled: true
            custom: true
            spec:
              exec:
                command:
                  - node
                  - -e
                  - "require('http').get('http://127.0.0.1:18789/readyz', r => process.exit(r.statusCode < 400 ? 0 : 1)).on('error', () => process.exit(1))"
              initialDelaySeconds: 15
              periodSeconds: 10
              timeoutSeconds: 5
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop: ["ALL"]
        resources:
          requests:
            cpu: 250m
            memory: 512Mi
          limits:
            memory: 2Gi

service:
  app:
    controller: openclaw
    ports:
      http:
        port: 18789

route:
  app:
    kind: HTTPRoute
    annotations:
      gethomepage.dev/description: Personal AI assistant
      gethomepage.dev/enabled: "true"
      gethomepage.dev/group: Personal
      gethomepage.dev/icon: mdi-robot
      gethomepage.dev/name: OpenClaw
    parentRefs:
      - name: private
        kind: Gateway
        namespace: envoy-gateway-system
    hostnames:
      - openclaw.costanza.cloud

persistence:
  home:
    existingClaim: openclaw-data
    globalMounts:
      - path: /home/node/.openclaw
  tmp:
    type: emptyDir
    globalMounts:
      - path: /tmp
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/applications/openclaw/values.yaml
git commit -m "feat(openclaw): add app-template values"
```

Note: This references `existingClaim: openclaw-data` — the PVC itself is created by the `pvc-backup` chart in Task 5 (same pattern mealie uses).

---

## Task 5: Write the kustomization (app-template + pvc-backup)

**Files:**
- Create: `kubernetes/applications/openclaw/kustomization.yaml`

- [ ] **Step 1: Write kustomization.yaml**

File: `kubernetes/applications/openclaw/kustomization.yaml`
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: &app openclaw

resources:
  - namespace.yaml
  - secrets.yaml

helmCharts:
  - name: app-template
    repo: https://bjw-s-labs.github.io/helm-charts
    version: 4.6.2
    namespace: *app
    releaseName: *app
    valuesFile: values.yaml
  - name: pvc-backup
    repo: https://smauermann.github.io/helm-charts
    version: 2.2.1
    releaseName: openclaw-backup
    valuesInline:
      appName: *app
      backup:
        pvcName: openclaw-data
      restore:
        enabled: true
        pvcSize: 10Gi
```

- [ ] **Step 2: Commit**

```bash
git add kubernetes/applications/openclaw/kustomization.yaml
git commit -m "feat(openclaw): wire app-template and pvc-backup charts"
```

---

## Task 6: Render locally and fix any errors

**Files:** none (validation only)

- [ ] **Step 1: Render the kustomization**

Run:
```bash
just kube kustomize-helm kubernetes/applications/openclaw
```

Expected: a multi-document YAML stream containing (at minimum):
- `Namespace/openclaw`
- `ExternalSecret/openclaw-secrets`
- `ServiceAccount/openclaw` (from app-template)
- `PersistentVolumeClaim/openclaw-data` (from pvc-backup restore)
- `Deployment/openclaw`
- `Service/openclaw`
- `HTTPRoute/openclaw`
- `ReplicationSource/openclaw` (VolSync, from pvc-backup)

If rendering fails (helm error, schema error): read the error, fix the offending file, re-run. Common causes:
- Missing `---` separator
- Wrong `repo:` URL typo
- `app-template` schema mismatch — re-check against the schema URL in the yaml-language-server hint

- [ ] **Step 2: Quick eyeball of the Deployment**

Run:
```bash
just kube kustomize-helm kubernetes/applications/openclaw | yq 'select(.kind == "Deployment")'
```

Confirm:
- `.spec.template.spec.securityContext.fsGroup == 1000`
- `.spec.template.spec.containers[0].image` has the digest from Task 1
- `.spec.template.spec.containers[0].envFrom[0].secretRef.name == "openclaw-secrets"`
- `.spec.template.spec.volumes` includes a PVC volume pointing to `openclaw-data` and an `emptyDir` for `/tmp`

- [ ] **Step 3: Confirm HTTPRoute hostname and gateway ref**

Run:
```bash
just kube kustomize-helm kubernetes/applications/openclaw | yq 'select(.kind == "HTTPRoute")'
```

Confirm `.spec.hostnames == ["openclaw.costanza.cloud"]` and `.spec.parentRefs[0].name == "private"` in namespace `envoy-gateway-system`.

No commit in this task (validation only). If Steps 1–3 required edits, those edits should have been committed as fixups to Tasks 4/5.

---

## Task 7: Render the ExternalSecret dry-run against the live cluster

**Files:** none (cluster sanity check)

Purpose: catch 1Password-side misconfiguration before the PR merges, so the pod doesn't crashloop on first sync.

- [ ] **Step 1: Server-side dry-run of just the ExternalSecret**

Run:
```bash
kubectl --context talos apply --server-side --dry-run=server \
  -n openclaw \
  -f kubernetes/applications/openclaw/secrets.yaml
```

This will fail with "namespace not found" if the namespace isn't yet applied. That's fine — just confirms the manifest is well-formed.

- [ ] **Step 2: Verify the 1Password item is readable**

Run:
```bash
kubectl --context talos -n external-secrets get pods \
  -l app.kubernetes.io/name=onepassword-connect -o name
```

Expect one or more running Connect pods. Then create a one-off test ExternalSecret in a scratch namespace to verify the key resolves (optional but cheap):

```bash
kubectl --context talos create namespace openclaw-check --dry-run=client -o yaml | kubectl --context talos apply -f -
cat <<'EOF' | kubectl --context talos apply -f -
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: openclaw-check
  namespace: openclaw-check
spec:
  secretStoreRef: { kind: ClusterSecretStore, name: onepassword-connect }
  target: { name: openclaw-check }
  dataFrom:
    - extract: { key: openclaw-secrets }
EOF

kubectl --context talos -n openclaw-check wait --for=jsonpath='{.status.conditions[?(@.type=="Ready")].status}'=True externalsecret/openclaw-check --timeout=30s
kubectl --context talos -n openclaw-check get secret openclaw-check -o jsonpath='{.data}' | jq 'keys'
```

Expected: `["OPENCLAW_GATEWAY_TOKEN", "OPENROUTER_API_KEY"]`.

- [ ] **Step 3: Clean up the scratch namespace**

```bash
kubectl --context talos delete namespace openclaw-check
```

No commit.

---

## Task 8: Push branch and open the PR

**Files:** none (git operations)

- [ ] **Step 1: Review all commits on the branch**

Run:
```bash
git log --oneline origin/main..HEAD
```

Expected (in order):
1. `docs(openclaw): add install design spec`
2. `docs(openclaw): drop openclaw.json from git, use first-boot edit`
3. `feat(openclaw): add namespace`
4. `feat(openclaw): add external secret for gateway token + openrouter key`
5. `feat(openclaw): add app-template values`
6. `feat(openclaw): wire app-template and pvc-backup charts`

- [ ] **Step 2: Push the branch**

```bash
git push -u origin feat/openclaw
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "feat(openclaw): install OpenClaw" --body "$(cat <<'EOF'
## Summary
- Installs OpenClaw (https://docs.openclaw.ai) as a new ArgoCD-managed app under `kubernetes/applications/openclaw/`
- Private HTTPRoute at `openclaw.costanza.cloud`, Tailscale-reachable
- Single provider: OpenRouter. Gateway token and API key from 1Password via ExternalSecret
- 10Gi PVC backed up via `pvc-backup` (same pattern as mealie)
- Config (`openclaw.json`) and workspace live on the PVC; git ships only the k8s scaffolding. See `docs/superpowers/specs/2026-04-17-openclaw-homelab-install-design.md`

## Post-merge manual step
The upstream default gateway bind is `loopback`. After Argo syncs the pod, run:
```bash
kubectl --context talos -n openclaw exec -it deploy/openclaw -- \
  sh -c 'jq ".gateway.bind = \"all\"" ~/.openclaw/openclaw.json > ~/.openclaw/openclaw.json.new && mv ~/.openclaw/openclaw.json.new ~/.openclaw/openclaw.json'
kubectl --context talos -n openclaw rollout restart deploy/openclaw
```

## Test plan
- [ ] Argo syncs the application cleanly
- [ ] `ExternalSecret/openclaw-secrets` becomes `Ready`
- [ ] Pod reaches Ready after the bind-address edit
- [ ] `curl -H "Authorization: Bearer $TOKEN" https://openclaw.costanza.cloud/healthz` returns 200 over Tailscale
- [ ] Homepage dashboard shows the OpenClaw tile
- [ ] First scheduled backup produces a `ReplicationSource` with a successful sync
EOF
)"
```

Record the PR URL.

- [ ] **Step 4: Review the rendered diff in GitHub**

Open the PR URL and confirm the file tree + contents match expectations. Merge when happy.

No commit (PR itself is the artifact).

---

## Task 9: Post-merge — verify the initial sync

**Files:** none (cluster verification)

Wait for Argo to sync after merge (usually <1 min).

- [ ] **Step 1: Confirm Argo sees and syncs the app**

Run:
```bash
kubectl --context talos -n argocd get application openclaw \
  -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'
```

Expected: `Synced Healthy` OR `Synced Progressing` (the pod will be crashlooping or not-ready because of loopback bind — that's expected at this stage).

- [ ] **Step 2: Confirm ExternalSecret resolved**

Run:
```bash
kubectl --context talos -n openclaw get externalsecret openclaw-secrets
kubectl --context talos -n openclaw get secret openclaw-secrets -o jsonpath='{.data}' | jq 'keys'
```

Expected: `SYNCED True`, and the secret has both keys.

- [ ] **Step 3: Confirm PVC bound**

Run:
```bash
kubectl --context talos -n openclaw get pvc openclaw-data
```

Expected: `STATUS=Bound`, `CAPACITY=10Gi`.

- [ ] **Step 4: Confirm pod came up and self-seeded**

Run:
```bash
kubectl --context talos -n openclaw get pods
kubectl --context talos -n openclaw exec deploy/openclaw -- ls /home/node/.openclaw /home/node/.openclaw/workspace
```

Expected: pod `Running` (readiness may be failing — that's fine), and the workspace dir contains at minimum `AGENTS.md`, `SOUL.md`, `TOOLS.md`, `IDENTITY.md`, `USER.md`, `HEARTBEAT.md`, `BOOTSTRAP.md`, plus `openclaw.json` at the parent level.

If `ls` fails because pod is CrashLoopBackOff: check logs (`kubectl --context talos -n openclaw logs deploy/openclaw --previous`) for the real reason. Common causes: missing envvar the app requires, wrong command args, image pull error.

No commit.

---

## Task 10: Post-merge — flip the gateway bind and verify end-to-end reachability

**Files:** none (one-time cluster mutation on the PVC)

- [ ] **Step 1: Inspect the current config**

Run:
```bash
kubectl --context talos -n openclaw exec deploy/openclaw -- cat /home/node/.openclaw/openclaw.json
```

Record the current value of `.gateway.bind`. Expected: `"loopback"`. If it's already `"all"`, the flip isn't needed — skip to Step 3.

- [ ] **Step 2: Flip the bind**

Run:
```bash
kubectl --context talos -n openclaw exec deploy/openclaw -- \
  sh -c 'jq ".gateway.bind = \"all\"" ~/.openclaw/openclaw.json > ~/.openclaw/openclaw.json.new && mv ~/.openclaw/openclaw.json.new ~/.openclaw/openclaw.json'
```

If the container image lacks `jq`, fall back to `sed`:
```bash
kubectl --context talos -n openclaw exec deploy/openclaw -- \
  sh -c 'sed -i "s/\"bind\": \"loopback\"/\"bind\": \"all\"/" ~/.openclaw/openclaw.json'
```

Confirm:
```bash
kubectl --context talos -n openclaw exec deploy/openclaw -- cat /home/node/.openclaw/openclaw.json | grep bind
```

Expected: `"bind": "all"`.

- [ ] **Step 3: Restart the deployment**

```bash
kubectl --context talos -n openclaw rollout restart deploy/openclaw
kubectl --context talos -n openclaw rollout status deploy/openclaw --timeout=2m
```

Expected: rollout completes; new pod is `1/1 Ready`.

- [ ] **Step 4: In-cluster HTTP check**

Run:
```bash
kubectl --context talos -n openclaw run curl-check --rm -it --image=curlimages/curl:8.10.1 --restart=Never -- \
  curl -sS -o /dev/null -w '%{http_code}\n' http://openclaw.openclaw.svc.cluster.local:18789/healthz
```

Expected: `200`.

- [ ] **Step 5: Over-Tailscale HTTP check**

On your laptop (Tailscale active):
```bash
TOKEN=$(op read 'op://<vault>/openclaw-secrets/OPENCLAW_GATEWAY_TOKEN')
curl -sS -H "Authorization: Bearer $TOKEN" \
  -o /dev/null -w '%{http_code}\n' \
  https://openclaw.costanza.cloud/healthz
```

Expected: `200`. If `401`: token mismatch — re-check 1Password item and ensure the secret in-cluster has the same value. If `404`: healthz path differs — try `/` or the path reported in `kubectl logs`. If `502`/`503`: Envoy can't reach the backend — verify the Service selector matches the pod labels.

No commit.

---

## Task 11: Verify homepage tile and first backup run

**Files:** none (end-to-end smoke)

- [ ] **Step 1: Homepage dashboard tile**

Open the homepage dashboard (same URL you use today for the other apps). Confirm:
- OpenClaw tile appears under group `Personal`
- Tile URL resolves (click-through reaches the gateway)

If the tile doesn't appear: check `kubectl --context talos -n homepage-dashboard logs deploy/homepage` for annotation discovery errors; verify the `gethomepage.dev/*` annotations survived rendering with `kubectl --context talos -n openclaw get httproute openclaw -o jsonpath='{.metadata.annotations}'`.

- [ ] **Step 2: Trigger a backup manually to confirm the ReplicationSource works**

Run:
```bash
just kube backup-volumes
```

This patches every `ReplicationSource` with a manual trigger and waits. Watch the openclaw one specifically:
```bash
kubectl --context talos -n openclaw get replicationsource openclaw -o yaml | yq '.status'
```

Expected: `conditions` contains a successful synchronization; `lastManualSync` populated.

- [ ] **Step 3: Mark the plan complete**

Close out any remaining operational follow-ups (e.g., record the tag in the PR description for future Renovate bumps, add an entry to any personal runbook).

No commit.

---

## Rollback

If any step from Task 9 onward reveals a broken state that can't be fixed forward quickly:

1. Revert the merged PR: `gh pr revert <number>` or `git revert <merge-sha> && git push`.
2. Argo will prune the `openclaw` application on next sync (ApplicationSet `prune: true`).
3. The 1Password item can stay — unused and harmless.
4. The PVC may linger depending on reclaim policy; if so: `kubectl --context talos delete pvc -n openclaw openclaw-data` after confirming no backup restore is needed.

---

## Self-review checklist (done at plan authoring)

- Every spec section maps to a task: namespace (T2), ExternalSecret (T3), Deployment/Service/PVC/HTTPRoute (T4-T5), backup (T5), bootstrap edit (T10), testing (T9-T11). ✓
- No "TBD" / "add appropriate X" placeholders. ✓
- Image digest deferred to runtime discovery (T1) — that's an explicit step, not a placeholder. ✓
- Exact commands with expected outputs throughout. ✓
- Types/names consistent: `openclaw-secrets` (secret), `openclaw-data` (PVC), `openclaw` (deployment/service/httproute) — all match across T3/T4/T5/T9/T10. ✓
