# Consonant Relayer Helm Chart

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/consonant/helm-charts)
[![Type](https://img.shields.io/badge/type-application-informational)](https://helm.sh/docs/topics/charts/)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.32%2B-brightgreen.svg)](https://kubernetes.io/)

# Consonant Relayer Helm Chart

[![Version](https://img.shields.io/badge/version-0.1.0--alpha.1-blue.svg)](https://github.com/consonant/helm-charts)
[![Type](https://img.shields.io/badge/type-application-informational)](https://helm.sh/docs/topics/charts/)
[![License](https://img.shields.io/badge/license-Apache%202.0-green.svg)](LICENSE)
[![Kubernetes](https://img.shields.io/badge/kubernetes-1.32%2B-brightgreen.svg)](https://kubernetes.io/)

**Production-grade Helm chart for Consonant Relayer** - A lightweight cluster-resident agent that establishes outbound gRPC connections to self-hosted Consonant backends, enabling secure AI agent orchestration without inbound cluster access.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## 🎯 Overview

### What is Consonant Relayer?

Consonant Relayer is a **cluster-resident agent** that:

- **Connects** outbound-only via gRPC to your self-hosted Consonant backend
- **Relays** commands and events between backend and cluster workloads
- **Collects** telemetry from AI agents via built-in OTEL Collector
- **Requires** no inbound firewall rules or exposed ports

### Key Features

✅ **Zero-Trust Security**
- Outbound-only gRPC connections (no inbound traffic)
- Bearer token authentication for initial registration
- Cluster credentials (id + token) for runtime
- Works behind NAT, firewalls, and air-gapped environments

✅ **Built-In Observability**
- OpenTelemetry Collector bundled by default
- Collects traces, metrics, and logs from agents
- Local buffering and processing
- Forwards to backend or external systems

✅ **Production-Ready**
- Multi-replica deployments with pod anti-affinity
- Circuit breaker pattern for backend failures
- Exponential backoff reconnection with jitter
- Comprehensive health checks and lifecycle hooks
- NetworkPolicy for pod-level isolation

✅ **Self-Hosted**
- No dependencies on external SaaS
- Complete data sovereignty
- Deploy in your infrastructure (on-prem, cloud, hybrid)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    YOUR INFRASTRUCTURE                       │
│                                                              │
│  ┌──────────────────┐         ┌──────────────────────────┐ │
│  │  Backend Server  │         │   Kubernetes Cluster      │ │
│  │  (Self-Hosted)   │         │                           │ │
│  │                  │         │  ┌────────────────────┐   │ │
│  │  ┌────────────┐  │         │  │   Relayer Pod     │   │ │
│  │  │  Fastify   │  │◄────────┼──┤                    │   │ │
│  │  │  Backend   │  │ gRPC    │  │   (Outbound only)  │   │ │
│  │  │            │  │         │  └────────────────────┘   │ │
│  │  │  gRPC      │  │         │           ▲               │ │
│  │  │  Server    │  │         │           │ OTLP          │ │
│  │  └────────────┘  │         │  ┌────────┴────────┐     │ │
│  │                  │         │  │ OTEL Collector  │     │ │
│  │  ┌────────────┐  │         │  │   (DaemonSet)   │     │ │
│  │  │ PostgreSQL │  │         │  └─────────────────┘     │ │
│  │  └────────────┘  │         │           ▲               │ │
│  └──────────────────┘         │  ┌────────┴────────┐     │ │
│                                │  │   KAgent Pods   │     │ │
│                                │  │   (AI Agents)   │     │ │
│                                │  └─────────────────┘     │ │
│                                └──────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
                   gRPC Stream (Outbound Only)
```

### How It Works

1. **Pre-Install Registration**
   - User generates secure bearer token (32-64 bytes)
   - Helm pre-install hook calls `POST /api/v1/clusters` with bearer token
   - Backend responds with `cluster_id` and `cluster_token`
   - Hook creates Kubernetes Secret with credentials
   - Bearer token is NOT stored in cluster (one-time use)

2. **Runtime Connection**
   - Relayer reads `cluster_id` and `cluster_token` from Secret
   - Establishes outbound gRPC stream to backend
   - Backend validates credentials and accepts stream
   - All communication flows over this single gRPC connection

3. **Telemetry Collection**
   - OTEL Collector runs as DaemonSet (one per node)
   - KAgent sends telemetry to local OTEL Collector (port 4317)
   - OTEL Collector buffers, processes, and forwards to backend
   - Relayer includes OTEL context in gRPC messages

## 📦 Prerequisites

### Required

| Component | Version | Purpose |
|-----------|---------|---------|
| **Kubernetes** | ≥ 1.32.0 | Container orchestration |
| **Helm** | ≥ 3.0.0 | Package manager |
| **kubectl** | ≥ 1.32.0 | CLI tool |

### Backend Requirements

- **Consonant Backend** running and accessible via HTTPS/gRPC
- **PostgreSQL** database
- Backend must expose:
  - `POST /api/v1/clusters` (registration endpoint)
  - `grpc://backend:50051` (or custom gRPC endpoint)

### Cluster Permissions

- Ability to create namespaces, deployments, services
- Ability to create and read secrets
- RBAC permissions for service accounts

## 🚀 Quick Start

### 1. Generate Bearer Token

```bash
# Generate secure 48-byte token
openssl rand -base64 48

# Example output:
# R3jK8mN2pQ5sT9vW1xY4zA6bC7dE0fF3gH5iJ8kL1mN4oP7qR0sT3uV6wX9yZ2aB
```

**Store this token securely!** You'll need it for installation.

### 2. Add Helm Repository

```bash
helm repo add consonant https://charts.consonant.xyz
helm repo update
```

### 3. Install the Chart

```bash
helm install consonant-relayer consonant/consonant-relayer \
  --create-namespace \
  --namespace consonant-system \
  --set cluster.name="production-us-east-1" \
  --set backend.url="https://backend.company.com" \
  --set auth.bearerToken="R3jK8mN2pQ5sT9vW1xY4zA6bC7dE0fF3gH5iJ8kL1mN4oP7qR0sT3uV6wX9yZ2aB"
```

### 4. Verify Installation

```bash
# Watch pods start
kubectl get pods -n consonant-system -w

# Check relayer logs
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer -f

# Check OTEL collector
kubectl logs -n consonant-system -l app.kubernetes.io/component=otel-collector -f

# Test health endpoint
kubectl port-forward -n consonant-system svc/consonant-relayer 8080:8080
curl http://localhost:8080/health
```

**Expected health response:**
```json
{
  "status": "healthy",
  "grpc": {
    "connected": true,
    "clusterId": "cls_abc123"
  },
  "version": "0.1.0-alpha.1"
}
```

## ⚙️ Configuration

### Essential Parameters

| Parameter | Description | Default | Required |
|-----------|-------------|---------|----------|
| `cluster.name` | Unique cluster identifier (DNS-1123) | `""` | ✅ Yes |
| `backend.url` | Backend URL (HTTPS) | `""` | ✅ Yes |
| `auth.bearerToken` | Pre-generated bearer token | `""` | ✅ Yes |

### Common Configurations

#### Production Setup

```yaml
# production-values.yaml
cluster:
  name: "production-us-east-1"
  region: "us-east-1"
  environment: "production"

backend:
  url: "https://backend.company.com"
  grpcEndpoint: "grpc://backend.company.com:50051"
  tlsVerify: true

auth:
  bearerToken: "YOUR_SECURE_TOKEN"  # From openssl rand -base64 48

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
            matchLabels:
              app.kubernetes.io/name: consonant-relayer
          topologyKey: kubernetes.io/hostname

# Network security
networkPolicy:
  enabled: true

# Pod disruption budget
podDisruptionBudget:
  enabled: true
  minAvailable: 2

# OTEL Collector
otelCollector:
  enabled: true
  type: "daemonset"
```

#### Development Setup

```yaml
# dev-values.yaml
cluster:
  name: "dev-local"
  environment: "development"

backend:
  url: "http://localhost:3000"
  tlsVerify: false  # OK for dev only

auth:
  bearerToken: "dev-token-not-for-production"

relayer:
  replicas: 1
  logging:
    level: "debug"

networkPolicy:
  enabled: false

podDisruptionBudget:
  enabled: false
```

Install:
```bash
helm install consonant-relayer consonant/consonant-relayer \
  -f dev-values.yaml \
  --namespace consonant-dev \
  --create-namespace
```

### All Configuration Options

See [values.yaml](values.yaml) for complete configuration reference.

## 🔒 Security

### Security Model

**Authentication Flow:**
1. **Registration** (pre-install): Bearer token → Backend returns cluster credentials
2. **Runtime**: cluster_id + cluster_token → Backend validates and accepts gRPC stream

**Network Security:**
- ✅ Outbound-only connections (no inbound traffic)
- ✅ gRPC over TLS (encrypted in transit)
- ✅ NetworkPolicy for pod-level isolation
- ✅ Blocks access to private IP ranges
- ✅ Works behind NAT/firewalls

**Secret Management:**
- ✅ Bearer token: One-time use, NOT stored in cluster
- ✅ Cluster credentials: Stored in Kubernetes Secret (encrypted at rest)
- ✅ Supports External Secrets Operator for enhanced security

### NetworkPolicy Strategy

**Enabled by default** - Provides defense-in-depth without operational burden.

**What it does:**
- ✅ Allows health checks within namespace
- ✅ Allows OTEL telemetry collection
- ✅ Allows outbound HTTPS to backend
- ✅ Blocks access to private IP ranges (lateral movement prevention)
- ✅ Allows DNS and Kubernetes API access

**What it blocks:**
- ❌ Unauthorized pods sending to relayer
- ❌ Relayer reaching internal cluster services (databases, etc.)
- ❌ Access to private IP ranges (10.x, 172.16.x, 192.168.x)

To disable (not recommended):
```yaml
networkPolicy:
  enabled: false
```

### Secrets Best Practices

**Production:**
1. Use External Secrets Operator
2. Store bearer token in vault (Vault, AWS Secrets Manager, etc.)
3. Enable etcd encryption at cluster level
4. Rotate bearer token every 90 days

**Development:**
1. Generate unique token per cluster
2. Store in password manager
3. Never commit to version control

## 🔧 Troubleshooting

### Common Issues

#### Issue: Pre-install hook failed

**Symptoms:**
```
Error: failed pre-install: job failed: BackoffLimitExceeded
```

**Check logs:**
```bash
kubectl logs -n consonant-system job/consonant-relayer-register
```

**Common causes:**
1. Backend not accessible
2. Invalid bearer token
3. Network connectivity issues
4. RBAC permissions insufficient

**Solution:**
```bash
# Test backend connectivity
curl https://backend.company.com/health

# Verify bearer token format (should be 32-64 bytes, base64)
echo "YOUR_TOKEN" | base64 -d | wc -c

# Check RBAC
kubectl auth can-i create secrets -n consonant-system
```

#### Issue: Relayer not connecting

**Symptoms:**
- Pod running but health check shows `"connected": false`
- Logs show connection errors

**Check logs:**
```bash
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer --tail=100
```

**Common causes:**
1. Backend gRPC endpoint not reachable
2. Invalid cluster credentials
3. Backend not validating credentials
4. NetworkPolicy blocking egress

**Solution:**
```bash
# Test gRPC connectivity from pod
kubectl exec -n consonant-system deployment/consonant-relayer -c relayer -- \
  sh -c "nc -zv backend.company.com 50051"

# Check cluster credentials
kubectl get secret -n consonant-system consonant-relayer-cluster \
  -o jsonpath='{.data.clusterId}' | base64 -d
echo ""
kubectl get secret -n consonant-system consonant-relayer-cluster \
  -o jsonpath='{.data.clusterToken}' | base64 -d
echo ""

# Verify backend logs show connection attempts
```

#### Issue: No telemetry data

**Symptoms:**
- OTEL Collector running but no data forwarded
- KAgent not sending telemetry

**Check:**
```bash
# Check OTEL Collector logs
kubectl logs -n consonant-system -l app.kubernetes.io/component=otel-collector

# Check OTEL Collector service
kubectl get svc -n consonant-system

# Test OTEL endpoint from KAgent pod
kubectl exec -n consonant-system deployment/kagent -- \
  sh -c "nc -zv consonant-relayer-otel 4317"
```

**Solution:**
- Verify KAgent is configured to send to correct OTEL endpoint
- Check NetworkPolicy allows KAgent → OTEL Collector traffic
- Verify OTEL Collector configuration in ConfigMap

### Getting Help

**Collect diagnostics:**
```bash
# Get all resources
kubectl get all -n consonant-system -o yaml > consonant-resources.yaml

# Get events
kubectl get events -n consonant-system --sort-by='.lastTimestamp' > consonant-events.txt

# Get logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer \
  --all-containers=true --tail=1000 > consonant-logs.txt

# Describe pods
kubectl describe pods -n consonant-system > consonant-pods.txt
```

**Contact support:**
- Email: support@consonant.xyz
- Include: diagnostics bundle, Helm chart version, Kubernetes version
- Describe: steps to reproduce, expected vs actual behavior

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution guidelines.

## 📄 License

This chart is licensed under the Apache License 2.0. See [LICENSE](LICENSE).

## 🙏 Acknowledgments

- **gRPC** - For robust RPC framework
- **OpenTelemetry** - For observability standards
- **Kubernetes Community** - For excellent tooling and documentation

---

**Made with ❤️ by the Consonant Team**

For support: support@consonant.xyz