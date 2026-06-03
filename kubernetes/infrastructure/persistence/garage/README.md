# Garage Disaster Recovery Runbook

How to recover the self-hosted S3 (Garage) after partial or total loss. Read the
**Architecture** section once so the recovery steps make sense; jump to the matching
**Scenario** when you actually need it.

## Architecture (what lives where)

Single-node Garage (`replication_factor = 1`), LMDB metadata engine. Deployed by ArgoCD
from `kubernetes/infrastructure/persistence/garage/`.

| Thing | Location | Notes |
|-------|----------|-------|
| Data blocks | `nas.internal:/volume1/homelab/garage/data` → `/data` | The actual object bytes. |
| Metadata (LMDB) | `nas.internal:/volume1/homelab/garage/meta` → `/meta` | Buckets, access keys, **cluster layout**, and **node identity** (`/meta/node_key`). This is the "config" that makes the data usable. |
| RPC secret, admin & metrics tokens | 1Password item `garage` → ExternalSecret `garage` | Needed for the node to start and for admin API. |
| Consumer S3 creds (CNPG/barman) | 1Password item `barman-garage-store` → ExternalSecret `garage-store` | `ACCESS_KEY_ID` / `ACCESS_SECRET_KEY` / `REGION`. Must match a key that exists *inside* Garage's metadata. |
| Off-site backup | Backblaze | Whole `garage/` folder (meta + data) tar'd from the NAS nightly at 01:00. |

Key facts that shape recovery:

- **Both data and metadata are on the NAS.** If the *cluster* dies but the NAS is fine, a
  redeploy remounts the same meta+data and Garage comes back as the **same node, same
  layout, same buckets, same keys** — no bootstrap needed.
- **Garage has no external dependencies.** LMDB is self-contained; Garage does **not** need
  Postgres. So in a full rebuild, bring Garage up *first*, then restore CNPG from its barman
  backups (which live in the `barman-backups` bucket here). No circular dependency.
- **LMDB on NFS is fragile** (mmap + file locking over NFS). Treat silent metadata
  corruption as a real failure mode — see Scenario C. Prefer restoring metadata from the
  Garage auto-snapshot (consistent) over the live LMDB tree (can be torn).

---

## Scenario A — Cluster rebuilt, NAS intact (most common)

E.g. Talos reinstall, accidental namespace deletion, fresh cluster pointed at the same NAS.

1. Bring the cluster + ArgoCD back. Ensure External Secrets Operator and the
   `onepassword-connect` ClusterSecretStore are healthy (the `garage` secret must sync).
2. Let ArgoCD sync the `garage` Application. The pod mounts the existing NFS meta+data.
3. Verify (see **Verification** below). Because `/meta/node_key` and the LMDB layout
   survived on NFS, the node keeps its identity and **no `layout apply` is needed**.
4. Verify consumers: `barman-backups` bucket is listable and the `barman-garage-store` key
   still works. Then restore CNPG clusters from barman if they were lost too.

> If the pod is stuck on a stale NFS lock after an unclean shutdown, scale the deployment to
> 0, confirm no other pod holds `/meta`, then scale back to 1. Garage takes an exclusive
> LMDB lock — only one replica may mount `/meta` at a time.

---

## Scenario B — NAS volume lost, restore from Backblaze

1. Restore the nightly `garage/` tarball from Backblaze onto the NAS at
   `nas.internal:/volume1/homelab/garage/` so that `meta/` and `data/` are back in place
   with original ownership (uid/gid `1000`, matching `runAsUser`/`fsGroup`).
2. Proceed exactly as **Scenario A**. The restored metadata carries node identity, layout,
   buckets and keys, so it comes back self-consistent.

> The nightly tar copies the **live** LMDB. It is almost always fine, but if Garage crashes
> on start with an LMDB error after a Backblaze restore, the backup caught a torn write —
> fall back to the most recent `meta/snapshots/<timestamp>/` directory inside the restored
> tree (those are the consistent 6-hourly auto-snapshots) per Scenario C.

