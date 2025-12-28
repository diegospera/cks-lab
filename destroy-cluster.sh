#!/bin/bash

#######################################
# CKS Practice Cluster Destroy Script
#######################################

# Configuration
ALL_NODES=("control" "worker1" "worker2")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KUBECONFIG_LOCAL="$SCRIPT_DIR/kubeconfig"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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
        echo -e "${YELLOW}Deleting $node...${NC}"
        multipass delete "$node"
    else
        echo -e "VM '$node' not found, skipping..."
    fi
done

# Purge deleted VMs
echo -e "${YELLOW}Purging deleted VMs...${NC}"
multipass purge

# Clean up kubeconfig
if [[ -f "$KUBECONFIG_LOCAL" ]]; then
    echo -e "${YELLOW}Removing local kubeconfig...${NC}"
    rm "$KUBECONFIG_LOCAL"
fi

echo ""
echo -e "${GREEN}Cluster destroyed successfully!${NC}"
echo ""
echo "To recreate: ./create-cluster.sh"
echo ""
