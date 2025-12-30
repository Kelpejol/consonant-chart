# Consonant Complete Installation Guide

## Overview

This guide shows you how to install Consonant with minimal setup - no manual tunnel configuration needed!

## System Architecture

```
┌────────────────────────────────────────────────────────────┐
│                    USER'S INFRASTRUCTURE                    │
│                                                             │
│  ┌────────────────────┐         ┌───────────────────────┐ │
│  │   Backend Server   │         │   Kubernetes Cluster   │ │
│  │   (Self-Hosted)    │         │                        │ │
│  │                    │         │  ┌─────────────────┐  │ │
│  │  ┌──────────────┐  │         │  │   Relayer      │  │ │
│  │  │  Fastify     │  │         │  │ + Cloudflared   │  │ │
│  │  │  Backend     │  │◄────────┼──┤  (Helm Chart)   │  │ │
│  │  │              │  │ Tunnel  │  │                 │  │ │
│  │  │  Socket.io   │  │         │  │  Watches:       │  │ │
│  │  │  Server      │  │         │  │  • KAgent       │  │ │
│  │  └──────────────┘  │         │  │  • Pods         │  │ │
│  │                    │         │  │  • Events       │  │ │
│  │  ┌──────────────┐  │         │  └─────────────────┘  │ │
│  │  │  PostgreSQL  │  │         │           ▲            │ │
│  │  └──────────────┘  │         │           │ OTEL       │ │
│  │                    │         │  ┌────────┴─────────┐  │ │
│  │  ┌──────────────┐  │         │  │     KAgent       │  │ │
│  │  │    Redis     │  │         │  │  (Bundled with   │  │ │
│  │  └──────────────┘  │         │  │   this chart)    │  │ │
│  └────────────────────┘         │  └──────────────────┘  │ │
│                                  └───────────────────────┘ │
└────────────────────────────────────────────────────────────┘
                   Cloudflare Tunnel (Secure)
```

## Prerequisites Checklist

### ✅ Backend Server Requirements

- [ ] Backend Server (your self-hosted Consonant backend)


### ✅ Kubernetes Cluster Requirements

- [ ] Kubernetes 1.24 or higher
- [ ] `kubectl` configured and working
- [ ] Helm 3.8 or higher installed
- [ ] Cluster has internet access (to pull images)

### ✅ Cloudflare Requirements

- [ ] Cloudflare account (free tier works)
- [ ] Domain added to Cloudflare DNS
- [ ] Zero Trust enabled in Cloudflare dashboard

### ✅ API Keys

- [ ] LLM API key (OpenAI, Anthropic, or Gemini)

---

## Part 1: Backend Setup

### Step 1.1: Install and Start Backend

```bash
# Clone repository (or use your own backend)
git clone https://github.com/yourorg/consonant-backend
cd consonant-backend

# Install dependencies
npm install

# Configure environment
cp .env.example .env
nano .env
```

**Required `.env` variables:**

```bash
NODE_ENV=production
PORT=3000
HOST=0.0.0.0

# Database
DATABASE_URL=postgresql://user:password@localhost:5432/consonant

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379

# CORS (important for frontend)
CORS_ORIGIN=https://your-frontend-domain.com
```

```bash
# Run database migrations
npx prisma migrate deploy

# Start backend (production mode with PM2)
npm install -g pm2
pm2 start npm --name consonant-backend -- start
pm2 save
pm2 startup  # Follow instructions to enable on boot
```

### Step 1.2: Verify Backend is Running

```bash
# Check if backend is accessible
curl http://localhost:3000/health

# Expected response:
# {"status":"ok","timestamp":"..."}
```

---

````md
## Part 2: Cloudflare Tunnel (2 Steps!)

### Step 1: Create Tunnel in Cloudflare Dashboard

Go to Cloudflare Zero Trust Dashboard  
Navigate to Networks → Tunnels  
Click Create a tunnel  
Choose Cloudflared  
Name it: consonant-backend  
Click Save tunnel  
Copy the tunnel token (looks like eyJhIjoiY...) - that's all you need
---

