#!/bin/bash
set -e

#######################################
# CKS Practice Cluster Setup Script
# Creates a 3-node kubeadm cluster using Multipass
#######################################

# Configuration
CONTROL_NODE="control"
WORKER_NODES=("worker1" "worker2")
ALL_NODES=("$CONTROL_NODE" "${WORKER_NODES[@]}")
CPUS=2
MEMORY="4G"  # Increased for 1.35
DISK="25G"
UBUNTU_VERSION="24.04"  # Newer Ubuntu for better compatibility
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yaml"
KUBECONFIG_LOCAL="$SCRIPT_DIR/kubeconfig"

# Kubernetes version (default to latest stable)
K8S_VERSION="1.35"

# Flags
VERBOSE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_progress() { echo -e "${DIM}       $1${NC}"; }
log_verbose() { if $VERBOSE; then echo -e "${CYAN}[VERBOSE]${NC} $1"; fi; }

#######################################
# Parse arguments
#######################################
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -v, --verbose          Show detailed cloud-init progress and logs"
    echo "  -k, --k8s-version VER  Kubernetes version (default: $K8S_VERSION)"
    echo "  -h, --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                     # Create cluster with K8s $K8S_VERSION (latest)"
    echo "  $0 -k 1.34             # Create cluster with K8s 1.34"
    echo "  $0 -k 1.30             # Create cluster with K8s 1.30 (uses v1beta3)"
    echo "  $0 -v                  # Verbose mode with full logs"
    echo ""
    echo "Version compatibility:"
    echo "  K8s 1.31+  → kubeadm API v1beta4, requires cgroup v2 for 1.35+"
    echo "  K8s 1.22-1.30 → kubeadm API v1beta3"
    echo ""
    exit 0
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -k|--k8s-version)
                K8S_VERSION="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

#######################################
# Check prerequisites
#######################################
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    if ! command -v multipass &> /dev/null; then
        log_error "Multipass is not installed. Install with: brew install multipass"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

#######################################
# Determine kubeadm API version
# v1beta4 for K8s 1.31+, v1beta3 for older
#######################################
get_kubeadm_api_version() {
    local major minor
    major=$(echo "$K8S_VERSION" | cut -d. -f1)
    minor=$(echo "$K8S_VERSION" | cut -d. -f2)
    
    # v1beta4 introduced in 1.31
    if [[ "$major" -ge 1 && "$minor" -ge 31 ]]; then
        echo "v1beta4"
    else
        echo "v1beta3"
    fi
}

#######################################
# Check if K8s version requires cgroup v2
# K8s 1.35+ dropped cgroup v1 support
#######################################
check_cgroup_requirements() {
    local minor
    minor=$(echo "$K8S_VERSION" | cut -d. -f2)
    
    if [[ "$minor" -ge 35 ]]; then
        log_info "Kubernetes $K8S_VERSION requires cgroup v2 (Ubuntu 24.04 provides this)"
    fi
}

#######################################
# Generate cloud-init config
#######################################
generate_cloud_init() {
    log_info "Generating cloud-init config for Kubernetes $K8S_VERSION..."
    
    cat > "$CLOUD_INIT" <<EOF
#cloud-config
package_update: true
package_upgrade: false

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gpg
  - containerd
  - socat
  - conntrack
  - ethtool
  - iptables

write_files:
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

  - path: /etc/crictl.yaml
    content: |
      runtime-endpoint: unix:///run/containerd/containerd.sock
      image-endpoint: unix:///run/containerd/containerd.sock
      timeout: 10

  # Audit policy for CKS practice
  - path: /etc/kubernetes/audit-policy.yaml
    content: |
      apiVersion: audit.k8s.io/v1
      kind: Policy
      rules:
        - level: Metadata
          resources:
          - group: ""
            resources: ["secrets", "configmaps"]
        - level: RequestResponse
          resources:
          - group: ""
            resources: ["pods"]
        - level: None
          users: ["system:kube-proxy"]
          verbs: ["watch"]
          resources:
          - group: ""
            resources: ["endpoints", "services"]
        - level: Metadata
          omitStages:
          - RequestReceived

runcmd:
  # Disable swap
  - swapoff -a
  - sed -i '/ swap / s/^/#/' /etc/fstab

  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system

  # Configure containerd with cgroup v2
  - mkdir -p /etc/containerd
  - containerd config default > /etc/containerd/config.toml
  - sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
  - systemctl restart containerd
  - systemctl enable containerd

  # Add Kubernetes apt repo
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /' > /etc/apt/sources.list.d/kubernetes.list

  # Install kubeadm, kubelet, kubectl
  - apt-get update
  - apt-get install -y kubelet kubeadm kubectl
  - apt-mark hold kubelet kubeadm kubectl

  # Enable kubelet
  - systemctl enable kubelet

  # Create directories for CKS practice
  - mkdir -p /etc/kubernetes/enc
  - mkdir -p /var/log/kubernetes/audit

  # Signal that cloud-init is complete
  - touch /var/lib/cloud/instance/kubeadm-ready
EOF

    log_success "Cloud-init config generated"
}

