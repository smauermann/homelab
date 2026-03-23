# Homelab Rules

## Git

- Before starting any work, check the current branch. If not on main, create a new branch from a fresh copy of main (`git fetch && git checkout -b <branch> origin/main`)
- Never commit work made on an unrelated branch

## Kubernetes

- Always use `kubectl --context talos` when working with my homelab