## Part 3: Kubernetes Installation (One Command!)

Now install everything into your Kubernetes cluster:

```bash
# Set your values
export CLUSTER_NAME="production-us-east"
export BACKEND_URL="https://consonant.yourcompany.com"
export TUNNEL_TOKEN="eyJhIjoiY..."  # Token from Step 2.1
export LLM_API_KEY="sk-..."  # Your OpenAI/Anthropic/Gemini key
export LLM_PROVIDER="openai"  # Options: openai, anthropic, gemini

# Install with Helm
helm install consonant-prod oci://ghcr.io/consonant/charts/consonant-relayer \
  --version 1.0.0 \
  --create-namespace \
  --namespace consonant-system \
  --set cluster.name=${CLUSTER_NAME} \
  --set backend.url=${BACKEND_URL} \
  --set cloudflare.tunnelToken=${TUNNEL_TOKEN} \
  --set llm.provider=${LLM_PROVIDER} \
  --set llm.apiKey=${LLM_API_KEY}
```

That's it! The chart:

Registers your cluster with the backend
Installs the relayer (with Cloudflare tunnel sidecar)
Installs KAgent (minimal config, no UI)
Connects everything together

### Monitor Installation

```bash
# Watch pods start
kubectl get pods -n consonant-system -w

# Check logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer -f
```

Expected output:

