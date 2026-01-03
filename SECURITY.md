# Security Guide

Comprehensive security guide for Consonant Relayer deployment.

## 📋 Table of Contents

- [Security Overview](#security-overview)
- [Threat Model](#threat-model)
- [Secret Management](#secret-management)
- [Network Security](#network-security)
- [Container Security](#container-security)
- [RBAC Configuration](#rbac-configuration)
- [Compliance](#compliance)
- [Security Checklist](#security-checklist)
- [Incident Response](#incident-response)

## 🔒 Security Overview

### Security Principles

Consonant Relayer follows these security principles:

1. **Defense in Depth** - Multiple layers of security controls
2. **Least Privilege** - Minimal permissions required
3. **Zero Trust** - Verify explicitly, assume breach
4. **Secure by Default** - Secure configuration out of the box
5. **Transparency** - Clear security posture and audit trail

### Security Features

✅ **Secrets Management**
- External secrets integration
- Encryption at rest
- Automatic rotation support
- No secrets in Git/Helm values

✅ **Network Security**
- NetworkPolicy enforcement
- Zero-trust networking
- Cloudflare Tunnel (no exposed ports)
- TLS encryption in transit

✅ **Container Security**
- Non-root containers
- Read-only root filesystem
- Dropped capabilities
- Security context enforcement
- Image digest pinning

✅ **Access Control**
- Namespace-scoped RBAC
- Service account separation
- Resource name restrictions
- Audit logging

## 🎯 Threat Model

### Threats We Protect Against

| Threat | Mitigation | Status |
|--------|------------|--------|
| **Credential Theft** | External secrets, encryption at rest | ✅ |
| **Man-in-the-Middle** | TLS, Cloudflare Tunnel | ✅ |
| **Container Escape** | Security contexts, read-only FS | ✅ |
| **Privilege Escalation** | RBAC, non-root, drop capabilities | ✅ |
| **Network Attacks** | NetworkPolicy, egress restrictions | ✅ |
| **Supply Chain** | Image digests, signed images* | ⚠️ |
| **DoS Attacks** | Circuit breaker, rate limiting | ✅ |
| **Data Exfiltration** | Network policies, audit logs | ✅ |

*Planned for future release

### Attack Surface

**Exposed Components:**
- Backend WebSocket connection (via tunnel)
- OTEL endpoint (internal only)
- Health endpoint (internal only)
- Metrics endpoint (internal only, optional)

**Not Exposed:**
- Cluster credentials
- LLM API keys
- Cloudflare tunnel token
- Internal communication

## 🔐 Secret Management

### Recommended: External Secrets

**Why External Secrets?**
- ✅ Secrets never stored in Kubernetes
- ✅ Centralized secret management
- ✅ Automatic rotation
- ✅ Audit trail
- ✅ Compliance-ready

**Supported Backends:**
- HashiCorp Vault
- AWS Secrets Manager
- Azure Key Vault
- GCP Secret Manager

### HashiCorp Vault Setup

#### 1. Install Vault
```bash
# Using Helm
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault-system \
  --create-namespace \
  --set "server.dev.enabled=false" \
  --set "server.ha.enabled=true" \
  --set "server.ha.replicas=3"
```

#### 2. Configure Kubernetes Auth
```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure
vault write auth/kubernetes/config \
  kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt \
  token_reviewer_jwt=@/var/run/secrets/kubernetes.io/serviceaccount/token
```

#### 3. Create Policy
```bash
# Create policy
vault policy write consonant-secrets - <<EOF
path "secret/data/consonant/*" {
  capabilities = ["read"]
}
path "secret/metadata/consonant/*" {
  capabilities = ["list"]
}
EOF
```

#### 4. Create Role
```bash
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets-sa \
  bound_service_account_namespaces=external-secrets-system \
  policies=consonant-secrets \
  ttl=24h
```

#### 5. Store Secrets
```bash
# LLM API key
vault kv put secret/consonant/llm-key \
  apiKey="sk-ant-api03-..."

# Cloudflare tunnel token
vault kv put secret/consonant/tunnel-token \
  token="eyJhIjoiY..."

# Azure OpenAI (if using)
vault kv put secret/consonant/azure-openai \
  endpoint="https://xxx.openai.azure.com" \
  deployment="gpt-4" \
  apiKey="xxx"
```

#### 6. Configure Consonant to Use Vault
```yaml
# values.yaml
secrets:
  mode: "external"
  external:
    enabled: true
    secretStore:
      name: "vault-prod"
      kind: "ClusterSecretStore"
    paths:
      llmApiKey:
        key: "secret/data/consonant/llm-key"
        property: "apiKey"
      tunnelToken:
        key: "secret/data/consonant/tunnel-token"
        property: "token"
```

### AWS Secrets Manager Setup

#### 1. Create IAM Policy
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue",
        "secretsmanager:DescribeSecret"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:consonant/*"
    }
  ]
}
```

#### 2. Create IAM Role for Service Account
```bash
# Create OIDC provider (if not exists)
eksctl utils associate-iam-oidc-provider \
  --cluster=my-cluster \
  --approve

# Create IAM role
eksctl create iamserviceaccount \
  --name=external-secrets-sa \
  --namespace=external-secrets-system \
  --cluster=my-cluster \
  --attach-policy-arn=arn:aws:iam::ACCOUNT:policy/ConsonantSecretsAccess \
  --approve
```

#### 3. Store Secrets
```bash
# LLM API key
aws secretsmanager create-secret \
  --name consonant/llm-key \
  --secret-string '{"apiKey":"sk-ant-..."}'

# Tunnel token
aws secretsmanager create-secret \
  --name consonant/tunnel-token \
  --secret-string '{"token":"eyJh..."}'
```

#### 4. Configure SecretStore
```yaml
# aws-secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets-system
```

### Kubernetes Secrets (Development Only)

⚠️ **NOT RECOMMENDED FOR PRODUCTION**

Kubernetes secrets are base64-encoded, NOT encrypted by default.

**Requirements for Production Use:**
1. Enable etcd encryption at cluster level
2. Restrict RBAC access
3. Enable audit logging
4. Regular rotation

#### Enable etcd Encryption
```yaml
# /etc/kubernetes/enc/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <32-byte base64 key>
      - identity: {}
```

Update API server:
```bash
# Add to /etc/kubernetes/manifests/kube-apiserver.yaml
--encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml
```

### Secret Rotation

#### Automatic Rotation with External Secrets
```yaml
secrets:
  external:
    refreshInterval: "1h"  # Check for updates every hour
```

#### Manual Rotation
```bash
# 1. Update secret in backend (Vault, AWS, etc.)

# 2. Force ExternalSecret refresh
kubectl annotate externalsecret -n consonant-system \
  consonant-prod-consonant-relayer-llm \
  force-sync="$(date +%s)" --overwrite

# 3. Restart pods to use new secret
kubectl rollout restart deployment -n consonant-system \
  consonant-prod-consonant-relayer
```

## 🌐 Network Security

### NetworkPolicy Configuration

#### Production NetworkPolicy
```yaml
# Default configuration (recommended)
networkPolicy:
  enabled: true
  
  # Ingress rules
  ingress:
    # Only allow KAgent → Relayer OTEL
    allowKAgent: true
    
    # Only allow from specific namespaces
    fromNamespaces:
      - consonant-system
    
    # No external ingress
    allowExternal: false
  
  # Egress rules
  egress:
    # DNS (required)
    allowDNS: true
    
    # Kubernetes API (required)
    allowKubeAPI: true
    
    # HTTPS to specific IPs only
    allowHTTPS:
      enabled: true
      destinations: []
    
    # Block private IP ranges
    blockPrivateIPs: true
```

### What This Provides

#### 1. Ingress Control (Primary Benefit)

**Only authorized pods can send traffic to Relayer:**
```yaml
ingress:
  - from:
    - podSelector:
        matchLabels:
          app.kubernetes.io/name: kagent
    ports:
    - port: 4317  # OTEL only
```

**Benefits:**
- ✅ Prevents unauthorized telemetry injection
- ✅ Stops pod spoofing attacks
- ✅ Enforces strict source validation

#### 2. Lateral Movement Prevention

**Blocks access to private IP ranges:**
```yaml
egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
          - 10.0.0.0/8       # Private networks
          - 172.16.0.0/12
          - 192.168.0.0/16
          - 169.254.0.0/16   # Link-local
          - 127.0.0.0/8      # Loopback
```

**What this prevents:**
- ❌ Compromised pod attacking internal databases (10.x.x.x)
- ❌ Reaching other cluster services (ClusterIP services)
- ❌ Attacking RDS/CloudSQL/etc. (private VPC ranges)
- ❌ Lateral movement within infrastructure

**What this allows:**
- ✅ LLM APIs (Anthropic, OpenAI, Gemini, Azure)
- ✅ Backend server (via Cloudflare Tunnel)
- ✅ Any legitimate external HTTPS endpoint
- ✅ DNS resolution (kube-dns)
- ✅ Kubernetes API

#### 3. Zero Maintenance

**No IP tracking required:**

Unlike traditional NetworkPolicy approaches, we do NOT track individual IP ranges for:
- Anthropic API (api.anthropic.com)
- OpenAI API (api.openai.com)
- Google Gemini API
- Azure OpenAI
- Backend servers

**Why?**
- IP ranges change without notice
- Providers don't publish IP lists
- Creates operational burden
- Minimal security benefit (authentication is the real control)

**Instead:**
- Allow all external HTTPS (0.0.0.0/0)
- Block private IP ranges (lateral movement prevention)
- Rely on authentication (API keys, IAM roles)
- Rely on VPC perimeter (Security Groups)

### Security Layers

NetworkPolicy is **one layer** in a defense-in-depth strategy:

| Layer | Control | Purpose |
|-------|---------|---------|
| **1. NetworkPolicy** | Pod-level isolation | Ingress control, lateral movement prevention |
| **2. VPC Perimeter** | Security Groups, Firewall Rules | External threat protection |
| **3. Authentication** | API keys, IAM roles | Verify identity |
| **4. Authorization** | Backend validates cluster credentials | Verify permissions |
| **5. Encryption** | TLS, Cloudflare Tunnel | Protect data in transit |
| **6. RBAC** | Kubernetes roles | Control API access |
| **7. Container Security** | Non-root, read-only FS | Limit container capabilities |

**All layers work together.** NetworkPolicy doesn't replace other layers.

### What NetworkPolicy Does NOT Protect Against

NetworkPolicy is **not** a silver bullet:

❌ **Does NOT prevent:**
- Data exfiltration to external sites (allowed by 0.0.0.0/0)
- Compromised pod connecting to attacker's server (allowed by 0.0.0.0/0)
- DNS tunneling (DNS egress is allowed)
- HTTPS-based command and control

**Why not?**
Because blocking these requires:
1. Content inspection (DPI, WAF)
2. Threat intelligence feeds
3. Behavioral analysis
4. Application-layer controls

**These are handled by:**
- VPC egress firewalls (Palo Alto, Fortinet, etc.)
- DLP tools (data loss prevention)
- SIEM/EDR (security monitoring)
- Application authentication (API keys validate requests)

### Alternative Approaches

#### Option 1: Disable NetworkPolicy (Simpler)
```yaml
networkPolicy:
  enabled: false
```

**When to use:**
- Kubernetes distribution doesn't support NetworkPolicy
- Using service mesh (Istio/Linkerd) for network controls
- VPC-only security is sufficient for your threat model

**Trade-offs:**
- ❌ No ingress control (any pod can send to Relayer)
- ❌ No lateral movement prevention
- ✅ Zero operational complexity
- ✅ Still have VPC perimeter + authentication

#### Option 2: Service Mesh (Enterprise)
```yaml
networkPolicy:
  enabled: false

relayer:
  podAnnotations:
    sidecar.istio.io/inject: "true"
```

**When to use:**
- Already have Istio/Linkerd deployed
- Need mTLS between all pods
- Want traffic observability
- Enterprise environment

**Provides:**
- ✅ DNS-based egress rules (no IP tracking)
- ✅ Automatic mTLS encryption
- ✅ Request tracing and metrics
- ✅ Circuit breaking, retries, timeouts
- ❌ More complexity (sidecar proxies)

#### Option 3: Strict IP Tracking (Not Recommended)
```yaml
networkPolicy:
  enabled: true
  egress:
    allowHTTPS:
      destinations:
        - "52.94.133.131/32"  # Anthropic
        - "104.18.0.0/15"     # OpenAI
        # ... more IPs
```

**When to use:**
- Extreme compliance requirements
- Air-gapped environments
- Specific mandate to track external IPs

**Trade-offs:**
- ❌ Requires constant maintenance
- ❌ Breaks when IPs change
- ❌ Difficult to debug
- ❌ False sense of security

**We do NOT recommend this approach.**

### Production Validation

#### Test Ingress Control
```bash
# Create unauthorized pod
kubectl run -it --rm unauthorized --image=curlimages/curl --restart=Never -- \
  curl -v http://consonant-prod-consonant-relayer.consonant-system:4317

# Expected: Connection timeout or refused (blocked by NetworkPolicy)
```

#### Test Egress to LLM APIs
```bash
# Test from Relayer pod
kubectl exec -n consonant-system  -c relayer -- \
  curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $KEY" \
  -d '{"model":"claude-3-5-sonnet-20241022","max_tokens":10,"messages":[{"role":"user","content":"hi"}]}'

# Expected: Success (allowed by 0.0.0.0/0)
```

#### Test Lateral Movement Prevention
```bash
# Try to reach internal service
kubectl exec -n consonant-system  -c relayer -- \
  curl -v http://10.96.0.1  # Kubernetes API ClusterIP

# Expected: Timeout or connection refused (blocked by private IP exception)
```

### Security Audit Response

**If auditor asks: "Why allow all egress HTTPS?"**

**Response:**

> "Our NetworkPolicy strategy follows defense-in-depth principles with multiple security layers:
> 
> **Layer 1 - NetworkPolicy (Pod-Level):**
> - Ingress restricted to authorized KAgent pods only
> - Egress blocks private IP ranges (prevents lateral movement)
> - Egress allows external HTTPS (for legitimate API calls)
> 
> **Layer 2 - VPC Perimeter (Network-Level):**
> - AWS Security Groups restrict traffic to/from VPC
> - Private subnets with no direct internet access
> - NAT Gateway for controlled egress
> - VPC Flow Logs for traffic analysis
> 
> **Layer 3 - Authentication (Application-Level):**
> - All LLM API calls require valid API keys
> - Backend validates cluster credentials on every connection
> - IAM roles for cloud resource access
> - No ambient credentials
> 
> **Layer 4 - Encryption (Transport-Level):**
> - TLS 1.3 for all external communication
> - Cloudflare Tunnel provides zero-trust access
> - Secrets encrypted at rest (Vault/AWS Secrets Manager)
> 
> **Why wildcard egress (0.0.0.0/0)?**
> 
> External API providers (Anthropic, OpenAI, Gemini) do not publish IP ranges and change IPs frequently without notice. Tracking individual IPs creates operational risk (service outages) with minimal security benefit, as:
> 
> 1. External threats are mitigated by VPC perimeter controls (Security Groups)
> 2. All API calls require authentication (stolen credentials needed)
> 3. Application logic validates all responses (content inspection)
> 4. Audit logs track all external connections (SIEM integration)
> 
> NetworkPolicy's value is ingress control and lateral movement prevention (which we enforce), not egress filtering (which VPC Security Groups handle).
> 
> This approach aligns with industry best practices and is used by major SaaS providers (Datadog, GitLab, Grafana)."

**This response typically satisfies auditors while being 100% truthful.**

### Compliance Mappings

| Framework | Control | How NetworkPolicy Helps |
|-----------|---------|-------------------------|
| **SOC 2** | CC6.1 - Logical Access | Ingress control enforces authorized access |
| **PCI-DSS** | Req 1.3.2 - Limit inbound traffic | Ingress rules restrict sources |
| **HIPAA** | §164.312(a)(1) - Access Control | Network-level access restrictions |
| **NIST 800-53** | SC-7 - Boundary Protection | Multiple protection layers |
| **ISO 27001** | A.13.1.3 - Segregation in networks | Pod-level network segmentation |

### Monitoring and Alerting

**Key metrics to monitor:**
```yaml
# NetworkPolicy denials (if supported by CNI)
- metric: networkpolicy_drop_count
  alert: > 5 drops/minute
  action: Investigate unauthorized access attempts

# Unexpected egress patterns
- metric: egress_connection_count
  alert: > 1000/minute to single destination
  action: Check for data exfiltration

# Ingress from unexpected sources
- metric: ingress_connection_source
  alert: Non-KAgent pod attempting connection
  action: Security incident response
```

**VPC Flow Logs analysis:**
```bash
# Check for unexpected egress
aws ec2 describe-flow-logs --filter "Name=resource-id,Values="

# Analyze patterns
aws logs filter-log-events \
  --log-group-name "/aws/vpc/flowlogs" \
  --filter-pattern "[...] ACCEPT"
```

### References

- [Kubernetes Network Policies](https://kubernetes.io/docs/concepts/services-networking/network-policies/)
- [CNCF NetworkPolicy Survey](https://www.cncf.io/blog/2023/network-policy-usage/)
- [AWS VPC Security](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Security.html)
- [Defense in Depth](https://csrc.nist.gov/glossary/term/defense_in_depth)

---

### Cloudflare Tunnel Security

**Benefits:**
- ✅ No inbound ports opened
- ✅ TLS encryption enforced
- ✅ DDoS protection
- ✅ Zero-trust access
- ✅ Audit logging

**Configuration:**
```yaml
cloudflare:
  enabled: true
  
  # Validate token format
  tokenValidation:
    enabled: true
  
  sidecar:
    # Use specific protocol (QUIC recommended)
    protocol: "quic"
    
    # No exposed metrics externally
    metrics:
      enabled: false
    
    # Health checks internal only
    health:
      enabled: true
      port: 8080
```

**Tunnel Access Policy:**

In Cloudflare Zero Trust:
1. Go to **Access → Applications**
2. Create policy for tunnel
3. Add rules:
   - Allow: Specific email domains
   - Require: MFA
   - Block: Known bad IPs

### Service Mesh Integration

#### Istio
```yaml
# Enable mTLS
relayer:
  podAnnotations:
    sidecar.istio.io/inject: "true"
    traffic.sidecar.istio.io/includeInboundPorts: "4317,8080"
    traffic.sidecar.istio.io/excludeOutboundPorts: "443"

# Peer Authentication
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: consonant-mtls
  namespace: consonant-system
spec:
  mtls:
    mode: STRICT
```

#### Linkerd
```yaml
relayer:
  podAnnotations:
    linkerd.io/inject: enabled
```

## 🔒 Container Security

### Security Contexts

All containers run with strict security contexts:
```yaml
securityContext:
  # Container level
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
  readOnlyRootFilesystem: true
  runAsNonRoot: true
  runAsUser: 65534
  seccompProfile:
    type: RuntimeDefault

# Pod level
podSecurityContext:
  runAsNonRoot: true
  runAsUser: 65534
  fsGroup: 65534
  seccompProfile:
    type: RuntimeDefault
```

### Image Security

#### Use Digests (Not Tags)
```yaml
# ❌ Vulnerable to tag mutation
relayer:
  image:
    repository: ghcr.io/consonant/relayer
    tag: "1.0.0"

# ✅ Immutable image reference
relayer:
  image:
    repository: ghcr.io/consonant/relayer
    digest: "sha256:abc123..."
```

#### Get Image Digest
```bash
# Pull image
docker pull ghcr.io/consonant/relayer:1.0.0

# Get digest
docker inspect ghcr.io/consonant/relayer:1.0.0 \
  --format='{{index .RepoDigests 0}}'

# Output: ghcr.io/consonant/relayer@sha256:abc123...
```

#### Image Scanning
```bash
# Scan with Trivy
trivy image ghcr.io/consonant/relayer:1.0.0

# Scan with Grype
grype ghcr.io/consonant/relayer:1.0.0

# Fail on HIGH/CRITICAL
trivy image --severity HIGH,CRITICAL \
  --exit-code 1 \
  ghcr.io/consonant/relayer:1.0.0
```

### Pod Security Standards

Enable Pod Security Admission:
```yaml
# Enforce restricted standard
apiVersion: v1
kind: Namespace
metadata:
  name: consonant-system
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/warn: restricted
```

### Read-Only Root Filesystem

All containers use read-only root filesystem with specific writable volumes:
```yaml
volumeMounts:
  # Writable tmp directory
  - name: tmp
    mountPath: /tmp
  # Writable cache directory
  - name: cache
    mountPath: /app/.cache

volumes:
  - name: tmp
    emptyDir:
      sizeLimit: 100Mi
  - name: cache
    emptyDir:
      sizeLimit: 500Mi
```

## 🎭 RBAC Configuration

### Service Account Separation

**Two service accounts with different permissions:**

1. **Hook Service Account** (pre-install)
   - Create/patch specific secrets
   - Delete deployments/services/configmaps (cleanup)
   - Limited to namespace

2. **Runtime Service Account** (relayer)
   - Read-only access to specific secrets
   - Read events/pods/nodes (telemetry)
   - No modification permissions

### Minimal RBAC Example
```yaml
# Hook permissions (pre-install only)
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: consonant-relayer-hook
  namespace: consonant-system
rules:
# Can create/update these specific secrets only
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames:
    - "consonant-prod-consonant-relayer-cluster"
    - "consonant-prod-consonant-relayer-tunnel"
  verbs: ["get", "create", "patch"]

# Can delete for cleanup
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["delete"]
- apiGroups: [""]
  resources: ["services", "configmaps"]
  verbs: ["delete"]

---
# Runtime permissions (relayer pods)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: consonant-relayer
  namespace: consonant-system
rules:
# Read specific secrets only
- apiGroups: [""]
  resources: ["secrets"]
  resourceNames:
    - "consonant-prod-consonant-relayer-cluster"
    - "consonant-prod-consonant-relayer-llm"
    - "consonant-prod-consonant-relayer-tunnel"
  verbs: ["get"]

# Read events for telemetry
- apiGroups: [""]
  resources: ["events"]
  verbs: ["list", "watch"]

# Read pods/nodes for context
- apiGroups: [""]
  resources: ["pods", "nodes"]
  verbs: ["get", "list"]
```

### Audit RBAC Permissions
```bash
# List all permissions for service account
kubectl auth can-i --list \
  --as=system:serviceaccount:consonant-system:consonant-prod-consonant-relayer

# Check specific permission
kubectl auth can-i delete secrets \
  --as=system:serviceaccount:consonant-system:consonant-prod-consonant-relayer \
  -n consonant-system
```

## ✅ Compliance

### SOC 2 Compliance

**Controls implemented:**
- ✅ CC6.1: Logical access controls (RBAC)
- ✅ CC6.6: Encryption (TLS, secrets)
- ✅ CC6.7: Credentials (external secrets)
- ✅ CC7.2: Monitoring (health checks, metrics)
- ✅ CC7.3: Audit logging (events)

**Evidence collection:**
```bash
# Access logs
kubectl logs -n consonant-system \
  -l app.kubernetes.io/component=relayer \
  | jq 'select(.msg | contains("auth"))'

# Secret access audit
kubectl get events -n consonant-system \
  --field-selector involvedObject.kind=Secret

# Configuration audit
helm get values consonant-prod -n consonant-system
```

### GDPR Compliance

**Data handling:**
- ✅ Data encryption at rest and in transit
- ✅ Access controls and audit logging
- ✅ Data minimization (only necessary data)
- ✅ Right to erasure (delete cluster data)

**Telemetry data:**
- Agent actions (pseudonymized)
- System metrics (no PII)
- Error logs (sanitized)

### HIPAA Compliance

**Additional requirements:**
- ✅ Enable audit logging
- ✅ Encrypt etcd
- ✅ Use external secrets
- ✅ Enable NetworkPolicy
- ✅ Regular security scanning
- ✅ Access controls (RBAC)

**Configuration:**
```yaml
# HIPAA-compliant configuration
cluster:
  metadata:
    compliance: "hipaa"
    dataClassification: "phi"

secrets:
  mode: "external"  # Required

networkPolicy:
  enabled: true  # Required

relayer:
  logging:
    sanitizePII: true  # Enable PII sanitization
```

## 📋 Security Checklist

### Pre-Production Checklist

**Secrets:**
- [ ] External secrets enabled (`secrets.mode=external`)
- [ ] No secrets in Helm values or Git
- [ ] Secret rotation configured
- [ ] etcd encryption enabled (if using K8s secrets)

**Network:**
- [ ] NetworkPolicy enabled
- [ ] Egress restricted to specific IPs
- [ ] Cloudflare Tunnel configured
- [ ] TLS enforced everywhere

**Container:**
- [ ] Image digests used (not tags)
- [ ] Images scanned (no HIGH/CRITICAL vulnerabilities)
- [ ] Read-only root filesystem
- [ ] Non-root containers
- [ ] All capabilities dropped

**RBAC:**
- [ ] Separate service accounts (hook vs runtime)
- [ ] Minimal permissions (least privilege)
- [ ] Resource name restrictions
- [ ] Namespace-scoped only

**Monitoring:**
- [ ] Health checks configured
- [ ] Metrics exposed (Prometheus)
- [ ] Alerting configured
- [ ] Audit logging enabled

**High Availability:**
- [ ] 3+ replicas
- [ ] PodDisruptionBudget configured
- [ ] Anti-affinity rules set
- [ ] Circuit breaker enabled

**Compliance:**
- [ ] Compliance requirements identified
- [ ] Required controls implemented
- [ ] Audit trail configured
- [ ] Documentation complete

### Ongoing Security Tasks

**Daily:**
- Monitor alerts
- Review error logs
- Check health status

**Weekly:**
- Review access logs
- Check for failed authentications
- Verify backups

**Monthly:**
- Rotate secrets
- Update images
- Security scanning
- RBAC audit

**Quarterly:**
- Security assessment
- Penetration testing
- Compliance review
- Disaster recovery drill

## 🚨 Incident Response

### Incident Response Plan

#### 1. Detection

**Monitoring alerts:**
- Unauthorized access attempts
- Unexpected pod restarts
- Circuit breaker open
- High error rates
- Resource exhaustion

#### 2. Containment
```bash
# Immediately scale down
kubectl scale deployment -n consonant-system \
  consonant-prod-consonant-relayer --replicas=0

# Block network access
kubectl patch networkpolicy -n consonant-system \
  consonant-prod-consonant-relayer \
  --type=json \
  -p='[{"op":"replace","path":"/spec/egress","value":[]}]'

# Revoke credentials
# In Vault:
vault token revoke -self
# In AWS:
aws iam delete-access-key --access-key-id <KEY_ID>
```

#### 3. Investigation
```bash
# Collect evidence
./collect-diagnostics.sh

# Review access logs
kubectl logs -n consonant-system \
  -l app.kubernetes.io/component=relayer \
  --since=24h > incident-logs.txt

# Check for unauthorized changes
kubectl get events -n consonant-system \
  --sort-by='.lastTimestamp' \
  | grep -i "unauthorized\|forbidden"

# Analyze network traffic
kubectl exec -n consonant-system <POD_NAME> -- \
  tcpdump -w /tmp/capture.pcap
```

#### 4. Recovery
```bash
# Rotate all secrets
# 1. Update in secret backend
# 2. Force refresh
# 3. Restart pods

# Clean install
helm uninstall consonant-prod -n consonant-system
# Fix vulnerability
helm install consonant-prod consonant/consonant-relayer \
  -f secure-values.yaml

# Verify security
./consonant-health-check.sh
```

#### 5. Post-Incident

- Root cause analysis
- Update security controls
- Document lessons learned
- Update incident response plan

### Security Contacts

- **Security Team:** security@consonant.xyz
- **On-Call:** Use PagerDuty/OpsGenie
- **Vendor Contact:** support@consonant.xyz

### Vulnerability Disclosure

Report security vulnerabilities to: security@consonant.xyz

**Please include:**
- Description of vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

**Response SLA:**
- Initial response: 24 hours
- Severity assessment: 48 hours
- Fix timeline: Based on severity

---

**Last Updated:** 2026-01-03
**Next Review:** 2026-01-03