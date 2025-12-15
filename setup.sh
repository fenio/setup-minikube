#!/usr/bin/env bash
set -e

echo "::group::Installing Minikube"
echo "Starting Minikube setup..."

# Get inputs
VERSION="${INPUT_VERSION:-stable}"
KUBERNETES_VERSION="${INPUT_KUBERNETES_VERSION:-stable}"
DRIVER="${INPUT_DRIVER:-docker}"
CONTAINER_RUNTIME="${INPUT_CONTAINER_RUNTIME:-}"
WAIT_FOR_READY="${INPUT_WAIT_FOR_READY:-true}"
TIMEOUT="${INPUT_TIMEOUT:-300}"
DNS_READINESS="${INPUT_DNS_READINESS:-true}"

if [ -n "$CONTAINER_RUNTIME" ]; then
  echo "Configuration: version=$VERSION, kubernetes-version=$KUBERNETES_VERSION, driver=$DRIVER, container-runtime=$CONTAINER_RUNTIME, wait-for-ready=$WAIT_FOR_READY, timeout=${TIMEOUT}s, dns-readiness=$DNS_READINESS"
else
  echo "Configuration: version=$VERSION, kubernetes-version=$KUBERNETES_VERSION, driver=$DRIVER, wait-for-ready=$WAIT_FOR_READY, timeout=${TIMEOUT}s, dns-readiness=$DNS_READINESS"
fi

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
    echo "::error::Unsupported architecture: $ARCH"
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
if [ -n "$CONTAINER_RUNTIME" ]; then
  echo "Starting Minikube cluster with driver=$DRIVER, kubernetes-version=$KUBERNETES_VERSION, container-runtime=$CONTAINER_RUNTIME..."
else
  echo "Starting Minikube cluster with driver=$DRIVER, kubernetes-version=$KUBERNETES_VERSION..."
fi

START_ARGS="start --driver=$DRIVER"
if [ "$KUBERNETES_VERSION" != "stable" ]; then
  START_ARGS="$START_ARGS --kubernetes-version=$KUBERNETES_VERSION"
fi
if [ -n "$CONTAINER_RUNTIME" ]; then
  START_ARGS="$START_ARGS --container-runtime=$CONTAINER_RUNTIME"
fi

# Fix for driver=none with systemd-resolved (causes CoreDNS loop)
# See: https://coredns.io/plugins/loop/#troubleshooting-loops-in-kubernetes-clusters
# See: https://github.com/kubernetes/minikube/issues/3511
if [ "$DRIVER" = "none" ]; then
  echo "::group::Configuring network for none driver"
  
  # Enable IP forwarding (required for pod networking)
  echo "Enabling IP forwarding..."
  sudo sysctl -w net.ipv4.ip_forward=1
  sudo sysctl -w net.ipv6.conf.all.forwarding=1 2>/dev/null || true
  
  # Set iptables FORWARD policy to ACCEPT
  echo "Configuring iptables..."
  sudo iptables -P FORWARD ACCEPT
  
  # Load br_netfilter module for bridge networking
  if ! lsmod | grep -q br_netfilter; then
    echo "Loading br_netfilter module..."
    sudo modprobe br_netfilter || echo "::warning::Failed to load br_netfilter module"
  fi
  
  # Enable bridge netfilter for proper pod-to-service communication
  if [ -f /proc/sys/net/bridge/bridge-nf-call-iptables ]; then
    sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
    sudo sysctl -w net.bridge.bridge-nf-call-ip6tables=1 2>/dev/null || true
  fi
  
  echo "::endgroup::"
  
  if systemctl is-active --quiet systemd-resolved 2>/dev/null; then
    echo "Detected systemd-resolved, configuring kubelet to use real resolv.conf..."
    if [ -f /run/systemd/resolve/resolv.conf ]; then
      START_ARGS="$START_ARGS --extra-config=kubelet.resolv-conf=/run/systemd/resolve/resolv.conf"
      echo "Added --extra-config=kubelet.resolv-conf=/run/systemd/resolve/resolv.conf"
    else
      echo "::warning::systemd-resolved is active but /run/systemd/resolve/resolv.conf not found"
    fi
  fi
  
  # Use CNI for networking instead of the default bridge
  START_ARGS="$START_ARGS --cni=bridge"