✅ Cluster registered: cluster_abc123
✅ Connected to backend: [https://consonant.yourcompany.com](https://consonant.yourcompany.com)
✅ OTEL receiver ready on :4317
✅ Tunnel established

### Verify Everything Works

```bash
# Port-forward to health endpoint
kubectl port-forward -n consonant-system svc/consonant-prod-consonant-relayer 8080:8080

# Check health (in another terminal)
curl http://localhost:8080/health
```

Expected response:

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

### Create a Test Agent

```bash
kubectl apply -f - <<EOF
apiVersion: kagent.dev/v1alpha2
kind: Agent
metadata:
  name: hello-agent
  namespace: consonant-system
spec:
  type: Declarative
  declarative:
    description: "Test agent"
    modelRef:
      name: default-openai
EOF
```

Check your Consonant UI - you should see the agent appear in real-time!

---

## What Happened Behind the Scenes

### On Your Backend Server:

Cloudflare tunnel connector runs
Connects to Cloudflare network
Exposes your backend at [https://consonant.yourcompany.com](https://consonant.yourcompany.com)

### In Your Kubernetes Cluster:

#### Pre-Install Hook:

Job runs with cloudflared sidecar
Calls POST /api/v1/clusters via tunnel
Gets back clusterId and clusterToken
Creates Secret with credentials

#### Main Installation:

Relayer deployed with cloudflared sidecar
KAgent installed (minimal, no UI)
Service created (OTEL endpoint on :4317)

#### Runtime:

Cloudflared establishes tunnel to backend
Relayer connects to localhost:8080 → cloudflared → tunnel → backend
KAgent sends traces to relayer on :4317
Relayer forwards to backend via Socket.io
Backend streams to UI in real-time

---

## Configuration Options

### Use Different LLM Provider

```bash
# Anthropic
--set llm.provider=anthropic \
--set llm.apiKey=sk-ant-... \
--set llm.model=claude-3-5-sonnet-20241022

# Gemini
--set llm.provider=gemini \
--set llm.apiKey=... \
--set llm.model=gemini-1.5-pro

# Azure OpenAI
--set llm.provider=azureopenai \
--set llm.apiKey=... \
--set llm.azure.endpoint=https://your-endpoint.openai.azure.com \
--set llm.azure.deploymentName=gpt-4
```

```

### All Available Flags

```bash
# Required
--set cluster.name=<name>                    # Unique cluster identifier
--set backend.url=<url>                      # Backend URL (with Cloudflare tunnel)
--set cloudflare.tunnelToken=<token>         # Cloudflare tunnel token
--set llm.apiKey=<key>                       # LLM API key

# Optional (common)
--set llm.provider=<provider>                # openai, anthropic, gemini (default: openai)
--set llm.model=<model>                      # Model name (default: gpt-4o-mini)
--set relayer.replicas=<n>                  # Number of replicas (default: 1)
--set relayer.logLevel=<level>              # trace, debug, info, warn, error (default: info)

# Optional (advanced)
--set cloudflare.enabled=<bool>              # Use Cloudflare tunnel (default: true)
--set kagent.enabled=<bool>                  # Install KAgent (default: true)
--set kagent.installCRDs=<bool>              # Install KAgent CRDs (default: true)
--set relayer.resources.requests.cpu=<cpu>  # CPU request (default: 200m)
--set relayer.resources.requests.memory=<mem>  # Memory request (default: 256Mi)
```

### Example: High Availability Setup

```bash
helm install consonant-prod oci://ghcr.io/consonant/charts/consonant-relayer \
  --create-namespace \
  --namespace consonant-system \
  --set cluster.name=production-us-east \
  --set backend.url=https://consonant.yourcompany.com \
  --set cloudflare.tunnelToken=eyJ... \
  --set llm.provider=anthropic \
  --set llm.apiKey=sk-ant-... \
  --set relayer.replicas=3 \
  --set relayer.resources.requests.cpu=500m \
  --set relayer.resources.requests.memory=512Mi \
  --set relayer.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].weight=100 \
  --set relayer.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.labelSelector.matchLabels.app\.kubernetes\.io/name=consonant-relayer \
  --set relayer.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[0].podAffinityTerm.topologyKey=kubernetes.io/hostname
```

---

## Troubleshooting

### Pre-Install Hook Failed

**Symptom**: `Error: pre-install hook "consonant-prod-consonant-relayer-register" failed`

**Debug**:

```bash
# Check job logs
kubectl logs -n ${NAMESPACE} job/consonant-prod-consonant-relayer-register

# Common issues:
# 1. Backend not accessible
# 2. Tunnel not configured correctly
# 3. Network connectivity issues
```

**Solution**:

```bash
# Test backend connectivity from cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v https://consonant.yourcompany.com/health

# If tunnel issue, verify on backend server
cloudflared tunnel info consonant-backend

# Delete failed release and retry
helm uninstall consonant-prod -n ${NAMESPACE}
# Fix the issue
# Re-install
```

### Relayer Not Connecting

**Symptom**: Pod running but readiness probe failing

**Debug**:

```bash
# Check relayer logs
kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=consonant-relayer -c relayer

# Check cloudflared sidecar
kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=consonant-relayer -c cloudflared
```

**Solution**:

```bash
# If tunnel token wrong
helm upgrade consonant-prod oci://ghcr.io/consonant/charts/consonant-relayer \
  --reuse-values \
  --set cloudflare.tunnelToken=CORRECT_TOKEN

# If cluster credentials corrupted
kubectl delete secret consonant-prod-consonant-relayer-cluster -n ${NAMESPACE}
helm upgrade consonant-prod oci://ghcr.io/consonant/charts/consonant-relayer --reuse-values
```

### No Telemetry Showing

**Symptom**: Agent created but no events in UI

**Debug**:

```bash
# Check KAgent is sending to relayer
kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=kagent

# Check relayer is receiving
kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=consonant-relayer | grep "OTEL"

# Verify OTEL endpoint
kubectl get deployment kagent-controller -n ${NAMESPACE} -o yaml | grep -A5 OTEL
```

---

## Uninstallation

```bash
# Uninstall Helm release
helm uninstall consonant-prod -n ${NAMESPACE}

# Delete namespace (optional)
kubectl delete namespace ${NAMESPACE}

# Backend cleanup (optional)
curl -X DELETE https://consonant.yourcompany.com/api/v1/clusters/${CLUSTER_ID}
```

---

Summary
What we have setup:

✅ Self-hosted backend with Cloudflare tunnel
✅ Kubernetes relayer with tunnel sidecar
✅ KAgent for AI agents
✅ Real-time telemetry streaming

Installation commands:

Start backend: npm start
Create tunnel: Cloudflare dashboard
Install to K8s: helm install consonant-prod ...

Total setup time: ~10 minutes
No manual configuration files needed!