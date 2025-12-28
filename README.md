# CKS Practice Lab

A single-command setup for a 3-node Kubernetes cluster optimized for CKS exam preparation.

## Prerequisites

- macOS with Multipass installed (`brew install multipass`)
- At least 8GB RAM available (6GB for VMs + system)
- ~60GB disk space

## Quick Start

```bash
# Create the cluster (takes ~5-8 minutes)
./create-cluster.sh

# Destroy when done
./destroy-cluster.sh
```

## What Gets Created

| Node | Role | Resources |
|------|------|-----------|
| control | Control plane | 2 vCPU, 2GB RAM, 20GB disk |
| worker1 | Worker | 2 vCPU, 2GB RAM, 20GB disk |
| worker2 | Worker | 2 vCPU, 2GB RAM, 20GB disk |

### Components Installed

- **Kubernetes 1.29** via kubeadm
- **Calico CNI** for NetworkPolicy support
- **containerd** as container runtime

### CKS Tools (on control plane)

- **Trivy** - Container image vulnerability scanner
- **kube-bench** - CIS Kubernetes Benchmark
- **Falco** - Runtime security monitoring

## Usage

### Access the cluster

```bash
# SSH into nodes
multipass shell control
multipass shell worker1
multipass shell worker2

# Use kubectl from your Mac
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

### Run CKS tools

```bash
# On control plane
multipass shell control

# Scan an image for vulnerabilities
trivy image nginx:latest

# Run CIS benchmark
sudo kube-bench

# Start Falco runtime monitoring
sudo systemctl start falco
sudo journalctl -fu falco
```

## CKS Practice Areas

### 1. Cluster Hardening

```bash
# Check API server config
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml

# Configure audit logging
sudo vim /etc/kubernetes/audit-policy.yaml
```

### 2. Network Policies

```bash
# Create default deny
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF
```

### 3. Pod Security Admission

```bash
# Label namespace for enforcement
kubectl label namespace default pod-security.kubernetes.io/enforce=restricted
```

### 4. RBAC

```bash
# Create service account with limited permissions
kubectl create serviceaccount limited-sa
kubectl create role pod-reader --verb=get,list --resource=pods
kubectl create rolebinding limited-sa-binding --role=pod-reader --serviceaccount=default:limited-sa
```

### 5. Secrets Management

```bash
# Encrypt secrets at rest
sudo vim /etc/kubernetes/enc/encryption-config.yaml
```

## Customization

Edit `cloud-init.yaml` to change the base configuration.

Edit `create-cluster.sh` variables at the top to adjust:
- Node names
- CPU/memory/disk allocation
- Kubernetes version

## Troubleshooting

### Nodes not becoming Ready

```bash
# Check kubelet status
multipass exec control -- sudo systemctl status kubelet

# Check Calico pods
multipass exec control -- kubectl get pods -n calico-system
```

### Cloud-init issues

```bash
# Check cloud-init logs
multipass exec control -- sudo cat /var/log/cloud-init-output.log
```

### Reset and retry

```bash
# On any node
multipass exec control -- sudo kubeadm reset -f
```