#######################################
# Launch VMs
#######################################
launch_vms() {
    log_info "Launching VMs..."
    echo ""

    for node in "${ALL_NODES[@]}"; do
        if multipass info "$node" &> /dev/null; then
            echo -e "  ${CYAN}$node${NC}: ${YELLOW}already exists, skipping${NC}"
        else
            echo -ne "  ${CYAN}$node${NC}: launching..."
            multipass launch -n "$node" -c "$CPUS" -m "$MEMORY" -d "$DISK" "$UBUNTU_VERSION" --cloud-init "$CLOUD_INIT" 2>/dev/null
            echo -e "\r\033[K  ${CYAN}$node${NC}: ${GREEN}✓ launched${NC}"
        fi
    done

    echo ""
    log_success "All VMs launched"
}

#######################################
# Wait for cloud-init to complete
#######################################
get_cloud_init_stage() {
    local node=$1
    local log_output
    
    # Try to get the last meaningful line from cloud-init-output.log
    log_output=$(multipass exec "$node" -- tail -20 /var/log/cloud-init-output.log 2>/dev/null | grep -E "(Setting up|Unpacking|Installing|Get:|Hit:|Fetched|Reading|Processing|modprobe|systemctl|kubeadm|kubelet|kubectl)" | tail -1 || echo "")
    
    if [[ -n "$log_output" ]]; then
        # Truncate long lines
        echo "${log_output:0:70}"
    else
        echo "Initializing..."
    fi
}

stream_cloud_init_logs() {
    local node=$1
    log_verbose "Streaming cloud-init logs for $node (Ctrl+C to stop streaming, cluster setup continues)..."
    echo ""
    
    # Stream the log in background, kill when cloud-init completes
    multipass exec "$node" -- tail -f /var/log/cloud-init-output.log 2>/dev/null &
    local tail_pid=$!
    
    # Wait for completion marker
    while ! multipass exec "$node" -- test -f /var/lib/cloud/instance/kubeadm-ready 2>/dev/null; do
        sleep 2
    done
    
    # Kill the tail process
    kill $tail_pid 2>/dev/null || true
    wait $tail_pid 2>/dev/null || true
    echo ""
}

wait_for_cloud_init() {
    log_info "Waiting for cloud-init to complete on all nodes..."
    echo ""

    for node in "${ALL_NODES[@]}"; do
        local start_time=$(date +%s)
        
        if $VERBOSE; then
            echo -e "${BLUE}━━━ $node cloud-init logs ━━━${NC}"
            stream_cloud_init_logs "$node"
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            echo -e "${GREEN}✓ $node ready${NC} (${duration}s)"
            echo ""
        else
            echo -ne "  ${CYAN}$node${NC}: "
            
            local last_stage=""
            while ! multipass exec "$node" -- test -f /var/lib/cloud/instance/kubeadm-ready 2>/dev/null; do
                current_stage=$(get_cloud_init_stage "$node")
                
                # Only update if stage changed
                if [[ "$current_stage" != "$last_stage" && -n "$current_stage" ]]; then
                    # Clear line and print new stage
                    echo -ne "\r\033[K  ${CYAN}$node${NC}: ${DIM}$current_stage${NC}"
                    last_stage="$current_stage"
                fi
                
                sleep 3
            done
            
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            echo -e "\r\033[K  ${CYAN}$node${NC}: ${GREEN}✓ ready${NC} (${duration}s)"
        fi
    done

    # Extra wait for services to stabilize
    echo ""
    log_info "Letting services stabilize (10s)..."
    sleep 10
    log_success "Cloud-init completed on all nodes"
}

