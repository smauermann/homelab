# OpenClaw homelab install — design

Date: 2026-04-17
Status: Proposed

## Goal

Run OpenClaw as a first-class app in the homelab cluster, reachable over
Tailscale at `openclaw.costanza.cloud`, managed the same way every other app
is (kustomize → Helm → ArgoCD, ExternalSecret from 1Password, backed-up PVC).

## Scope

- A new ArgoCD application `openclaw` under `kubernetes/applications/openclaw/`.
- Private HTTPRoute on the `private` Envoy Gateway.
- Single provider: OpenRouter.
- Agent workspace files (AGENTS.md etc.) managed **in-cluster** on the PVC, not
  declaratively in git.

Out of scope: public exposure, multi-provider setup, OIDC in front of OpenClaw
(OpenClaw auths via its own gateway bearer token).

## Constraints

- Upstream ships a Kustomize base + `deploy.sh`; the repo's convention is
  kustomize-wrapping-helm with `bjw-s/app-template`. We follow the repo
  convention — manifests are small (~60 lines of values) and re-owning them
  keeps OpenClaw homogeneous with mealie/paperless/etc.
- Upstream's default gateway bind is `127.0.0.1`; a ClusterIP Service cannot
  reach that. We override `openclaw.json` to bind `0.0.0.0:18789`.
- Branch discipline: work lands on `feat/openclaw`, never on `main`.

## Architecture

```
kubernetes/applications/openclaw/
├── kustomization.yaml    # app-template + pvc-backup helm charts
├── namespace.yaml        # openclaw namespace
├── secrets.yaml          # ExternalSecret → 1Password item "openclaw-secrets"
└── values.yaml           # app-template values (the bulk of the config)
```

Registered with the application ApplicationSet in
`kubernetes/applications/application-set.yaml` (one line — the ApplicationSet
discovers directories).

### Runtime resources (rendered by `app-template`)

| Kind | Name | Purpose |
|---|---|---|
| Deployment | `openclaw` | single replica, single container |
| Service | `openclaw` | ClusterIP :18789 |
| PersistentVolumeClaim | `openclaw-data` | 10Gi, agent state |
| ConfigMap | `openclaw-config` | `openclaw.json` |
| HTTPRoute | `openclaw` | `openclaw.costanza.cloud` → Service :18789 |

Plus from `pvc-backup`:

| Kind | Name | Purpose |
|---|---|---|
| CronJob | `openclaw-backup` | periodic snapshot of `openclaw-data` |

### Container

- Image: `ghcr.io/openclaw/openclaw` pinned to tag + digest (latest stable tag
  picked at implementation; Renovate keeps it fresh).
- Security context (matches mealie):
  - Pod: `runAsNonRoot: true`, `runAsUser/Group/fsGroup: 1000`,
    `fsGroupChangePolicy: OnRootMismatch`.
  - Container: `allowPrivilegeEscalation: false`,
    `readOnlyRootFilesystem: true`, `capabilities.drop: [ALL]`.
- Resources: 100m/400Mi requests, 600Mi memory limit (starting point;
  revisit if metrics show pressure).
- Env:
  - `envFrom` Secret `openclaw-secrets` → `OPENCLAW_GATEWAY_TOKEN`,
    `OPENROUTER_API_KEY`.
- Probes: HTTP on port 18789 (path confirmed at implementation time against
  the running container).

### Filesystem layout

| Mount path | Source | Read/write | Notes |
|---|---|---|---|
| `~/.openclaw/` | PVC `openclaw-data` | rw | Whole dir; holds `workspace/`, `agents/<id>/sessions/`, auto-created files. |
| `~/.openclaw/openclaw.json` | ConfigMap `openclaw-config` (subPath) | ro | Overlays the one file; survives ConfigMap changes (pod restarts on change). |
| `/tmp/openclaw/` | `emptyDir` | rw | Logs; ephemeral. |
| `/tmp` | `emptyDir` | rw | Required because `readOnlyRootFilesystem: true`. |

The home directory expands to whatever the container's default user has;
confirmed at implementation time (if upstream image doesn't use `/root` or
`/home/…`, the mount paths are adjusted).

### `openclaw.json` contents

Start from upstream's default. Only override:

```json
{
  "gateway": {
    "bindAddress": "0.0.0.0",
    "port": 18789
  }
}
```

Everything else (agent defaults, model config) inherits upstream defaults and
can be tuned later.

### AGENTS.md and workspace

OpenClaw auto-creates `~/.openclaw/workspace/{AGENTS,SOUL,TOOLS,IDENTITY,USER,HEARTBEAT,BOOTSTRAP}.md`
on first boot on the PVC. The user edits them via `kubectl exec` or the
OpenClaw UI. Git is not the source of truth for agent behavior — the PVC is
(and the PVC is backed up).

Trade-off accepted: agent instructions aren't versioned in git. The backup
gives us recovery; full versioning can be added later if needed by moving
AGENTS.md into the ConfigMap.

## Secrets

1Password item `openclaw-secrets` (new, created by hand) holds:

| Field | Value |
|---|---|
| `OPENCLAW_GATEWAY_TOKEN` | generated once (`openssl rand -hex 32` or similar) |
| `OPENROUTER_API_KEY` | from openrouter.ai |

`ExternalSecret` syncs it into Kubernetes Secret `openclaw-secrets` in the
`openclaw` namespace via the existing `onepassword-connect` ClusterSecretStore
(same pattern as mealie).

## Access

Tailscale client → `openclaw.costanza.cloud` → Envoy Gateway (private) →
`Service/openclaw:18789` → pod. Client sends bearer token
(`OPENCLAW_GATEWAY_TOKEN`) in the request — retrieved by the user once from
1Password.

## Homepage dashboard

HTTPRoute carries `gethomepage.dev/*` annotations (enabled, group, name,
description, icon) matching existing apps.

## Backup

`pvc-backup` helm chart, `pvcName: openclaw-data`, restore enabled, 10Gi —
same config shape as mealie's. Cadence inherited from chart defaults.

## Testing / verification

1. `kubectl --context talos -n openclaw get pods` → Ready.
2. `kubectl --context talos -n openclaw logs deploy/openclaw` → gateway listening on 0.0.0.0:18789.
3. `kubectl --context talos -n openclaw exec -it deploy/openclaw -- ls ~/.openclaw/workspace` → workspace files present.
4. Over Tailscale: `curl -H "Authorization: Bearer $TOKEN" https://openclaw.costanza.cloud/…` → 200.
5. Homepage dashboard shows the OpenClaw tile under its configured group.
6. Backup CronJob runs once and produces a snapshot.

## Rollout

1. Create 1Password item.
2. Open PR with the four files + ApplicationSet registration.
3. Merge → Argo syncs → pod comes up and auto-creates the workspace.
4. First-use: fetch the token, hit the URL, confirm it works.

## Open questions (resolved at implementation time, not blocking)

- Exact home-dir path inside the container (drives volume mount paths).
- Latest stable OpenClaw image tag.
- Liveness/readiness probe path exposed by the gateway.
