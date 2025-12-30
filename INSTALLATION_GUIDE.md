# Consonant Installation Guide (Simplified)

## Overview

This guide shows you how to install Consonant with **minimal setup** - no manual tunnel configuration needed!

## Prerequisites

### ✅ What You Need

1. **Backend Server** (your self-hosted Consonant backend)
   - Running and accessible on localhost (e.g., `http://localhost:3000`)
   - Can be anywhere: VPS, home server, laptop, etc.

2. **Kubernetes Cluster**
   - Any K8s cluster with `kubectl` and Helm 3.8+

3. **Cloudflare Account** (free tier works)
   - Domain added to Cloudflare
   - Zero Trust enabled

4. **LLM API Key** (OpenAI, Anthropic, or Gemini)

---

## Part 1: Backend Setup (Quick)

```bash
# Clone and install backend
git clone https://github.com/yourorg/consonant-backend
cd consonant-backend
npm install

# Configure environment
cp .env.example .env
# Edit .env with your database/redis settings

# Run migrations
npx prisma migrate deploy

# Start backend
npm start
# Backend now running on http://localhost:3000
```

---

## Part 2: Cloudflare Tunnel (2 Steps!)

### Step 1: Create Tunnel in Cloudflare Dashboard

1. Go to [Cloudflare Zero Trust Dashboard](https://one.dash.cloudflare.com/)
2. Navigate to **Networks → Tunnels**
3. Click **Create a tunnel**
4. Choose **Cloudflared**
5. Name it: `consonant-backend`
6. Click **Save tunnel**
7. **Copy the tunnel token** (looks like `eyJhIjoiY...`) - you'll need this!

### Step 2: Install Tunnel Connector

Cloudflare shows you a command like:

```bash
# Copy and run this command on your backend server
docker run cloudflare/cloudflared:latest tunnel --no-autoupdate run --token eyJhIjoiY...
```

Or if you prefer running as a system service:

```bash
# Linux/macOS
cloudflared service install eyJhIjoiY...
```

### Step 3: Route Your Domain

Still in the Cloudflare dashboard:

1. Under **Public Hostname**, click **Add a public hostname**
2. Set:
   - **Subdomain**: `consonant` (or whatever you want)
   - **Domain**: `yourcompany.com` (your domain)
   - **Service**: `http://localhost:3000`
3. Click **Save hostname**

**Done!** Your backend is now accessible at `https://consonant.yourcompany.com`

Verify:
```bash
curl https://consonant.yourcompany.com/health
# Expected: {"status":"ok",...}
```

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

**That's it!** The chart:
1. Registers your cluster with the backend
2. Installs the relayer (with Cloudflare tunnel sidecar)
3. Installs KAgent (minimal config, no UI)
4. Connects everything together

### Monitor Installation

```bash
# Watch pods start
kubectl get pods -n consonant-system -w

# Check logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer -f
```

**Expected output:**
```
✅ Cluster registered: cluster_abc123
✅ Connected to backend: https://consonant.yourcompany.com
✅ OTEL receiver ready on :4317
✅ Tunnel established
```

---

## Verify Everything Works

```bash
# Port-forward to health endpoint
kubectl port-forward -n consonant-system svc/consonant-prod-consonant-relayer 8080:8080

# Check health (in another terminal)
curl http://localhost:8080/health
```

**Expected response:**
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
- Cloudflare tunnel connector runs
- Connects to Cloudflare network
- Exposes your backend at `https://consonant.yourcompany.com`

### In Your Kubernetes Cluster:
1. **Pre-Install Hook**:
   - Job runs with cloudflared sidecar
   - Calls `POST /api/v1/clusters` via tunnel
   - Gets back `clusterId` and `clusterToken`
   - Creates Secret with credentials

2. **Main Installation**:
   - Relayer deployed with cloudflared sidecar
   - KAgent installed (minimal, no UI)
   - Service created (OTEL endpoint on :4317)

3. **Runtime**:
   - Cloudflared establishes tunnel to backend
   - Relayer connects to `localhost:8080` → cloudflared → tunnel → backend
   - KAgent sends traces to relayer on `:4317`
   - Relayer forwards to backend via Socket.io
   - Backend streams to UI in real-time

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

### High Availability

```bash
# Multiple relayer replicas
--set relayer.replicas=3

# More resources
--set relayer.resources.requests.cpu=500m \
--set relayer.resources.requests.memory=512Mi
```

### Skip KAgent (if already installed)

```bash
--set kagent.enabled=false
```

---

## Troubleshooting

### Pre-Install Hook Failed

```bash
# Check job logs
kubectl logs -n consonant-system job/consonant-prod-consonant-relayer-register

# Common issue: Backend not accessible
# Test from cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v https://consonant.yourcompany.com/health
```

### Relayer Not Connecting

```bash
# Check relayer logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer -c relayer

# Check tunnel sidecar
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer -c cloudflared
```

### No Telemetry

```bash
# Check KAgent logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=kagent

# Verify OTEL endpoint
kubectl get svc -n consonant-system
# Should see: consonant-prod-consonant-relayer with port 4317
```

---

## Uninstall

```bash
helm uninstall consonant-prod -n consonant-system
kubectl delete namespace consonant-system
```

---

## Summary

**What you built:**
- ✅ Self-hosted backend with Cloudflare tunnel
- ✅ Kubernetes relayer with tunnel sidecar
- ✅ KAgent for AI agents
- ✅ Real-time telemetry streaming

**Installation commands:**
1. Start backend: `npm start`
2. Create tunnel: Cloudflare dashboard
3. Install to K8s: `helm install consonant-prod ...`

**Total setup time:** ~10 minutes

**No manual configuration files needed!**