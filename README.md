# Setup Minikube Action

A GitHub Action for installing and configuring [Minikube](https://minikube.sigs.k8s.io/) - a local Kubernetes environment that makes it easy to learn and develop for Kubernetes.

## Features

- ✅ Automatic installation of Minikube
- ✅ Support for multiple drivers (docker, podman, none)
- ✅ Configurable Kubernetes version
- ✅ Waits for cluster readiness
- ✅ Outputs kubeconfig path for easy integration
- ✅ No cleanup required - designed for ephemeral GitHub Actions runners

## Quick Start

```yaml
name: Test with Minikube

on: [push]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup Minikube
        id: minikube
        uses: fenio/setup-minikube@v5
      
      - name: Deploy and test
        run: |
          kubectl apply -f k8s/
          kubectl wait --for=condition=available --timeout=60s deployment/my-app
```

## Inputs

| Input | Description | Default |
|-------|-------------|---------|
| `version` | Minikube version to install (e.g., `v1.32.0`, `latest`, or `stable`) | `stable` |
| `kubernetes-version` | Kubernetes version to use (e.g., `v1.28.0`, `stable`, or `latest`) | `stable` |
| `driver` | VM driver to use (docker, podman, none) | `docker` |
| `container-runtime` | Container runtime to use (docker, containerd, cri-o) | _(driver default)_ |
| `wait-for-ready` | Wait for cluster to be ready before completing | `true` |
| `timeout` | Timeout in seconds to wait for cluster readiness | `120` |
| `dns-readiness` | Wait for CoreDNS to be ready and verify DNS resolution works | `true` |

## Outputs

| Output | Description |
|--------|-------------|
| `kubeconfig` | Path to the kubeconfig file (typically `~/.kube/config`) |

## Usage Examples

### Basic Usage with Latest Version

```yaml
- name: Setup Minikube
  uses: fenio/setup-minikube@v5
```

### Specific Kubernetes Version

```yaml
- name: Setup Minikube
  uses: fenio/setup-minikube@v5
  with:
    kubernetes-version: 'v1.28.0'
```

### Using Podman Driver

```yaml
- name: Setup Minikube
  uses: fenio/setup-minikube@v5
  with:
    driver: 'podman'
```

### Custom Timeout

```yaml
- name: Setup Minikube
  uses: fenio/setup-minikube@v5
  with:
    timeout: '600'  # 10 minutes
```

## How It Works

1. Detects your platform (Linux/macOS) and architecture
2. Downloads the Minikube binary from official sources
3. Installs Minikube to `/usr/local/bin`
4. Starts a Minikube cluster with the specified driver and Kubernetes version
5. Exports the KUBECONFIG environment variable
6. Optionally waits for the cluster to become fully ready

**No cleanup needed** - GitHub Actions runners are ephemeral and destroyed after each workflow run, so there's no need to restore system state.

## Requirements

- Runs on `ubuntu-latest` or `macos-latest`
- Requires Docker (or another driver) to be pre-installed on the runner
- Requires `sudo` access for binary installation

## Troubleshooting

### Cluster Not Ready

If the cluster doesn't become ready in time, increase the timeout:

```yaml
- name: Setup Minikube
  uses: fenio/setup-minikube@v5
  with:
    timeout: '600'  # 10 minutes
```

### Driver Issues

If you encounter issues with the Docker driver, try using a different driver:

```yaml
- name: Setup Minikube
  uses: fenio/setup-minikube@v5
  with:
    driver: 'podman'
```

## Development

This action is written in pure bash and requires no build step. Just edit `setup.sh` and test!

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Related Projects

- [Minikube](https://minikube.sigs.k8s.io/) - Local Kubernetes environment

### Other Kubernetes Setup Actions

- [setup-k0s](https://github.com/fenio/setup-k0s) - Zero friction Kubernetes (k0s)
- [setup-k3s](https://github.com/fenio/setup-k3s) - Lightweight Kubernetes (k3s)
- [setup-kubesolo](https://github.com/fenio/setup-kubesolo) - Ultra-lightweight Kubernetes
- [setup-microk8s](https://github.com/fenio/setup-microk8s) - Lightweight Kubernetes by Canonical
- [setup-talos](https://github.com/fenio/setup-talos) - Secure, immutable Kubernetes OS (Talos)