---

## Scenario C — Metadata corrupted (LMDB won't open / inconsistent)

Data blocks in `/data` are intact but `/meta` is broken.

1. Scale the Garage deployment to 0 so nothing holds the LMDB lock.
2. On the NAS, move the bad `meta/` aside (don't delete yet) and restore `meta/` from the
   most recent consistent source, in order of preference:
   - the latest `meta/snapshots/<timestamp>/` from the **same** tree (Garage's 6h auto-snapshot), or
   - last night's Backblaze tarball, or
   - an older Backblaze tarball.
3. Scale back to 1 and run **Verification**.
4. If no usable metadata exists anywhere, the data blocks are effectively orphaned —
   recovering object names from raw blocks is not practical. Go to **Scenario D** to rebuild
   buckets/keys, and treat object contents as lost.

---

## Scenario D — From-scratch bootstrap (no usable metadata at all)

Only when meta is unrecoverable. The aim is to recreate Garage so that **existing consumer
credentials in 1Password keep working** — i.e. recreate the access key with its *exact*
existing ID and secret, not a fresh one (otherwise every consumer secret must change).

All commands run inside the pod:
`kubectl --context talos -n garage exec deploy/garage -c app -- /garage <args>`

1. **Layout** — assign the single node to a zone and capacity, then apply:
   ```
   /garage status                       # note the NODE_ID of the running node
   /garage layout assign -z dc1 -c 1T <NODE_ID>
   /garage layout apply --version 1
   ```
2. **Buckets** — recreate every bucket consumers expect. At minimum:
   ```
   /garage bucket create barman-backups
   ```
   (Add others as they are reintroduced — e.g. langfuse, volsync targets. Keep this list in
   sync as you add S3 consumers.)
3. **Access key with its original ID + secret** — pull `ACCESS_KEY_ID` and
   `ACCESS_SECRET_KEY` from the 1Password `barman-garage-store` item and re-import them so
   the existing `garage-store` ExternalSecret stays valid:
   ```
   /garage key import --help            # confirm exact flags for v2.2.0
   /garage key import <ACCESS_KEY_ID> <ACCESS_SECRET_KEY> -n barman-garage-store
   ```
4. **Grant the key access to its bucket(s):**
   ```
   /garage bucket allow --read --write --owner barman-backups --key <ACCESS_KEY_ID>
   ```
5. Repeat 2–4 for any other consumer/key pairs stored in 1Password.
6. Run **Verification**.

---

## Verification

```bash
POD=$(kubectl --context talos -n garage get pod -l app.kubernetes.io/name=garage -o jsonpath='{.items[0].metadata.name}')
kubectl --context talos -n garage exec "$POD" -c app -- /garage status        # node healthy, layout present
kubectl --context talos -n garage exec "$POD" -c app -- /garage bucket list    # expected buckets present
kubectl --context talos -n garage exec "$POD" -c app -- /garage key list       # expected keys present
```

End-to-end S3 check (from any machine with the barman creds and `aws` CLI configured for
`https://s3.costanza.cloud`, region `eu-west-1`):

```bash
aws --endpoint-url https://s3.costanza.cloud s3 ls s3://barman-backups/
```

Then confirm CNPG can read its backups before relying on them for a Postgres restore.

---

## Recovery order in a full rebuild

1. Cluster + ArgoCD + External Secrets Operator (so 1Password-backed secrets sync).
2. **Garage** (Scenario A or B). Verify S3 is serving.
3. CNPG clusters — restore from barman backups in `barman-backups`.
4. Everything else that depends on Postgres or S3.

## Notes / known weaknesses

- The nightly Backblaze tar is the durability backstop for both data and metadata. It is
  *application-inconsistent* for the live LMDB; the 6h auto-snapshots inside `meta/snapshots/`
  are the consistent fallback.
- `replication_factor = 1` + single node means there is no in-cluster redundancy — durability
  rests entirely on the NAS and its Backblaze backup. That is an accepted homelab trade-off,
  not a bug.
