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
MEMORY="2G"
DISK="20G"
UBUNTU_VERSION="22.04"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yaml"
KUBECONFIG_LOCAL="$SCRIPT_DIR/kubeconfig"

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
    echo "  -v, --verbose    Show detailed cloud-init progress and logs"
    echo "  -h, --help       Show this help message"
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

    if [[ ! -f "$CLOUD_INIT" ]]; then
        log_error "cloud-init.yaml not found at $CLOUD_INIT"
        exit 1
    fi

    log_success "Prerequisites check passed"
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

    # Initialize kubeadm
    log_progress "Running kubeadm init (this takes 1-2 minutes)..."
    
    if $VERBOSE; then
        multipass exec "$CONTROL_NODE" -- sudo kubeadm init \
            --apiserver-advertise-address="$CONTROL_IP" \
            --pod-network-cidr=192.168.0.0/16 \
            --skip-phases=addon/kube-proxy 2>&1 | tee /tmp/kubeadm-init.log
    else
        multipass exec "$CONTROL_NODE" -- sudo kubeadm init \
            --apiserver-advertise-address="$CONTROL_IP" \
            --pod-network-cidr=192.168.0.0/16 \
            --skip-phases=addon/kube-proxy > /tmp/kubeadm-init.log 2>&1
    fi

    # Setup kubectl for ubuntu user
    log_progress "Configuring kubectl..."
    multipass exec "$CONTROL_NODE" -- bash -c "mkdir -p \$HOME/.kube && sudo cp /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"

    log_success "Control plane initialized"
}

#######################################
# Install CNI (Calico)
#######################################
install_cni() {
    log_info "Installing Calico CNI..."

    # Install Calico operator and CRDs
    log_progress "Applying Tigera operator..."
    multipass exec "$CONTROL_NODE" -- kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml 2>/dev/null

    # Wait for operator
    log_progress "Waiting for operator to be ready..."
    sleep 10

    # Install Calico custom resources
    log_progress "Applying Calico custom resources..."
    multipass exec "$CONTROL_NODE" -- kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml 2>/dev/null

    log_success "Calico CNI installed"
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
    echo ""
    echo "========================================"
    echo -e "${GREEN}CKS Practice Cluster Ready!${NC}"
    echo "========================================"
    echo ""
    multipass exec "$CONTROL_NODE" -- kubectl get nodes -o wide
    echo ""
    echo -e "${BLUE}Quick commands:${NC}"
    echo "  multipass shell control     # SSH to control plane"
    echo "  multipass shell worker1     # SSH to worker1"
    echo "  multipass shell worker2     # SSH to worker2"
    echo ""
    echo -e "${BLUE}CKS tools installed on control plane:${NC}"
    echo "  trivy image nginx:latest    # Scan container images"
    echo "  sudo kube-bench             # Run CIS benchmark"
    echo "  sudo systemctl start falco  # Start Falco runtime security"
    echo ""
    echo -e "${BLUE}Useful practice areas:${NC}"
    echo "  - Network Policies (Calico installed)"
    echo "  - Pod Security Admission"
    echo "  - RBAC & ServiceAccounts"
    echo "  - Audit logging"
    echo "  - Secrets management"
    echo "  - Container runtime sandboxing"
    echo ""
    echo -e "${YELLOW}To destroy cluster:${NC} ./destroy-cluster.sh"
    echo ""
}

#######################################
# Main
#######################################
main() {
    parse_args "$@"
    
    echo ""
    echo "========================================"
    echo "  CKS Practice Cluster Setup"
    if $VERBOSE; then
        echo "  (verbose mode)"
    fi
    echo "========================================"
    echo ""

    check_prerequisites
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
