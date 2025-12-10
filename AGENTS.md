# AGENTS.md

This file provides comprehensive documentation about the setup-minikube GitHub Action for AI agents and developers working with this codebase.

## Project Overview

**setup-minikube** is a GitHub Action that installs and configures minikube - Local Kubernetes for CI/CD. The action is designed to be simple, with no cleanup required - it just sets up minikube and leaves it running for your workflow to use.

### Key Features
- Automatic installation of minikube with version selection
- Support for multiple drivers (docker, none, podman)
- Kubernetes version selection
- Cluster readiness checks with configurable timeout
- Outputs kubeconfig path for easy integration with kubectl
- **Simple bash-based implementation - no Node.js/TypeScript required**

## Architecture

This is a **composite action** that runs a single bash script. No complex build process, no dependencies to manage.

### Execution Flow

```
setup.sh: Install minikube → Start cluster → Wait for ready (optional)
```

**setup.sh** - Single bash script that:
1. Detects platform (linux/darwin) and architecture (amd64/arm64/arm)
2. Downloads minikube binary from Google Cloud Storage or GitHub releases
3. Installs binary to `/usr/local/bin/minikube`
4. Starts minikube cluster with specified driver and Kubernetes version
5. Exports KUBECONFIG environment variable
6. Optionally waits for cluster to be fully ready with timeout
7. Shows diagnostics if timeout occurs

Location: `setup.sh:1-134`

## File Structure

```
setup-minikube/
├── setup.sh            # Main bash script - does everything
├── action.yml          # GitHub Action metadata and interface
├── AGENTS.md           # This file
├── README.md           # User documentation
└── LICENSE             # MIT license
```

## Key Technical Details

### Action Configuration (action.yml)

**Inputs:**
- `version` (default: 'stable'): minikube version to install (e.g., v1.32.0, latest, or stable)
- `kubernetes-version` (default: 'stable'): Kubernetes version to use (e.g., v1.28.3, stable, latest)
- `driver` (default: 'docker'): Driver to use (docker, none, podman)
- `wait-for-ready` (default: 'true'): Wait for minikube cluster to be ready
- `timeout` (default: '300'): Timeout in seconds for readiness check

**Outputs:**
- `kubeconfig`: Path to kubeconfig file (`~/.kube/config`)

**Runtime:**
- Composite action using bash
- Single step that runs `setup.sh`

### How Inputs Work

The action.yml passes inputs to the bash script via environment variables:
- `INPUT_VERSION` - minikube version
- `INPUT_KUBERNETES_VERSION` - Kubernetes version
- `INPUT_DRIVER` - driver to use
- `INPUT_WAIT_FOR_READY` - whether to wait for cluster ready
- `INPUT_TIMEOUT` - timeout in seconds

The bash script reads these with defaults:
```bash
VERSION="${INPUT_VERSION:-stable}"
KUBERNETES_VERSION="${INPUT_KUBERNETES_VERSION:-stable}"
DRIVER="${INPUT_DRIVER:-docker}"
WAIT_FOR_READY="${INPUT_WAIT_FOR_READY:-true}"
TIMEOUT="${INPUT_TIMEOUT:-300}"
```

## System Requirements

- **OS:** Linux or macOS
- **Permissions:** sudo access (available by default in GitHub Actions)
- **Network:** Internet access to download minikube binaries
- **Driver Dependencies:** Docker must be installed if using docker driver (default on GitHub-hosted runners)

## Common Modification Scenarios

### Adding New Configuration Options

1. Add input to `action.yml`:
```yaml
inputs:
  new-option:
    description: 'Description of the new option'
    required: false
    default: 'default-value'
```

2. Add environment variable to action.yml step:
```yaml
env:
  INPUT_NEW_OPTION: ${{ inputs.new-option }}
```

3. Read input in `setup.sh`:
```bash
NEW_OPTION="${INPUT_NEW_OPTION:-default-value}"
```

4. Update README.md documentation

### Modifying Installation Logic

All installation logic is in `setup.sh`. Key areas:
- Platform/architecture detection: lines 16-33
- Download URL construction: lines 36-42
- Binary download and installation: lines 47-50
- Cluster startup: lines 57-63
- Readiness checking: lines 72-126

### Adding New Diagnostic Information

The diagnostics section (lines 85-95) can be extended to show additional information when cluster readiness times out.

## No Cleanup Required

Unlike the previous Node.js-based version, this simplified action **does not perform any cleanup**. The minikube cluster stays running after your workflow completes. This is simpler and works fine for:

- GitHub-hosted runners (fresh VM each time)
- Self-hosted runners where you want the cluster to persist
- CI/CD pipelines where cleanup isn't necessary

If you need cleanup, you can add it explicitly in your workflow:
```yaml
- name: Cleanup
  if: always()
  run: minikube delete --all --purge
```

## Testing Strategy

### Testing Checklist
**Setup Phase:**
- [ ] minikube installs successfully on Linux
- [ ] minikube installs successfully on macOS
- [ ] Cluster becomes ready within timeout
- [ ] kubectl can connect and list nodes
- [ ] KUBECONFIG environment variable is set correctly
- [ ] Action works with different drivers (docker, none, podman)
- [ ] Action works with specific Kubernetes versions

## Debugging

### Enable Debug Logging
Set repository secret: `ACTIONS_STEP_DEBUG = true`

### Key Log Messages
- "Starting Minikube setup..." - Setup begins
- "Downloading minikube from: ..." - Download URL used
- "Verifying installation..." - Installation complete
- "Starting Minikube cluster..." - Cluster starting
- "Minikube cluster is fully ready!" - Cluster ready
- "Minikube setup completed successfully!" - All done

### Diagnostic Information
When cluster readiness times out, diagnostics display:
- minikube status
- minikube logs (last 100 lines)
- kubectl cluster info
- Nodes status
- Kube-system pods

## Related Resources

- **minikube Project**: https://minikube.sigs.k8s.io/
- **minikube GitHub**: https://github.com/kubernetes/minikube
- **minikube Documentation**: https://minikube.sigs.k8s.io/docs/
- **GitHub Actions Documentation**: https://docs.github.com/actions
- **Composite Actions Guide**: https://docs.github.com/actions/creating-actions/creating-a-composite-action

## Contributing

### Development Workflow
1. Make changes to `setup.sh` or `action.yml`
2. Test in a workflow on GitHub
3. Create pull request

No build step required! Just edit the bash script and test.

### Release Process
Releases are typically managed via tags. Tags should follow semantic versioning (e.g., v1.0.0).