#######################################
# Initialize control plane
#######################################
init_control_plane() {
    log_info "Initializing Kubernetes control plane..."

    # Get control plane IP
    CONTROL_IP=$(multipass info "$CONTROL_NODE" --format csv | tail -1 | cut -d',' -f3)
    log_progress "Control plane IP: $CONTROL_IP"

    # Determine kubeadm API version
    local KUBEADM_API_VERSION
    KUBEADM_API_VERSION=$(get_kubeadm_api_version)
    log_progress "Using kubeadm API $KUBEADM_API_VERSION"

    # Create kubeadm config with security best practices
    log_progress "Creating kubeadm configuration..."
    
    if [[ "$KUBEADM_API_VERSION" == "v1beta4" ]]; then
        # v1beta4 format (K8s 1.31+): extraArgs is a list of name/value pairs
        multipass exec "$CONTROL_NODE" -- bash -c "cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VERSION}.0
networking:
  podSubnet: 192.168.0.0/16
  serviceSubnet: 10.96.0.0/12
apiServer:
  extraArgs:
    - name: audit-policy-file
      value: /etc/kubernetes/audit-policy.yaml
    - name: audit-log-path
      value: /var/log/kubernetes/audit/audit.log
    - name: audit-log-maxage
      value: \"30\"
    - name: audit-log-maxbackup
      value: \"10\"
    - name: audit-log-maxsize
      value: \"100\"
    - name: enable-admission-plugins
      value: NodeRestriction
  extraVolumes:
    - name: audit-policy
      hostPath: /etc/kubernetes/audit-policy.yaml
      mountPath: /etc/kubernetes/audit-policy.yaml
      readOnly: true
    - name: audit-logs
      hostPath: /var/log/kubernetes/audit
      mountPath: /var/log/kubernetes/audit
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${CONTROL_IP}
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
EOF"
    else
        # v1beta3 format (K8s 1.22-1.30): extraArgs is a key/value map
        multipass exec "$CONTROL_NODE" -- bash -c "cat > /tmp/kubeadm-config.yaml <<EOF
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v${K8S_VERSION}.0
networking:
  podSubnet: 192.168.0.0/16
  serviceSubnet: 10.96.0.0/12
apiServer:
  extraArgs:
    audit-policy-file: /etc/kubernetes/audit-policy.yaml
    audit-log-path: /var/log/kubernetes/audit/audit.log
    audit-log-maxage: \"30\"
    audit-log-maxbackup: \"10\"
    audit-log-maxsize: \"100\"
    enable-admission-plugins: NodeRestriction
  extraVolumes:
    - name: audit-policy
      hostPath: /etc/kubernetes/audit-policy.yaml
      mountPath: /etc/kubernetes/audit-policy.yaml
      readOnly: true
    - name: audit-logs
      hostPath: /var/log/kubernetes/audit
      mountPath: /var/log/kubernetes/audit
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: ${CONTROL_IP}
nodeRegistration:
  criSocket: unix:///var/run/containerd/containerd.sock
EOF"
    fi

    # Initialize kubeadm
    log_progress "Running kubeadm init (this takes 1-2 minutes)..."
    
    if $VERBOSE; then
        multipass exec "$CONTROL_NODE" -- sudo kubeadm init \
            --config=/tmp/kubeadm-config.yaml \
            --skip-phases=addon/kube-proxy 2>&1 | tee /tmp/kubeadm-init.log
    else
        multipass exec "$CONTROL_NODE" -- sudo kubeadm init \
            --config=/tmp/kubeadm-config.yaml \
            --skip-phases=addon/kube-proxy > /tmp/kubeadm-init.log 2>&1
    fi

    # Setup kubectl for ubuntu user
    log_progress "Configuring kubectl..."
    multipass exec "$CONTROL_NODE" -- bash -c "mkdir -p \$HOME/.kube && sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"

    log_success "Control plane initialized with audit logging enabled"
}

#######################################
# Install CNI (Calico)
#######################################
install_cni() {
    log_info "Installing Calico CNI v3.31..."

    # Install Calico operator and CRDs
    log_progress "Applying Tigera operator..."
    multipass exec "$CONTROL_NODE" -- kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/tigera-operator.yaml 2>/dev/null

    # Wait for operator
    log_progress "Waiting for operator to be ready..."
    sleep 10

    # Install Calico custom resources
    log_progress "Applying Calico custom resources..."
    multipass exec "$CONTROL_NODE" -- kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.2/manifests/custom-resources.yaml 2>/dev/null

    log_success "Calico CNI v3.31 installed"
}

