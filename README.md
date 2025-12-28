# CKS Practice Lab

A single-command setup for a 3-node Kubernetes cluster optimized for CKS (Certified Kubernetes Security Specialist) exam preparation.

**Aligned with the October 2024 CKS Curriculum Update**

## Features

- **Latest Kubernetes** (1.35 by default, configurable)
- **Cilium CNI** with WireGuard pod-to-pod encryption (NEW in Oct 2024)
- **Audit logging** pre-configured and enabled
- **CKS tools** pre-installed:
  - Trivy (image scanning)
  - kube-bench (CIS benchmarks)
  - Falco (runtime security)
  - Kubesec (static YAML analysis) - NEW
  - KubeLinter (manifest linting) - NEW
- **Security best practices** out of the box
- **Ubuntu 24.04** with cgroup v2

## Prerequisites

- macOS with Multipass installed (`brew install multipass`)
- At least 16GB RAM available (12GB for VMs + system)
- ~75GB disk space

## Quick Start

```bash
# Create the cluster (takes ~8-10 minutes)
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
| Cilium | Latest | CNI with WireGuard encryption |
| containerd | Latest | cgroup v2 enabled |
| Ubuntu | 24.04 | LTS with modern kernel |

### CKS Tools Pre-installed (October 2024 Curriculum)

| Tool | Domain | Weight | Purpose |
|------|--------|--------|---------|
| **Trivy** | Supply Chain Security | 20% | Container image vulnerability scanning |
| **Kubesec** | Supply Chain Security | 20% | Static YAML security analysis |
| **KubeLinter** | Supply Chain Security | 20% | Kubernetes manifest linting |
| **kube-bench** | Cluster Setup | 15% | CIS Kubernetes Benchmark checks |
| **Falco** | Monitoring/Runtime | 20% | Runtime security monitoring |
| **Cilium** | Cluster Setup + Microservices | 15%+20% | NetworkPolicy + Pod encryption |

### Security Features Enabled

- ✓ Audit logging with sensible policy
- ✓ NodeRestriction admission plugin
- ✓ RBAC enabled
- ✓ Pod Security Admission ready
- ✓ Cilium NetworkPolicy + CiliumNetworkPolicy
- ✓ Pod-to-Pod encryption (WireGuard)

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

# === Supply Chain Security (20%) ===

# Trivy - Scan images for vulnerabilities
trivy image nginx:latest
trivy image --severity HIGH,CRITICAL nginx:latest
trivy image --ignore-unfixed nginx:latest

# Kubesec - Static analysis of YAML manifests
kubesec scan pod.yaml
kubectl get pod mypod -o yaml | kubesec scan -

# KubeLinter - Lint Kubernetes manifests
kube-linter lint deployment.yaml
kube-linter lint ./manifests/

# === Cluster Setup (15%) ===

# kube-bench - CIS benchmark
sudo kube-bench run --targets=master
sudo kube-bench run --targets=node

# Cilium - Network status and policies
cilium status
cilium connectivity test
kubectl get ciliumnetworkpolicies
kubectl get ciliumendpoints

# === Runtime Security (20%) ===

# Falco - Runtime monitoring
sudo systemctl start falco
sudo journalctl -fu falco
# Custom rules: /etc/falco/falco_rules.local.yaml
```

### Cilium Network Policies (NEW in Oct 2024)

```bash
# Standard Kubernetes NetworkPolicy (works with Cilium)
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
EOF

# CiliumNetworkPolicy (Cilium-specific, more powerful)
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-frontend
spec:
  endpointSelector:
    matchLabels:
      app: frontend
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: backend
EOF

# Check encryption status
cilium encrypt status
```

### View Audit Logs

```bash
multipass shell control
sudo tail -f /var/log/kubernetes/audit/audit.log | jq .
```

## CKS Exam Domains (October 2024)

This lab covers all six CKS domains. Here's what you can practice:

| Domain | Weight | Lab Coverage |
|--------|--------|--------------|
| **Cluster Setup** | 15% | ✓ Cilium NetworkPolicy, CIS benchmarks (kube-bench), audit logging |
| **Cluster Hardening** | 15% | ✓ RBAC, ServiceAccount security, API server hardening |
| **System Hardening** | 10% | ✓ AppArmor, seccomp (Ubuntu 24.04 ready) |
| **Minimize Microservice Vulnerabilities** | 20% | ✓ Pod Security Standards, Cilium encryption, SecurityContext |
| **Supply Chain Security** | 20% | ✓ Trivy, Kubesec, KubeLinter, image scanning |
| **Monitoring, Logging, Runtime Security** | 20% | ✓ Falco, audit logs, behavioral analytics |

### Key Exam Topics to Practice

