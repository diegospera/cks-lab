# CKS Practice Lab

A single-command setup for a 3-node Kubernetes cluster optimized for CKS (Certified Kubernetes Security Specialist) exam preparation.

## Features

- **Latest Kubernetes** (1.35 by default, configurable)
- **Calico CNI** v3.31 for NetworkPolicy support
- **Audit logging** pre-configured and enabled
- **CKS tools** pre-installed (Trivy, kube-bench, Falco)
- **Security best practices** out of the box
- **Ubuntu 24.04** with cgroup v2

## Prerequisites

- macOS with Multipass installed (`brew install multipass`)
- At least 16GB RAM available (12GB for VMs + system)
- ~75GB disk space

## Quick Start

```bash
# Create the cluster (takes ~5-8 minutes)
./create-cluster.sh

# Destroy when done
./destroy-cluster.sh
```

## Options

```bash
# Default: Create cluster with latest K8s (1.35)
./create-cluster.sh

# Specify Kubernetes version
./create-cluster.sh -k 1.34
./create-cluster.sh -k 1.30   # Uses v1beta3 kubeadm API

# Verbose mode: stream cloud-init logs
./create-cluster.sh -v

# Show help
./create-cluster.sh -h
```

## Version Compatibility

| K8s Version | kubeadm API | cgroup | Notes |
|-------------|-------------|--------|-------|
| 1.35+ | v1beta4 | v2 required | Latest, cgroup v1 dropped |
| 1.31-1.34 | v1beta4 | v2 recommended | New extraArgs format |
| 1.22-1.30 | v1beta3 | v1 or v2 | Legacy extraArgs format |

The script automatically detects which kubeadm API version to use based on your chosen Kubernetes version.

## Cluster Specifications

| Node | Role | Resources |
|------|------|-----------|
| control | Control plane | 2 vCPU, 4GB RAM, 25GB disk |
| worker1 | Worker | 2 vCPU, 4GB RAM, 25GB disk |
| worker2 | Worker | 2 vCPU, 4GB RAM, 25GB disk |

### Components

| Component | Version | Notes |
|-----------|---------|-------|
| Kubernetes | 1.35 | Latest stable, configurable |
| Calico | 3.31.2 | NetworkPolicy support |
| containerd | Latest | cgroup v2 enabled |
| Ubuntu | 24.04 | LTS with modern kernel |

### CKS Tools Pre-installed

| Tool | Purpose |
|------|---------|
| **Trivy** | Container image vulnerability scanning |
| **kube-bench** | CIS Kubernetes Benchmark checks |
| **Falco** | Runtime security monitoring |

### Security Features Enabled

- ✓ Audit logging with sensible policy
- ✓ NodeRestriction admission plugin
- ✓ RBAC enabled
- ✓ Pod Security Admission ready
- ✓ NetworkPolicy support (Calico)

## Usage

### Access the Cluster

```bash
# SSH into nodes
multipass shell control
multipass shell worker1
multipass shell worker2

# Use kubectl from your Mac
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

### CKS Tools

```bash
# SSH to control plane
multipass shell control

# Scan an image for vulnerabilities
trivy image nginx:latest
trivy image --severity HIGH,CRITICAL nginx:latest

# Run CIS benchmark
sudo kube-bench run --targets=master
sudo kube-bench run --targets=node

# Start Falco runtime monitoring
sudo systemctl start falco
sudo journalctl -fu falco
```

### View Audit Logs

```bash
multipass shell control
sudo tail -f /var/log/kubernetes/audit/audit.log | jq .
```

## CKS Practice Scenarios

### 1. Cluster Hardening

```bash
# Check API server config
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml

# Review audit policy
sudo cat /etc/kubernetes/audit-policy.yaml

# Check etcd encryption (setup exercise)
sudo cat /etc/kubernetes/enc/encryption-config.yaml
```

### 2. Network Policies

```bash
# Create default deny all
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# Allow specific traffic
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-nginx
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: nginx
  ingress:
  - from:
    - podSelector:
        matchLabels:
          access: "true"
    ports:
    - protocol: TCP
      port: 80
EOF
```

### 3. Pod Security Admission

```bash
# Create namespace with restricted policy
kubectl create namespace restricted
kubectl label namespace restricted \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/warn=restricted

# Test with a privileged pod (should fail)
kubectl -n restricted run test --image=nginx --privileged
```

### 4. RBAC

```bash
# Create service account with limited permissions
kubectl create serviceaccount audit-sa
kubectl create role pod-reader --verb=get,list --resource=pods
kubectl create rolebinding audit-sa-binding \
  --role=pod-reader \
  --serviceaccount=default:audit-sa

# Test permissions
kubectl auth can-i get pods --as=system:serviceaccount:default:audit-sa
kubectl auth can-i delete pods --as=system:serviceaccount:default:audit-sa
```

### 5. Secrets Encryption at Rest

```bash
# Create encryption config (on control plane)
sudo tee /etc/kubernetes/enc/encryption-config.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: $(head -c 32 /dev/urandom | base64)
      - identity: {}
EOF

# Then update kube-apiserver manifest to use it
```

### 6. Container Security Context

```bash
# Run pod with security context
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
EOF
```

## Key Paths on Control Plane

| Path | Description |
|------|-------------|
| `/etc/kubernetes/manifests/` | Static pod manifests (API server, etcd, etc.) |
| `/etc/kubernetes/audit-policy.yaml` | Audit policy configuration |
| `/var/log/kubernetes/audit/` | Audit log files |
| `/etc/kubernetes/pki/` | Cluster certificates |
| `/etc/kubernetes/enc/` | Encryption configs (for practice) |

## Troubleshooting

### Nodes not becoming Ready

```bash
# Check kubelet status
multipass exec control -- sudo systemctl status kubelet

# Check kubelet logs
multipass exec control -- sudo journalctl -xeu kubelet

# Check Calico pods
multipass exec control -- kubectl get pods -n calico-system
```

### Cloud-init issues

```bash
# Check cloud-init status
multipass exec control -- cloud-init status

# Check cloud-init logs
multipass exec control -- sudo cat /var/log/cloud-init-output.log
```

### Reset a node

```bash
multipass exec control -- sudo kubeadm reset -f
```

### Complete rebuild

```bash
./destroy-cluster.sh
./create-cluster.sh
```

## Customization

Edit variables at the top of `create-cluster.sh`:

```bash
CPUS=2          # vCPUs per node
MEMORY="4G"     # RAM per node
DISK="25G"      # Disk per node
K8S_VERSION="1.35"  # Or use -k flag
```

## Exam Tips

1. **Practice with audit logs** - The exam may ask you to configure audit policies
2. **Know NetworkPolicy syntax** - Practice creating ingress/egress rules
3. **Understand PSA** - Know how to label namespaces for Pod Security Admission
4. **Trivy and Falco** - Know how to scan images and interpret Falco rules
5. **kube-bench** - Understand CIS benchmark failures and remediations
6. **Secrets** - Practice creating encryption configs
7. **RBAC** - Create roles, rolebindings, and test with `kubectl auth can-i`