fi

# shellcheck disable=SC2086
minikube $START_ARGS

echo "✓ Minikube installed and started"
echo "::endgroup::"

# Set kubeconfig output
KUBECONFIG_PATH="$HOME/.kube/config"
echo "kubeconfig=$KUBECONFIG_PATH" >> "$GITHUB_OUTPUT"
echo "KUBECONFIG=$KUBECONFIG_PATH" >> "$GITHUB_ENV"
echo "KUBECONFIG exported: $KUBECONFIG_PATH"

# Wait for cluster ready if requested
if [ "$WAIT_FOR_READY" = "true" ]; then
  echo "::group::Waiting for cluster ready"
  echo "Waiting for Minikube cluster to be ready (timeout: ${TIMEOUT}s)..."
  
  START_TIME=$(date +%s)
  
  while true; do
    ELAPSED=$(($(date +%s) - START_TIME))
    
    if [ "$ELAPSED" -gt "$TIMEOUT" ]; then
      echo "::error::Timeout waiting for cluster to be ready"
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
      echo "Minikube is running"
      
      if kubectl cluster-info > /dev/null 2>&1; then
        echo "kubectl can connect to API server"
        
        # Check if all nodes are Ready
        if ! kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready " > /dev/null; then
          echo "All nodes are Ready"
          
          # Check if core pods are running
          if ! kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Running\|Completed" > /dev/null; then
            echo "All kube-system pods are running"
            
            # Check if all pods are fully ready (not just Running, but all containers ready)
            # The READY column shows "X/Y" - we need X to equal Y for all pods
            NOT_READY=$(kubectl get pods -n kube-system --no-headers 2>/dev/null | grep -v "Completed" | awk '{split($2,a,"/"); if(a[1]!=a[2]) print $1}')
            if [ -z "$NOT_READY" ]; then
              echo "All kube-system pods are fully ready"
              echo "✓ Minikube cluster is fully ready!"
              echo "::endgroup::"
              break
            else
              echo "Some kube-system pods not fully ready yet: $NOT_READY"
            fi
          else
            echo "Some kube-system pods not running yet"
          fi
        else
          echo "Some nodes not Ready yet"
        fi
      else
        echo "kubectl cannot connect yet"
      fi
    else
      echo "Minikube not running yet"
    fi
    
    echo "Cluster not ready yet, waiting... (${ELAPSED}/${TIMEOUT}s)"
    sleep 5
    done
fi

# DNS readiness check (if requested)
if [ "$DNS_READINESS" = "true" ]; then
  echo "::group::Testing DNS readiness"
  echo "Verifying CoreDNS and DNS resolution..."
  
  # Wait for CoreDNS pods to be ready
  echo "Waiting for CoreDNS to be ready..."
  kubectl wait --for=condition=ready --timeout=240s pod -l k8s-app=kube-dns -n kube-system
  echo "✓ CoreDNS is ready"
  
  # Create a test pod and verify DNS resolution
  kubectl run dns-test --image=public.ecr.aws/docker/library/busybox:stable --restart=Never -- sleep 300
  kubectl wait --for=condition=ready --timeout=120s pod/dns-test
  
  if kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local; then
    echo "✓ DNS resolution is working"
  else
    echo "::error::DNS resolution failed"
    kubectl delete pod dns-test --ignore-not-found
    exit 1
  fi
  
  # Cleanup test pod
  kubectl delete pod dns-test --ignore-not-found
  echo "::endgroup::"
fi

echo "✓ Minikube setup completed successfully!"
