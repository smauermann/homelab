# Homelab Infrastructure

A modern, Kubernetes-based homelab infrastructure built with Talos Linux, ArgoCD, and other cloud-native tools.

## 🏗️ Architecture

This homelab is built on a foundation of modern infrastructure tools:

- **Talos Linux**: A secure, immutable, and minimal Linux distribution designed for running Kubernetes
- **Kubernetes**: The container orchestration platform
- **ArgoCD**: GitOps continuous delivery tool
- **Cilium**: Container networking and security
- **1Password**: Secrets management
- **SOPS**: Secrets encryption

## 🚀 Getting Started

### Prerequisites

- [Talos Linux](https://www.talos.dev/latest/introduction/getting-started/)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [sops](https://github.com/mozilla/sops)
- [just](https://github.com/casey/just) command runner
- [direnv](https://direnv.net/) (optional, but recommended)

### Initial Setup

1. Clone this repository:
   ```bash
   git clone https://github.com/smauermann/homelab.git
   cd homelab
   ```

2. Copy the example environment file and configure it:
   ```bash
   cp example.envrc .envrc
   # Edit .envrc with your configuration
   ```

3. Generate Talos secrets:
   ```bash
   just gen-secrets
   ```

4. Generate Talos configuration:
   ```bash
   just gen-config
   ```

5. Apply the configuration to your nodes:
   ```bash
   just apply-all
   ```

6. Bootstrap the cluster:
   ```bash
   just bootstrap $FIRST_NODE
   ```

7. Deploy the base applications (Cilium, 1Password, ArgoCD):
   ```bash
   just bootstrap-apps
   ```

## 📁 Project Structure

```
.
├── bootstrap/           # Initial setup before ArgoCD takes over
├── infra/               # Adjacent infrastructure like S3 buckets
├── kubernetes/          # Kubernetes manifests
│   ├── applications/    # Application workloads
│   └── infrastructure/  # Core infrastructure components
├── talos/               # Talos Linux configurations
└── hack/                # Utility scripts
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
