# Repository Guidelines

## Project Structure & Module Organization
The repository is organized around Talos-managed Kubernetes infrastructure. `kubernetes/` holds GitOps manifests split into `applications/` (workloads) and `infrastructure/` (cluster services). Talos machine definitions live under `talos/`, including rendered configs and secrets. `bootstrap/` contains pre-ArgoCD assets such as namespaces and sealed secrets, while `infra/` tracks auxiliary cloud resources. Utility scripts and ad-hoc helpers reside in `hack/`. Consult `justfile` for task automation entry points.

## Coding Style & Naming Conventions
YAML manifests use two-space indentation, lowercase directory names, and hyphenated resource filenames (for example, `kubernetes/applications/media/radarr/helm-release.yaml`). Favor descriptive resource labels and keep Kustomize overlays co-located with their base service. Shell scripts in `hack/` should be `bash` with `set -euo pipefail` and executable bit set. Keep Talos node files matched to their IP address (`talos/192.168.178.100.sops.yaml`) to simplify automation.

## Commit & Pull Request Guidelines
Commit messages follow the conventional `type(scope): summary` format seen in history (for example, `fix(container): update image node-feature-discovery`). Keep subjects imperative and note version bumps in parentheses when applicable. Pull requests should describe the intent, list affected clusters or apps, and reference tracking issues. Attach command output or screenshots for disruptive upgrades, and confirm that secrets or kubeconfigs are redacted before sharing logs.

## Security & Secrets Handling
Secrets are encrypted with SOPS; never commit decrypted files.
