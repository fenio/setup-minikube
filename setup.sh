#!/bin/bash
set -e

echo "Starting Minikube setup..."

# Get inputs
VERSION="${INPUT_VERSION:-stable}"
KUBERNETES_VERSION="${INPUT_KUBERNETES_VERSION:-stable}"
DRIVER="${INPUT_DRIVER:-docker}"
WAIT_FOR_READY="${INPUT_WAIT_FOR_READY:-true}"
TIMEOUT="${INPUT_TIMEOUT:-300}"

echo "Configuration: version=$VERSION, kubernetes-version=$KUBERNETES_VERSION, driver=$DRIVER, wait-for-ready=$WAIT_FOR_READY, timeout=${TIMEOUT}s"

# Detect platform and architecture
PLATFORM=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case $ARCH in
  x86_64)
    BINARY_ARCH="amd64"
    ;;
  aarch64|arm64)
    BINARY_ARCH="arm64"
    ;;
  armv7l)
    BINARY_ARCH="arm"
    ;;
  *)
    echo "Error: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "Platform: $PLATFORM, Architecture: $BINARY_ARCH"

# Construct download URL
if [ "$VERSION" = "latest" ] || [ "$VERSION" = "stable" ]; then
  DOWNLOAD_URL="https://storage.googleapis.com/minikube/releases/latest/minikube-${PLATFORM}-${BINARY_ARCH}"
else
  DOWNLOAD_URL="https://github.com/kubernetes/minikube/releases/download/${VERSION}/minikube-${PLATFORM}-${BINARY_ARCH}"
fi

echo "Downloading minikube from: $DOWNLOAD_URL"

# Download and install minikube
curl -sfL "$DOWNLOAD_URL" -o /tmp/minikube
sudo install /tmp/minikube /usr/local/bin/minikube
rm -f /tmp/minikube

# Verify installation
echo "Verifying installation..."
minikube version

# Start minikube
echo "Starting Minikube cluster with driver=$DRIVER, kubernetes-version=$KUBERNETES_VERSION..."

START_ARGS="start --driver=$DRIVER"
if [ "$KUBERNETES_VERSION" != "stable" ]; then
  START_ARGS="$START_ARGS --kubernetes-version=$KUBERNETES_VERSION"
fi

# shellcheck disable=SC2086
minikube $START_ARGS

# Set kubeconfig output
KUBECONFIG_PATH="$HOME/.kube/config"
echo "kubeconfig=$KUBECONFIG_PATH" >> "$GITHUB_OUTPUT"
echo "KUBECONFIG=$KUBECONFIG_PATH" >> "$GITHUB_ENV"
echo "KUBECONFIG exported: $KUBECONFIG_PATH"

# Wait for cluster ready if requested
if [ "$WAIT_FOR_READY" = "true" ]; then
  echo "Waiting for Minikube cluster to be ready (timeout: ${TIMEOUT}s)..."
  
  START_TIME=$(date +%s)
  
  while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    
    if [ "$ELAPSED" -gt "$TIMEOUT" ]; then
      echo "Error: Timeout waiting for cluster to be ready"
      echo "=== Minikube Status ==="
      minikube status || true
      echo "=== Minikube Logs ==="
      minikube logs --length=100 || true
      echo "=== Kubectl Cluster Info ==="
      kubectl cluster-info || true
      echo "=== Nodes ==="
      kubectl get nodes -o wide || true
      echo "=== Kube-system Pods ==="
      kubectl get pods -n kube-system || true
      exit 1
    fi
    
    # Check if cluster is ready
    if minikube status > /dev/null 2>&1; then
      echo "  Minikube is running"
      
      if kubectl cluster-info > /dev/null 2>&1; then
        echo "  kubectl can connect to API server"
        
        # Check if all nodes are Ready
        if ! kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " > /dev/null; then
          echo "  All nodes are Ready"
          
          # Check if core pods are running
          if ! kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" > /dev/null; then
            echo "  All kube-system pods are running"
            echo "✓ Minikube cluster is fully ready!"
            break
          else
            echo "  Some kube-system pods not running yet"
          fi
        else
          echo "  Some nodes not Ready yet"
        fi
      else
        echo "  kubectl cannot connect yet"
      fi
    else
      echo "  Minikube not running yet"
    fi
    
    echo "  Cluster not ready yet, waiting... ($ELAPSED/${TIMEOUT}s)"
    sleep 5
  done
fi

echo "✓ Minikube setup completed successfully!"