#######################################
# Join worker nodes
#######################################
join_workers() {
    log_info "Joining worker nodes..."

    # Get join command from control plane
    log_progress "Generating join token..."
    JOIN_CMD=$(multipass exec "$CONTROL_NODE" -- sudo kubeadm token create --print-join-command)

    echo ""
    for worker in "${WORKER_NODES[@]}"; do
        echo -ne "  ${CYAN}$worker${NC}: joining cluster..."
        multipass exec "$worker" -- sudo $JOIN_CMD 2>/dev/null
        echo -e "\r\033[K  ${CYAN}$worker${NC}: ${GREEN}✓ joined${NC}"
    done

    echo ""
    log_success "All workers joined"
}

#######################################
# Wait for nodes to be ready
#######################################
wait_for_nodes() {
    log_info "Waiting for all nodes to be Ready..."

    local attempts=0
    local max_attempts=30

    echo -ne "  Checking node status..."
    
    while [[ $attempts -lt $max_attempts ]]; do
        # Get node statuses
        NODE_STATUS=$(multipass exec "$CONTROL_NODE" -- kubectl get nodes --no-headers 2>/dev/null || echo "")
        READY_COUNT=$(echo "$NODE_STATUS" | grep -c " Ready" || echo "0")
        NOT_READY_COUNT=$(echo "$NODE_STATUS" | grep -c "NotReady" || echo "0")
        
        echo -ne "\r\033[K  Nodes: ${GREEN}$READY_COUNT Ready${NC}"
        if [[ "$NOT_READY_COUNT" -gt 0 ]]; then
            echo -ne ", ${YELLOW}$NOT_READY_COUNT NotReady${NC}"
        fi
        
        if [[ "$READY_COUNT" -eq 3 ]]; then
            echo -e "\r\033[K  Nodes: ${GREEN}3/3 Ready ✓${NC}"
            echo ""
            log_success "All nodes are Ready"
            return 0
        fi

        sleep 10
        ((attempts++))
    done

    echo ""
    log_warn "Timeout waiting for nodes. Check status with: multipass exec control -- kubectl get nodes"
}

#######################################
# Install CKS tools
#######################################
install_cks_tools() {
    log_info "Installing CKS practice tools..."

    # Install Trivy on control plane
    echo -ne "  ${CYAN}Trivy${NC}: installing..."
    multipass exec "$CONTROL_NODE" -- bash -c '
        sudo apt-get install -y wget gnupg > /dev/null 2>&1
        wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb generic main" | sudo tee /etc/apt/sources.list.d/trivy.list > /dev/null
        sudo apt-get update > /dev/null 2>&1
        sudo apt-get install -y trivy > /dev/null 2>&1
    '
    echo -e "\r\033[K  ${CYAN}Trivy${NC}: ${GREEN}✓ installed${NC}"

    # Install kube-bench
    echo -ne "  ${CYAN}kube-bench${NC}: installing..."
    multipass exec "$CONTROL_NODE" -- bash -c '
        curl -sLO https://github.com/aquasecurity/kube-bench/releases/download/v0.7.1/kube-bench_0.7.1_linux_amd64.deb
        sudo dpkg -i kube-bench_0.7.1_linux_amd64.deb > /dev/null 2>&1
        rm kube-bench_0.7.1_linux_amd64.deb
    '
    echo -e "\r\033[K  ${CYAN}kube-bench${NC}: ${GREEN}✓ installed${NC}"

    # Install Falco
    echo -ne "  ${CYAN}Falco${NC}: installing..."
    multipass exec "$CONTROL_NODE" -- bash -c '
        curl -fsSL https://falco.org/repo/falcosecurity-packages.asc | sudo gpg --dearmor -o /usr/share/keyrings/falco-archive-keyring.gpg 2>/dev/null
        echo "deb [signed-by=/usr/share/keyrings/falco-archive-keyring.gpg] https://download.falco.org/packages/deb stable main" | sudo tee /etc/apt/sources.list.d/falcosecurity.list > /dev/null
        sudo apt-get update > /dev/null 2>&1
        sudo FALCO_FRONTEND=noninteractive apt-get install -y falco > /dev/null 2>&1
    '
    echo -e "\r\033[K  ${CYAN}Falco${NC}: ${GREEN}✓ installed${NC}"

    echo ""
    log_success "CKS tools installed"
}

