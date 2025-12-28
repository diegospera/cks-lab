#!/bin/bash

#######################################
# CKS Practice Cluster Destroy Script
#######################################

# Configuration
ALL_NODES=("control" "worker1" "worker2")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_LOCAL="$SCRIPT_DIR/kubeconfig"
CLOUD_INIT="$SCRIPT_DIR/cloud-init.yaml"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo ""
echo "========================================"
echo "  CKS Practice Cluster Teardown"
echo "========================================"
echo ""

# Confirm destruction
read -p "This will destroy all cluster VMs. Are you sure? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Delete VMs
for node in "${ALL_NODES[@]}"; do
    if multipass info "$node" &> /dev/null; then
        echo -ne "  ${CYAN}$node${NC}: deleting..."
        multipass delete "$node"
        echo -e "\r\033[K  ${CYAN}$node${NC}: ${GREEN}✓ deleted${NC}"
    else
        echo -e "  ${CYAN}$node${NC}: ${YELLOW}not found, skipping${NC}"
    fi
done

# Purge deleted VMs
echo ""
echo -e "${YELLOW}Purging deleted VMs...${NC}"
multipass purge

# Clean up generated files
echo -e "${YELLOW}Cleaning up local files...${NC}"
[[ -f "$KUBECONFIG_LOCAL" ]] && rm "$KUBECONFIG_LOCAL" && echo "  Removed kubeconfig"
[[ -f "$CLOUD_INIT" ]] && rm "$CLOUD_INIT" && echo "  Removed cloud-init.yaml"

echo ""
echo -e "${GREEN}Cluster destroyed successfully!${NC}"
echo ""
echo "To recreate: ./create-cluster.sh"
echo ""
