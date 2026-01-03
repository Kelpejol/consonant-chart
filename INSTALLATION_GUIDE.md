# Consonant Relayer Installation Guide

Complete step-by-step guide for installing Consonant Relayer in production.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation Methods](#installation-methods)
- [Production Installation](#production-installation)
- [Development Installation](#development-installation)
- [Post-Installation](#post-installation)
- [Validation](#validation)
- [Next Steps](#next-steps)

## 🎯 Overview

This guide covers:
- ✅ Prerequisites and preparation
- ✅ External secrets setup (recommended)
- ✅ Cloudflare tunnel configuration
- ✅ Production-grade installation
- ✅ Validation and testing
- ✅ Troubleshooting

**Estimated time:** 30-45 minutes

## 📦 Prerequisites

### 1. Kubernetes Cluster

**Minimum requirements:**
- Kubernetes ≥ 1.24.0
- 3+ worker nodes (for HA)
- 2 CPU cores available
- 2 GB RAM available

**Verify cluster:**
```bash
kubectl version --short
kubectl get nodes
kubectl cluster-info
```

### 2. Helm

**Install Helm 3:**
```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

### 3. Backend Server

**Requirements:**
- Consonant backend running
- Accessible URL (with TLS)
- PostgreSQL database
- Redis cache

**Verify backend:**
```bash
curl https://your-backend.com/health
# Expected: {"status":"ok"}
```

### 4. Cloudflare Account

**Setup:**
1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com)
2. Add your domain
3. Enable Zero Trust (free tier works)

### 5. LLM API Key

**Supported providers:**
- Anthropic (recommended for production)
- OpenAI
- Google Gemini
- Azure OpenAI
- Ollama (self-hosted)

**Get API key:**
- Anthropic: https://console.anthropic.com/settings/keys
- OpenAI: https://platform.openai.com/api-keys
- Gemini: https://makersuite.google.com/app/apikey

## 🚀 Installation Methods

### Method 1: Production (External Secrets)

**Best for:** Production environments

**Features:**
- ✅ Secrets stored in Vault/AWS/Azure/GCP
- ✅ Automatic secret rotation
- ✅ Audit logging
- ✅ Compliance-ready

**Requirements:**
- External Secrets Operator installed
- SecretStore configured

### Method 2: Standard (Kubernetes Secrets)

**Best for:** Development, staging

**Features:**
- ✅ Simple setup
- ✅ No external dependencies
- ⚠️ Secrets in etcd (base64 encoded)

**Requirements:**
- etcd encryption enabled (recommended)

### Method 3: GitOps (ArgoCD/Flux)

**Best for:** Teams using GitOps

**Features:**
- ✅ Declarative configuration
- ✅ Version control
- ✅ Automated deployments

**Requirements:**
- ArgoCD or Flux installed

## 🏭 Production Installation

### Step 1: Install External Secrets Operator
```bash
# Add Helm repository
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

# Install operator
helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets-system \
  --create-namespace \
  --set installCRDs=true
```

### Step 2: Configure Secret Backend

**For HashiCorp Vault:**
```yaml
# vault-secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: vault-prod
spec:
  provider:
    vault:
      server: "https://vault.company.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "external-secrets"
```

Apply:
```bash
kubectl apply -f vault-secretstore.yaml
```

**For AWS Secrets Manager:**
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

### Step 3: Store Secrets in Backend

**Vault:**
```bash
# Store LLM API key
vault kv put secret/consonant/llm-key \
  apiKey="sk-ant-..."

# Store Cloudflare tunnel token
vault kv put secret/consonant/tunnel-token \
  token="eyJh..."
```

**AWS Secrets Manager:**
```bash
# Store LLM API key
aws secretsmanager create-secret \
  --name consonant/llm-key \
  --secret-string '{"apiKey":"sk-ant-..."}'

# Store tunnel token
aws secretsmanager create-secret \
  --name consonant/tunnel-token \
  --secret-string '{"token":"eyJh..."}'
```

### Step 4: Create Cloudflare Tunnel

1. Go to https://one.dash.cloudflare.com
2. Navigate to **Networks → Tunnels**
3. Click **Create a tunnel**
4. Select **Cloudflared**
5. Name: `consonant-backend-prod`
6. Click **Save tunnel**
7. **Copy the tunnel token** (starts with `eyJ`)

**Configure tunnel route:**
1. Click **Public Hostname → Add a public hostname**
2. Settings:
   - Subdomain: `consonant`
   - Domain: `yourcompany.com`
   - Service: `http://localhost:3000`
3. Click **Save**

**Test tunnel:**
```bash
curl https://consonant.yourcompany.com/health
```

### Step 5: Create Production Values File
```yaml
# production-values.yaml

###########################################
# CLUSTER CONFIGURATION
###########################################
cluster:
  name: "production-us-east-1"
  region: "us-east-1"
  environment: "production"
  metadata:
    provider: "aws"
    tags:
      team: "platform"
      cost-center: "engineering"

###########################################
# BACKEND CONFIGURATION
###########################################
backend:
  url: "https://consonant.yourcompany.com"
  
  circuitBreaker:
    enabled: true
    failureThreshold: 5
    successThreshold: 2
    timeout: 60
  
  reconnection:
    enabled: true
    delay: 1000
    maxDelay: 30000
    multiplier: 2

###########################################
# EXTERNAL SECRETS (RECOMMENDED)
###########################################
secrets:
  mode: "external"
  external:
    enabled: true
    secretStore:
      name: "vault-prod"  # or aws-secrets-manager
      kind: "ClusterSecretStore"
      validate: true
    
    refreshInterval: "1h"
    
    paths:
      llmApiKey:
        key: "secret/data/consonant/llm-key"
        property: "apiKey"
      
      tunnelToken:
        key: "secret/data/consonant/tunnel-token"
        property: "token"

###########################################
# CLOUDFLARE TUNNEL
###########################################
cloudflare:
  enabled: true
  
  tokenValidation:
    enabled: true
  
  sidecar:
    image:
      repository: cloudflare/cloudflared
      tag: "2025.1.1"
      # ✅ Use digest in production
      digest: "sha256:..."
    
    protocol: "quic"
    
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
      limits:
        cpu: 500m
        memory: 256Mi

###########################################
# LLM CONFIGURATION
###########################################
llm:
  provider: "anthropic"
  model: "claude-3-5-sonnet-20241022"
  
  fallbackModels:
    - "claude-3-opus-20240229"
    - "gpt-4o"
  
  rateLimit:
    enabled: true
    requestsPerMinute: 60
    burst: 10
  
  retry:
    maxAttempts: 3
    initialDelay: 1000
    maxDelay: 10000
    multiplier: 2

###########################################
# HIGH AVAILABILITY
###########################################
relayer:
  replicas: 3
  
  image:
    repository: ghcr.io/consonant/relayer
    tag: "1.0.0"
    # ✅ Use digest in production
    digest: "sha256:..."
  
  resources:
    requests:
      cpu: 500m
      memory: 512Mi
    limits:
      cpu: 2000m
      memory: 1Gi
  
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
              - consonant-relayer
          topologyKey: kubernetes.io/hostname
      - weight: 50
        podAffinityTerm:
          labelSelector:
            matchExpressions:
            - key: app.kubernetes.io/name
              operator: In
              values:
              - consonant-relayer
          topologyKey: topology.kubernetes.io/zone
  
  topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
    labelSelector:
      matchLabels:
        app.kubernetes.io/name: consonant-relayer

###########################################
# SECURITY
###########################################
networkPolicy:
  enabled: true
  
  egress:
    allowHTTPS:
      enabled: true
      # Restrict to specific IPs (recommended)
      destinations:
        - "52.94.133.131/32"  # Anthropic API
        - "35.244.112.0/22"   # Google APIs

podDisruptionBudget:
  enabled: true
  minAvailable: 2

###########################################
# MONITORING
###########################################
serviceMonitor:
  enabled: true
  labels:
    prometheus: kube-prometheus
  interval: 30s

###########################################
# KAGENT
###########################################
kagent:
  enabled: true
  installCRDs: true
  
  controller:
    replicas: 2
    resources:
      requests:
        cpu: 200m
        memory: 256Mi
      limits:
        cpu: 1000m
        memory: 512Mi
```

### Step 6: Install Chart
```bash
# Add Helm repository
helm repo add consonant https://charts.consonant.xyz
helm repo update

# Install
helm install consonant-prod consonant/consonant-relayer \
  --create-namespace \
  --namespace consonant-system \
  --values production-values.yaml \
  --timeout 10m \
  --wait
```

**Expected output:**
```
NAME: consonant-prod
LAST DEPLOYED: Fri Jan  3 10:15:30 2025
NAMESPACE: consonant-system
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
✅ Consonant Relayer installed successfully!
...
```

### Step 7: Verify Installation
```bash
# Check all resources
kubectl get all -n consonant-system

# Check pods
kubectl get pods -n consonant-system -w

# Expected:
# NAME                                  READY   STATUS    RESTARTS   AGE
# consonant-prod-relayer-abc123-xyz    2/2     Running   0          2m
# consonant-prod-relayer-abc123-abc    2/2     Running   0          2m
# consonant-prod-relayer-abc123-def    2/2     Running   0          2m
# kagent-controller-789xyz-abc          1/1     Running   0          2m
# kagent-controller-789xyz-def          1/1     Running   0          2m
```

## 🧪 Validation

### 1. Check Pre-Install Hooks
```bash
# Registration hook
kubectl get job -n consonant-system

# Check logs
kubectl logs -n consonant-system \
  job/consonant-prod-consonant-relayer-register
```

**Expected:**
```
============================================
  Consonant Cluster Registration
============================================
✅ Cluster registered successfully!
Cluster ID: cluster_abc123
```

### 2. Verify Cluster Credentials
```bash
kubectl get secret -n consonant-system \
  consonant-prod-consonant-relayer-cluster \
  -o yaml
```

### 3. Test Backend Connection
```bash
# Port-forward
kubectl port-forward -n consonant-system \
  svc/consonant-prod-consonant-relayer 8080:8080

# Test health (in another terminal)
curl http://localhost:8080/health
```

**Expected:**
```json
{
  "status": "ok",
  "socket": {
    "connected": true,
    "clusterId": "cluster_abc123"
  },
  "otel": {
    "port": 4317,
    "ready": true
  }
}
```

### 4. Create Test Agent
```bash
kubectl apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: test-agent
  namespace: consonant-system
spec:
  type: Declarative
  declarative:
    description: "Test agent for verification"
    modelRef:
      name: default-anthropic
EOF
```

**Check agent:**
```bash
kubectl get agents -n consonant-system test-agent
```

### 5. Verify in UI

1. Open: https://consonant.yourcompany.com
2. Navigate to **Clusters**
3. Find your cluster: `production-us-east-1`
4. Verify:
   - ✅ Status: Connected
   - ✅ Agent count: 1
   - ✅ Telemetry flowing

## 🔄 Post-Installation

### 1. Configure Monitoring
```bash
# Verify ServiceMonitor
kubectl get servicemonitor -n consonant-system

# Check Prometheus targets
# Prometheus UI → Status → Targets
# Look for: consonant-system/consonant-prod-consonant-relayer
```

### 2. Set Up Alerts
```yaml
# consonant-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: consonant-relayer-alerts
  namespace: consonant-system
spec:
  groups:
  - name: consonant
    interval: 30s
    rules:
    - alert: RelayerDown
      expr: up{job="consonant-relayer"} == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Relayer is down"
```

Apply:
```bash
kubectl apply -f consonant-alerts.yaml
```

### 3. Configure Log Aggregation

**FluentBit:**
```yaml
# fluentbit-config.yaml
[FILTER]
    Name parser
    Match kube.*consonant-system*
    Key_Name log
    Parser json

[OUTPUT]
    Name es
    Match kube.*consonant-system*
    Host elasticsearch
    Port 9200
    Index consonant
```

### 4. Document Installation
```bash
# Save configuration
helm get values consonant-prod -n consonant-system > \
  consonant-prod-values.yaml

# Save manifests
helm get manifest consonant-prod -n consonant-system > \
  consonant-prod-manifest.yaml

# Store securely (not in Git!)
```

## ✅ Next Steps

1. **Create Agents**
   - Use Consonant UI
   - Deploy via kubectl
   - Automate with CI/CD

2. **Set Up Backup**
   - Back up cluster credentials
   - Export Helm values
   - Document recovery procedures

3. **Enable Autoscaling**
```bash
   helm upgrade consonant-prod consonant/consonant-relayer \
     --reuse-values \
     --set relayer.autoscaling.enabled=true \
     --set relayer.autoscaling.minReplicas=3 \
     --set relayer.autoscaling.maxReplicas=10
```

4. **Review Security**
   - Run security scan
   - Review RBAC permissions
   - Check NetworkPolicy rules
   - Audit secret access

5. **Performance Tuning**
   - Monitor resource usage
   - Adjust replica count
   - Tune batch sizes
   - Optimize reconnection strategy

## 🐛 Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed guide.

**Quick fixes:**
```bash
# View all events
kubectl get events -n consonant-system --sort-by='.lastTimestamp'

# Check resource status
kubectl describe pod -n consonant-system -l app.kubernetes.io/name=consonant-relayer

# Restart deployment
kubectl rollout restart deployment -n consonant-system consonant-prod-consonant-relayer

# Delete and reinstall
helm uninstall consonant-prod -n consonant-system
# Fix issue
helm install consonant-prod consonant/consonant-relayer -f production-values.yaml
```

## 📚 Additional Resources

- [Configuration Reference](values.yaml)
- [Security Guide](SECURITY.md)
- [Troubleshooting Guide](TROUBLESHOOTING.md)
- [API Documentation](https://docs.consonant.xyz)

---

**Need help?** support@consonant.xyz