1. **Cilium Network Policies** - Both standard K8s NetworkPolicy AND CiliumNetworkPolicy
2. **Pod-to-Pod Encryption** - WireGuard is pre-configured, practice verifying with `cilium encrypt status`
3. **Trivy Scanning** - Filter by severity, ignore unfixed, JSON output
4. **Falco Rules** - Modify `/etc/falco/falco_rules.local.yaml`, restart and verify
5. **Secrets Encryption at Rest** - Use `/etc/kubernetes/enc/` directory to practice
6. **Audit Logging** - Policy already configured, practice reading logs
7. **RBAC** - Create Roles, ClusterRoles, bindings imperatively
8. **Pod Security Standards** - Apply namespace labels for enforce/audit/warn

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

### 2. Network Policies (Standard + Cilium)

```bash
# Default deny all (standard Kubernetes NetworkPolicy)
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

# Allow specific traffic (standard)
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

# CiliumNetworkPolicy with Layer 7 filtering (exam topic)
kubectl apply -f - <<EOF
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-policy
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
  - fromEndpoints:
    - matchLabels:
        app: frontend
    toPorts:
    - ports:
      - port: "80"
        protocol: TCP
      rules:
        http:
        - method: GET
          path: "/api/.*"
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

### 7. AppArmor Profiles

```bash
# SSH to a node
multipass shell control

# Check loaded AppArmor profiles
sudo aa-status

# Create a custom AppArmor profile
sudo tee /etc/apparmor.d/k8s-deny-write <<EOF
#include <tunables/global>
profile k8s-deny-write flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /tmp/** w,
  deny /var/tmp/** w,
}
EOF

# Load the profile
sudo apparmor_parser -r /etc/apparmor.d/k8s-deny-write

# Use in a pod (K8s 1.30+)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: apparmor-pod
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-deny-write
  containers:
  - name: app
    image: busybox
    command: ["sleep", "3600"]
EOF
```

### 8. Seccomp Profiles

```bash
# Create seccomp profile directory (on node)
sudo mkdir -p /var/lib/kubelet/seccomp/profiles

# Create a custom seccomp profile
sudo tee /var/lib/kubelet/seccomp/profiles/audit.json <<EOF
{
  "defaultAction": "SCMP_ACT_LOG"
}
EOF

# Use in a pod
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-pod
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: profiles/audit.json
  containers:
  - name: app
    image: busybox
    command: ["sleep", "3600"]
EOF

# Or use RuntimeDefault (recommended)
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: seccomp-default
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx
EOF
```

### 9. Falco Rules Practice

```bash
# SSH to control plane
multipass shell control

# Edit custom Falco rules
sudo tee -a /etc/falco/falco_rules.local.yaml <<EOF
- rule: Detect Shell in Container
  desc: Alert when a shell is spawned in a container
  condition: container.id != host and proc.name in (bash, sh, zsh)
  output: "Shell spawned in container (user=%user.name container=%container.name command=%proc.cmdline)"
  priority: WARNING
EOF

# Restart Falco
sudo systemctl restart falco

# Watch Falco logs
sudo journalctl -fu falco

# In another terminal, trigger the rule
kubectl run test --image=busybox --rm -it -- sh
```

## Key Paths on Control Plane

| Path | Description |
|------|-------------|
| `/etc/kubernetes/manifests/` | Static pod manifests (API server, etcd, etc.) |
| `/etc/kubernetes/audit-policy.yaml` | Audit policy configuration |
| `/var/log/kubernetes/audit/` | Audit log files |
| `/etc/kubernetes/pki/` | Cluster certificates |
| `/etc/kubernetes/enc/` | Encryption configs (for practice) |
| `/etc/falco/falco.yaml` | Falco main configuration |
| `/etc/falco/falco_rules.yaml` | Default Falco rules (don't edit) |
| `/etc/falco/falco_rules.local.yaml` | Custom Falco rules (edit this!) |
| `/var/lib/kubelet/seccomp/` | Seccomp profiles directory |
| `/etc/apparmor.d/` | AppArmor profiles |

## Troubleshooting

### Nodes not becoming Ready

```bash
# Check kubelet status
multipass exec control -- sudo systemctl status kubelet

# Check kubelet logs
multipass exec control -- sudo journalctl -xeu kubelet

# Check Cilium status
multipass exec control -- cilium status

# Check Cilium pods
multipass exec control -- kubectl get pods -n kube-system -l app.kubernetes.io/part-of=cilium
```

### Cloud-init issues

```bash
# Check cloud-init status
multipass exec control -- cloud-init status

# Check cloud-init logs
multipass exec control -- sudo cat /var/log/cloud-init-output.log
```

### Cilium troubleshooting

```bash
# Detailed Cilium status
multipass exec control -- cilium status --verbose

# Check Cilium connectivity
multipass exec control -- cilium connectivity test

# Check encryption status
multipass exec control -- cilium encrypt status

# View Cilium logs
multipass exec control -- kubectl logs -n kube-system -l app.kubernetes.io/name=cilium-agent
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