#######################################
# Copy kubeconfig to host
#######################################
copy_kubeconfig() {
    log_info "Copying kubeconfig to host..."

    multipass exec "$CONTROL_NODE" -- sudo cat /etc/kubernetes/admin.conf > "$KUBECONFIG_LOCAL"
    
    # Update the server address to use the VM's IP
    CONTROL_IP=$(multipass info "$CONTROL_NODE" --format csv | tail -1 | cut -d',' -f3)
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/127.0.0.1:[0-9]*/$CONTROL_IP:6443/" "$KUBECONFIG_LOCAL"
    else
        sed -i "s/127.0.0.1:[0-9]*/$CONTROL_IP:6443/" "$KUBECONFIG_LOCAL"
    fi

    chmod 600 "$KUBECONFIG_LOCAL"

    log_success "Kubeconfig saved to: $KUBECONFIG_LOCAL"
    echo ""
    echo -e "${GREEN}To use kubectl from your Mac:${NC}"
    echo "  export KUBECONFIG=$KUBECONFIG_LOCAL"
    echo ""
    echo -e "${GREEN}Or merge with existing config:${NC}"
    echo "  KUBECONFIG=~/.kube/config:$KUBECONFIG_LOCAL kubectl config view --flatten > ~/.kube/config.new && mv ~/.kube/config.new ~/.kube/config"
}

#######################################
# Print cluster info
#######################################
print_summary() {
    local KUBEADM_API_VERSION
    KUBEADM_API_VERSION=$(get_kubeadm_api_version)
    
    echo ""
    echo "========================================"
    echo -e "${GREEN}CKS Practice Cluster Ready!${NC}"
    echo "========================================"
    echo ""
    echo -e "${CYAN}Cluster Details:${NC}"
    echo "  Kubernetes:    v$K8S_VERSION"
    echo "  kubeadm API:   $KUBEADM_API_VERSION"
    echo "  CNI:           Calico v3.31"
    echo "  Runtime:       containerd (cgroup v2)"
    echo "  Ubuntu:        $UBUNTU_VERSION"
    echo "  Nodes:         3 (1 control + 2 workers)"
    echo ""
    multipass exec "$CONTROL_NODE" -- kubectl get nodes -o wide
    echo ""
    echo -e "${BLUE}Access:${NC}"
    echo "  multipass shell control     # SSH to control plane"
    echo "  multipass shell worker1     # SSH to worker1"
    echo "  multipass shell worker2     # SSH to worker2"
    echo ""
    echo -e "${BLUE}From your Mac:${NC}"
    echo "  export KUBECONFIG=$KUBECONFIG_LOCAL"
    echo ""
    echo -e "${BLUE}CKS Tools (on control plane):${NC}"
    echo "  trivy image nginx:latest              # Scan images for CVEs"
    echo "  sudo kube-bench run --targets=master  # CIS benchmark"
    echo "  sudo systemctl start falco            # Runtime security"
    echo "  sudo journalctl -fu falco             # View Falco alerts"
    echo ""
    echo -e "${BLUE}CKS Practice Features Enabled:${NC}"
    echo "  ✓ Audit logging (/var/log/kubernetes/audit/audit.log)"
    echo "  ✓ NetworkPolicy support (Calico)"
    echo "  ✓ Pod Security Admission ready"
    echo "  ✓ RBAC enabled"
    echo "  ✓ NodeRestriction admission plugin"
    echo ""
    echo -e "${BLUE}Useful Paths (on control plane):${NC}"
    echo "  /etc/kubernetes/manifests/         # Static pod manifests"
    echo "  /etc/kubernetes/audit-policy.yaml  # Audit policy"
    echo "  /var/log/kubernetes/audit/         # Audit logs"
    echo "  /etc/kubernetes/pki/               # Certificates"
    echo "  /etc/kubernetes/enc/               # Encryption configs (practice)"
    echo ""
    echo -e "${YELLOW}To destroy cluster:${NC} ./destroy-cluster.sh"
    echo ""
}

#######################################
# Main
#######################################
main() {
    parse_args "$@"
    
    local KUBEADM_API_VERSION
    KUBEADM_API_VERSION=$(get_kubeadm_api_version)
    
    echo ""
    echo "========================================"
    echo "  CKS Practice Cluster Setup"
    echo "  Kubernetes $K8S_VERSION (kubeadm $KUBEADM_API_VERSION)"
    if $VERBOSE; then
        echo "  (verbose mode)"
    fi
    echo "========================================"
    echo ""

    check_prerequisites
    check_cgroup_requirements
    generate_cloud_init
    launch_vms
    wait_for_cloud_init
    init_control_plane
    install_cni
    join_workers
    wait_for_nodes
    install_cks_tools
    copy_kubeconfig
    print_summary
}

main "$@"
