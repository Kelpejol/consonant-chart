# Consonant Relayer Helm Chart

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/consonant/helm-charts)
[![Type](https://img.shields.io/badge/type-application-informational)](https://helm.sh/docs/topics/charts/)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.24%2B-brightgreen.svg)](https://kubernetes.io/)

Production-grade Helm chart for deploying the Consonant Relayer - an AI agent orchestration system that connects self-hosted backends to Kubernetes clusters via secure Cloudflare tunnels, enabling real-time telemetry streaming from KAgent to web UI.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Security](#security)
- [High Availability](#high-availability)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## 🎯 Overview

### What is Consonant Relayer?

Consonant Relayer is the bridge component that:

- **Connects** Kubernetes clusters to self-hosted Consonant backends
- **Streams** real-time telemetry from AI agents (via KAgent) to your UI
- **Secures** connections using Cloudflare Tunnel or direct TLS
- **Orchestrates** multi-agent workflows across clusters

### Key Features

✅ **Production-Ready Security**
- External secrets integration (Vault, AWS, Azure, GCP)
- Network isolation with NetworkPolicy
- Read-only root filesystems
- Non-root containers
- Pod Security Standards enforcement

✅ **High Availability**
- Multi-replica deployment support
- PodDisruptionBudget for safe updates
- Automatic failover and reconnection
- Circuit breaker pattern for resilience

✅ **Enterprise Observability**
- Prometheus metrics via ServiceMonitor
- Structured JSON logging
- OpenTelemetry integration
- Health checks and readiness probes

✅ **Zero-Trust Networking**
- Cloudflare Tunnel integration (no exposed ports)
- Namespace-scoped RBAC
- Restricted network policies
- Encrypted secrets at rest

## 🏗️ Architecture
```
┌────────────────────────────────────────────────────────────────┐
│                    USER'S INFRASTRUCTURE                        │
│                                                                 │
│  ┌──────────────────┐         ┌──────────────────────────┐    │
│  │  Backend Server  │         │   Kubernetes Cluster      │    │
│  │  (Self-Hosted)   │         │                           │    │
│  │                  │         │  ┌────────────────────┐   │    │
│  │  ┌────────────┐  │         │  │   Relayer Pod      │   │    │
│  │  │  Fastify   │  │         │  │ ┌──────────────┐   │   │    │
│  │  │  Backend   │  │◄────────┼──┤ │   Relayer    │   │   │    │
│  │  │            │  │ Tunnel  │  │ │  (Main)      │   │   │    │
│  │  │ Socket.io  │  │         │  │ └──────────────┘   │   │    │
│  │  │  Server    │  │         │  │ ┌──────────────┐   │   │    │
│  │  └────────────┘  │         │  │ │ Cloudflared  │   │   │    │
│  │                  │         │  │ │  (Sidecar)   │   │   │    │
│  │  ┌────────────┐  │         │  │ └──────────────┘   │   │    │
│  │  │ PostgreSQL │  │         │  └────────────────────┘   │    │
│  │  └────────────┘  │         │           ▲               │    │
│  │                  │         │           │ OTEL          │    │
│  │  ┌────────────┐  │         │  ┌────────┴────────┐     │    │
│  │  │   Redis    │  │         │  │     KAgent      │     │    │
│  │  └────────────┘  │         │  │   (AI Agents)   │     │    │
│  └──────────────────┘         │  └─────────────────┘     │    │
│                                └──────────────────────────┘    │
└────────────────────────────────────────────────────────────────┘
                 Cloudflare Tunnel (Zero-Trust)
```

### Component Flow

1. **Pre-Install Hook** → Registers cluster with backend, creates credentials
2. **Relayer** → Connects to backend via Cloudflare Tunnel
3. **KAgent** → Sends telemetry to Relayer via OTEL (port 4317)
4. **Backend** → Receives telemetry via WebSocket, streams to UI

## 📦 Prerequisites

### Required

| Component | Version | Purpose |
|-----------|---------|---------|
| **Kubernetes** | ≥ 1.24.0 | Container orchestration |
| **Helm** | ≥ 3.8.0 | Package manager |
| **kubectl** | ≥ 1.24.0 | CLI tool |

### Backend Requirements

- **Consonant Backend** running and accessible
- **PostgreSQL** database
- **Redis** for caching
- **Domain** with Cloudflare (for tunnel)

### Optional but Recommended

| Component | Purpose |
|-----------|---------|
| **External Secrets Operator** | Secret management |
| **Prometheus Operator** | Metrics collection |
| **cert-manager** | TLS certificate management |

## 🚀 Quick Start

### 1. Add Helm Repository
```bash
helm repo add consonant https://charts.consonant.xyz
helm repo update
```

### 2. Create Cloudflare Tunnel

Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/):

1. Navigate to **Networks → Tunnels**
2. Click **Create a tunnel**
3. Choose **Cloudflared**
4. Name: `consonant-backend`
5. Copy the tunnel token (starts with `eyJ...`)

### 3. Install the Chart
```bash
# Set your configuration
export CLUSTER_NAME="production-us-east-1"
export BACKEND_URL="https://consonant.yourcompany.com"
export TUNNEL_TOKEN="eyJhIjoiY..."  # Your Cloudflare tunnel token
export LLM_API_KEY="sk-ant-..."     # Anthropic/OpenAI/Gemini key
export LLM_PROVIDER="anthropic"

# Install with Helm
helm install consonant-prod consonant/consonant-relayer \
  --create-namespace \
  --namespace consonant-system \
  --set cluster.name="${CLUSTER_NAME}" \
  --set backend.url="${BACKEND_URL}" \
  --set cloudflare.tunnelToken="${TUNNEL_TOKEN}" \
  --set llm.provider="${LLM_PROVIDER}" \
  --set llm.apiKey="${LLM_API_KEY}"
```

### 4. Verify Installation
```bash
# Watch pods start
kubectl get pods -n consonant-system -w

# Check logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer -f

# Test connection
kubectl port-forward -n consonant-system svc/consonant-prod-consonant-relayer 8080:8080
curl http://localhost:8080/health
```

**Expected output:**
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

## ⚙️ Configuration

### Essential Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `cluster.name` | Unique cluster identifier | `""` | ✅ Yes |
| `backend.url` | Backend URL (HTTPS) | `""` | ✅ Yes |
| `cloudflare.tunnelToken` | CF tunnel token | `""` | ✅ Yes* |
| `llm.apiKey` | LLM API key | `""` | ✅ Yes** |
| `llm.provider` | LLM provider | `"anthropic"` | ✅ Yes |

*Required if `cloudflare.enabled=true` (default)
**Not required if using external secrets

### Common Configuration Examples

#### Production Setup (Recommended)
```yaml
# production-values.yaml
cluster:
  name: "production-us-east-1"
  region: "us-east-1"
  environment: "production"

backend:
  url: "https://consonant.company.com"

# Use external secrets (RECOMMENDED)
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

cloudflare:
  enabled: true

llm:
  provider: "anthropic"
  model: "claude-3-5-sonnet-20241022"

# High availability
relayer:
  replicas: 3
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

# Network security
networkPolicy:
  enabled: true

# Pod disruption budget
podDisruptionBudget:
  enabled: true
  minAvailable: 2

# Monitoring
serviceMonitor:
  enabled: true
  labels:
    prometheus: kube-prometheus
```

Install:
```bash
helm install consonant-prod consonant/consonant-relayer \
  -f production-values.yaml \
  --namespace consonant-system
```

#### Development Setup
```yaml
# dev-values.yaml
cluster:
  name: "dev-local"
  environment: "development"

backend:
  url: "http://localhost:3000"

# Use Kubernetes secrets (simpler for dev)
secrets:
  mode: "kubernetes"
  kubernetes:
    llmApiKey: "sk-..."
    tunnelToken: "eyJ..."

cloudflare:
  enabled: false  # Direct connection for dev

llm:
  provider: "openai"
  model: "gpt-4o-mini"

relayer:
  replicas: 1
  logLevel: "debug"

networkPolicy:
  enabled: false

podDisruptionBudget:
  enabled: false
```

#### Multi-Cloud Setup
```yaml
# multi-cloud-values.yaml
cluster:
  name: "prod-aws-us-east-1"
  region: "us-east-1"
  metadata:
    provider: "aws"
    accountId: "123456789012"
    tags:
      cost-center: "engineering"
      team: "platform"

# AWS-specific annotations
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::ACCOUNT:role/consonant-relayer"

# Use AWS Secrets Manager
secrets:
  mode: "external"
  external:
    enabled: true
    secretStore:
      name: "aws-secrets-manager"
      kind: "SecretStore"
```

### All Configuration Options

See [values.yaml](values.yaml) for complete configuration reference.

Key sections:
- [Cluster Configuration](#cluster-configuration)
- [Backend Configuration](#backend-configuration)
- [Secret Management](#secret-management)
- [Cloudflare Tunnel](#cloudflare-tunnel)
- [LLM Configuration](#llm-configuration)
- [Resource Management](#resource-management)
- [Security Settings](#security-settings)
- [Monitoring](#monitoring-configuration)

## 🔒 Security

### Security Features

✅ **Network Isolation**
- NetworkPolicy enabled by default
- Ingress control (only KAgent → Relayer)
- Lateral movement prevention (blocks private IPs)
- Zero maintenance (wildcard egress to internet)

✅ **Secrets Management**
- External secrets support (Vault, AWS, Azure, GCP)
- Kubernetes secrets with etcd encryption
- No secrets in Helm values or Git

✅ **Network Security**
- Pod-level isolation with NetworkPolicy
- VPC-level security (Security Groups, Firewall Rules)
- Cloudflare Tunnel (no exposed ports, zero-trust)
- TLS encryption in transit
- Private cluster communication

✅ **Container Security**
- Non-root containers
- Read-only root filesystem
- Drop all capabilities
- Security context enforcement
- Image digest pinning

✅ **RBAC**
- Namespace-scoped permissions
- Separate hook and runtime accounts
- Least privilege principle
- Resource name restrictions

### NetworkPolicy Strategy

**This chart enables NetworkPolicy by default with wildcard egress.**

**What this provides:**
- ✅ **Ingress control**: Only KAgent pods can send telemetry to Relayer
- ✅ **Lateral movement prevention**: Blocks access to internal services (10.x.x.x, 192.168.x.x)
- ✅ **Zero maintenance**: No tracking of external IP ranges
- ✅ **Scalability**: Works with any LLM provider (Anthropic, OpenAI, Gemini, Azure, etc.)

**Default configuration:**
```yaml
networkPolicy:
  enabled: true
  egress:
    allowHTTPS:
      destinations: []  # Empty = allow all external HTTPS
```

**What gets blocked:**
- ❌ Unauthorized pods sending to Relayer
- ❌ Relayer reaching internal cluster services (databases, etc.)
- ❌ Relayer reaching private IP ranges (10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16)

**What gets allowed:**
- ✅ KAgent → Relayer (OTEL telemetry)
- ✅ Relayer → Backend (via Cloudflare Tunnel)
- ✅ Relayer → LLM APIs (Anthropic, OpenAI, etc.)
- ✅ DNS resolution
- ✅ Kubernetes API access

**External threat protection:**
External threats are mitigated by:
1. VPC perimeter controls (AWS Security Groups, GCP Firewall Rules)
2. Authentication (API keys, IAM roles)
3. Encryption (TLS everywhere)
4. Cloudflare Tunnel (zero-trust networking)

**When to disable:**
Disable NetworkPolicy only if:
- Your Kubernetes distribution doesn't support it (rare)
- You're using a service mesh (Istio/Linkerd) for network controls
- You have specific technical constraints
```yaml
# To disable:
networkPolicy:
  enabled: false
```

See [SECURITY.md](SECURITY.md#network-policy) for detailed documentation.

### Security Checklist

Before deploying to production:

- [ ] Enable external secrets (`secrets.mode=external`)
- [ ] Pin all image digests (not tags)
- [ ] Enable NetworkPolicy (`networkPolicy.enabled=true`)
- [ ] Use Cloudflare Tunnel (`cloudflare.enabled=true`)
- [ ] Enable etcd encryption at cluster level
- [ ] Review RBAC permissions
- [ ] Configure PodDisruptionBudget
- [ ] Set up monitoring and alerting
- [ ] Review and restrict egress rules
- [ ] Enable audit logging

See [SECURITY.md](SECURITY.md) for detailed security guide.

## 🚀 High Availability

### HA Configuration
```yaml
# HA setup
relayer:
  replicas: 3  # Minimum for production
  
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # Zero downtime

  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 100
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: consonant-relayer
          topologyKey: kubernetes.io/hostname
      - weight: 50
        podAffinityTerm:
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: consonant-relayer
          topologyKey: topology.kubernetes.io/zone

podDisruptionBudget:
  enabled: true
  minAvailable: 2  # Always keep 2 running

backend:
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
```

### Disaster Recovery

**Backup cluster credentials:**
```bash
kubectl get secret -n consonant-system \
  consonant-prod-consonant-relayer-cluster \
  -o yaml > cluster-credentials-backup.yaml
```

**Restore cluster credentials:**
```bash
kubectl apply -f cluster-credentials-backup.yaml
```

**Re-register cluster:**
```bash
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set backend.credentials.existingSecret=""
```

## 📊 Monitoring

### Prometheus Integration

Enable ServiceMonitor:
```yaml
serviceMonitor:
  enabled: true
  labels:
    prometheus: kube-prometheus
  interval: 30s
  path: /metrics
```

### Key Metrics

| Metric | Description | Alert Threshold |
|--------|-------------|-----------------|
| `relayer_backend_connected` | Backend connection status | < 1 |
| `relayer_otel_received_total` | OTEL messages received | Rate change |
| `relayer_otel_forwarded_total` | Messages forwarded | < received |
| `relayer_reconnections_total` | Reconnection attempts | > 10/hour |
| `relayer_circuit_breaker_state` | Circuit breaker state | open |

### Alerting Examples
```yaml
# PrometheusRule
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: consonant-relayer-alerts
spec:
  groups:
  - name: consonant-relayer
    interval: 30s
    rules:
    - alert: RelayerBackendDisconnected
      expr: relayer_backend_connected == 0
      for: 5m
      labels:
        severity: critical
      annotations:
        summary: "Relayer disconnected from backend"
        description: "{{ $labels.pod }} has been disconnected for 5 minutes"
    
    - alert: RelayerHighReconnectionRate
      expr: rate(relayer_reconnections_total[5m]) > 2
      for: 10m
      labels:
        severity: warning
      annotations:
        summary: "High reconnection rate detected"
```

### Logging

Logs are structured JSON:
```json
{
  "level": "info",
  "timestamp": "2025-01-03T10:15:30.123Z",
  "msg": "Backend connected",
  "clusterId": "cluster_abc123",
  "component": "relayer",
  "pod": "consonant-prod-consonant-relayer-7d8f9b-xyz"
}
```

Query logs:
```bash
# Using kubectl
kubectl logs -n consonant-system \
  -l app.kubernetes.io/name=consonant-relayer \
  --tail=100 -f | jq '.'

# Using stern (recommended)
stern -n consonant-system consonant-relayer
```

## 🔧 Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for detailed guide.

### Common Issues

**❌ Pre-install hook failed**
```bash
# Check hook logs
kubectl logs -n consonant-system job/consonant-prod-consonant-relayer-register

# Common causes:
# 1. Backend not accessible
# 2. Invalid tunnel token
# 3. Network connectivity issues
```

**❌ Relayer not connecting**
```bash
# Check relayer logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer -c relayer

# Check cloudflared sidecar
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer -c cloudflared

# Test backend connectivity
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v https://consonant.yourcompany.com/health
```

**❌ No telemetry data**
```bash
# Check KAgent logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=kagent

# Verify OTEL endpoint
kubectl get svc -n consonant-system

# Check NetworkPolicy
kubectl describe networkpolicy -n consonant-system
```

## 📚 Documentation

- [Installation Guide](INSTALLATION_GUIDE.md) - Step-by-step setup
- [Troubleshooting Guide](TROUBLESHOOTING.md) - Common issues
- [Security Guide](SECURITY.md) - Security best practices
- [Future Roadmap](FUTURE_ROADMAP.md) - Upcoming features
- [Contributing](CONTRIBUTING.md) - How to contribute
- [Publishing Guide](PUBLISHING.md) - Chart publishing

## 🤝 Contributing

We welcome contributions! See [CONTRIBUTING.md](CONTRIBUTING.md).

### Quick Links

- 🐛 [Report Bug](https://github.com/consonant/helm-charts/issues/new?template=bug_report.md)
- 💡 [Request Feature](https://github.com/consonant/helm-charts/issues/new?template=feature_request.md)
- 📖 [Documentation](https://docs.consonant.xyz)
- 💬 [Slack Community](https://consonant.xyz/slack)

## 📄 License

This chart is licensed under the Apache License 2.0. See [LICENSE](LICENSE).

## 🙏 Acknowledgments

- **KAgent Team** - For the excellent AI agent framework
- **Cloudflare** - For Zero Trust tunnels
- **External Secrets Operator** - For secret management
- **Helm Community** - For the amazing package manager

---

**Made with ❤️ by the Consonant Team**

For support: [support@consonant.xyz](mailto:support@consonant.xyz)