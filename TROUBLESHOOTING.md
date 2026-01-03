# Troubleshooting Guide

Complete troubleshooting guide for Consonant Relayer Helm chart.

## 📋 Table of Contents

- [Quick Diagnostics](#quick-diagnostics)
- [Installation Issues](#installation-issues)
- [Connection Issues](#connection-issues)
- [Performance Issues](#performance-issues)
- [Secret Management Issues](#secret-management-issues)
- [Network Issues](#network-issues)
- [KAgent Issues](#kagent-issues)
- [Resource Issues](#resource-issues)
- [Logging and Debugging](#logging-and-debugging)
- [Recovery Procedures](#recovery-procedures)

## 🔍 Quick Diagnostics

### Health Check Script
```bash
#!/bin/bash
# consonant-health-check.sh

NAMESPACE="${1:-consonant-system}"
RELEASE="${2:-consonant-prod}"

echo "🔍 Consonant Relayer Health Check"
echo "=================================="
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE"
echo ""

# Check namespace exists
if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
  echo "❌ Namespace '$NAMESPACE' does not exist"
  exit 1
fi

# Check Helm release
echo "📦 Helm Release Status:"
helm status "$RELEASE" -n "$NAMESPACE" 2>/dev/null || echo "❌ Release not found"
echo ""

# Check pods
echo "🐳 Pod Status:"
kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE"
echo ""

# Check pod readiness
NOT_READY=$(kubectl get pods -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE" \
  -o jsonpath='{.items[?(@.status.phase!="Running")].metadata.name}')
if [ -n "$NOT_READY" ]; then
  echo "⚠️  Pods not ready: $NOT_READY"
  echo ""
fi

# Check recent events
echo "📋 Recent Events (last 10):"
kubectl get events -n "$NAMESPACE" \
  --sort-by='.lastTimestamp' \
  --field-selector involvedObject.kind=Pod \
  | tail -10
echo ""

# Check secrets
echo "🔐 Secrets:"
kubectl get secrets -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE"
echo ""

# Check services
echo "🌐 Services:"
kubectl get svc -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE"
echo ""

# Test health endpoint
echo "🏥 Health Endpoint Test:"
POD=$(kubectl get pod -n "$NAMESPACE" -l "app.kubernetes.io/instance=$RELEASE,app.kubernetes.io/component=relayer" \
  -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD" ]; then
  kubectl exec -n "$NAMESPACE" "$POD" -c relayer -- \
    wget -qO- http://localhost:8080/health 2>/dev/null | jq '.' || echo "❌ Health check failed"
else
  echo "❌ No relayer pods found"
fi
echo ""

echo "=================================="
echo "✅ Health check complete"
```

Run:
```bash
chmod +x consonant-health-check.sh
./consonant-health-check.sh consonant-system consonant-prod
```

### Quick Command Reference
```bash
# View all resources
kubectl get all -n consonant-system

# Check pod logs (all containers)
kubectl logs -n consonant-system -l app.kubernetes.io/name=consonant-relayer --all-containers=true -f

# Describe problematic pod
kubectl describe pod -n consonant-system <POD_NAME>

# Get events sorted by time
kubectl get events -n consonant-system --sort-by='.lastTimestamp'

# Check resource usage
kubectl top pods -n consonant-system

# Execute command in pod
kubectl exec -it -n consonant-system <POD_NAME> -c relayer -- /bin/sh
```

## 🚨 Installation Issues

### Issue: Pre-Install Hook Failed

**Symptoms:**
```
Error: failed pre-install: job failed: BackoffLimitExceeded
```

**Diagnosis:**
```bash
# Check hook job
kubectl get job -n consonant-system

# View logs
kubectl logs -n consonant-system job/consonant-prod-consonant-relayer-register
```

**Common Causes:**

#### 1. Backend Not Accessible

**Error in logs:**
```
curl: (6) Could not resolve host: backend.company.com
curl: (7) Failed to connect to backend.company.com port 443
```

**Solution:**
```bash
# Test backend connectivity from cluster
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  curl -v https://your-backend.com/health

# If fails, check:
# 1. DNS resolution
kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
  nslookup your-backend.com

# 2. Network policy
kubectl get networkpolicy -n consonant-system

# 3. Firewall rules
# Ensure cluster can reach backend
```

#### 2. Invalid Tunnel Token

**Error in logs:**
```
Invalid tunnel token format
Token validation failed
```

**Solution:**
```bash
# Verify token format
echo $TUNNEL_TOKEN | wc -c
# Should be > 100 characters

# Token should start with "eyJ"
echo $TUNNEL_TOKEN | head -c 3
# Output: eyJ

# Regenerate token in Cloudflare dashboard
# Networks → Tunnels → Your Tunnel → Configure → Copy Token
```

#### 3. Backend Registration Failure

**Error in logs:**
```
HTTP/1.1 400 Bad Request
{"error":"Cluster name already exists"}
```

**Solution:**
```bash
# Option 1: Use different cluster name
helm install consonant-prod consonant/consonant-relayer \
  --set cluster.name="production-us-east-1-v2"

# Option 2: Unregister old cluster in backend UI
# Backend → Clusters → Delete old cluster

# Option 3: Skip registration if credentials exist
helm install consonant-prod consonant/consonant-relayer \
  --set backend.credentials.existingSecret="consonant-cluster-credentials"
```

### Issue: Values Validation Failed

**Symptoms:**
```
Error: values don't meet the specifications of the schema(s)
```

**Diagnosis:**
```bash
# Check which validation failed
helm install consonant-prod consonant/consonant-relayer \
  --dry-run --debug \
  -f values.yaml 2>&1 | grep -A 5 "Error"
```

**Common Causes:**

#### 1. Invalid Cluster Name

**Error:**
```
cluster.name: Does not match pattern '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'
```

**Solution:**
```yaml
# ❌ Invalid
cluster:
  name: "Production_Cluster"  # Uppercase not allowed
  name: "-prod-cluster"       # Cannot start with dash
  name: "prod-cluster-"       # Cannot end with dash

# ✅ Valid
cluster:
  name: "production-cluster"
  name: "prod-us-east-1"
  name: "cluster01"
```

#### 2. Invalid Backend URL

**Error:**
```
backend.url: Must start with http:// or https://
```

**Solution:**
```yaml
# ❌ Invalid
backend:
  url: "backend.company.com"
  url: "ws://backend.company.com"

# ✅ Valid
backend:
  url: "https://backend.company.com"
  url: "http://localhost:3000"  # For dev only
```

#### 3. Invalid LLM Configuration

**Error:**
```
llm.provider: Must be one of [anthropic, openai, gemini, azure, ollama]
```

**Solution:**
```yaml
# ❌ Invalid
llm:
  provider: "claude"  # Wrong

# ✅ Valid
llm:
  provider: "anthropic"
  model: "claude-3-5-sonnet-20241022"
```

### Issue: Image Pull Errors

**Symptoms:**
```
Failed to pull image: rpc error: code = Unknown desc = Error response from daemon
```

**Diagnosis:**
```bash
kubectl describe pod -n consonant-system <POD_NAME>
```

**Common Causes:**

#### 1. Private Registry Authentication

**Solution:**
```bash
# Create image pull secret
kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username=<USERNAME> \
  --docker-password=<TOKEN> \
  --namespace=consonant-system

# Use in values
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set imagePullSecrets[0].name=ghcr-secret
```

#### 2. Wrong Image Tag/Digest

**Solution:**
```bash
# Verify image exists
docker pull ghcr.io/consonant/relayer:1.0.0

# Use correct tag
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.image.tag="1.0.0"
```

## 🔌 Connection Issues

### Issue: Relayer Not Connecting to Backend

**Symptoms:**
- Pod running but health check shows `"connected": false`
- Logs show repeated connection attempts

**Diagnosis:**
```bash
# Check relayer logs
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer -c relayer --tail=100

# Check cloudflared logs (if enabled)
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer -c cloudflared --tail=100

# Test health
kubectl port-forward -n consonant-system svc/consonant-prod-consonant-relayer 8080:8080
curl http://localhost:8080/health
```

**Common Causes:**

#### 1. Cloudflared Not Connected

**Error in logs:**
```
ERR  error="Unable to reach the origin service" connIndex=0
WARN Retrying connection in 2s connIndex=0
```

**Solution:**
```bash
# Check tunnel status in Cloudflare dashboard
# Zero Trust → Networks → Tunnels → Your Tunnel

# Verify tunnel token
kubectl get secret -n consonant-system \
  consonant-prod-consonant-relayer-tunnel \
  -o jsonpath='{.data.token}' | base64 -d

# Recreate tunnel if needed
# 1. Delete old tunnel in Cloudflare
# 2. Create new tunnel
# 3. Update secret
kubectl create secret generic consonant-prod-consonant-relayer-tunnel \
  --from-literal=token="NEW_TOKEN" \
  --namespace=consonant-system \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods
kubectl rollout restart deployment -n consonant-system
```

#### 2. WebSocket Connection Failed

**Error in logs:**
```
WebSocket connection failed: timeout
Error connecting to backend: ECONNREFUSED
```

**Solution:**
```bash
# Test backend WebSocket from within cluster
kubectl run -it --rm ws-test --image=node:18-alpine --restart=Never -- sh -c "
  npm install -g wscat
  wscat -c wss://your-backend.com/socket.io/?EIO=4&transport=websocket
"

# Check if backend is listening
curl -I https://your-backend.com/socket.io/

# Verify backend logs show connection attempts
# Backend should log: "Client connecting from cluster_xxx"
```

#### 3. Invalid Cluster Credentials

**Error in logs:**
```
Authentication failed: Invalid cluster ID or token
Unauthorized: 401
```

**Solution:**
```bash
# Check credentials secret
kubectl get secret -n consonant-system \
  consonant-prod-consonant-relayer-cluster \
  -o jsonpath='{.data.clusterId}' | base64 -d
echo ""
kubectl get secret -n consonant-system \
  consonant-prod-consonant-relayer-cluster \
  -o jsonpath='{.data.clusterToken}' | base64 -d
echo ""

# Verify in backend database
# SELECT * FROM clusters WHERE cluster_id = 'cluster_xxx';

# Re-register if credentials invalid
kubectl delete secret -n consonant-system \
  consonant-prod-consonant-relayer-cluster

helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set backend.credentials.existingSecret=""

# This will trigger re-registration
```

#### 4. Circuit Breaker Open

**Error in logs:**
```
Circuit breaker is OPEN
Skipping connection attempt (circuit breaker)
```

**Solution:**
```bash
# Circuit breaker opens after too many failures
# Wait for timeout, then it will try half-open state

# Check circuit breaker config
kubectl get configmap -n consonant-system \
  consonant-prod-consonant-relayer-config \
  -o jsonpath='{.data.backend\.yaml}' | grep -A 10 circuitBreaker

# Reduce threshold if too sensitive
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set backend.circuitBreaker.failureThreshold=10

# Or disable for debugging (NOT FOR PRODUCTION)
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set backend.circuitBreaker.enabled=false
```

### Issue: Connection Drops Frequently

**Symptoms:**
- Relayer connects then disconnects repeatedly
- High reconnection count in logs

**Diagnosis:**
```bash
# Check reconnection metrics
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer \
  | grep -i "reconnect\|disconnect"

# Check network stability
kubectl exec -n consonant-system <POD_NAME> -c relayer -- \
  ping -c 10 1.1.1.1
```

**Common Causes:**

#### 1. Network Policy Too Restrictive

**Solution:**
```bash
# Temporarily disable NetworkPolicy
kubectl delete networkpolicy -n consonant-system \
  consonant-prod-consonant-relayer

# Test if connections stable
# If stable, adjust NetworkPolicy egress rules

# Re-enable with updated rules
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set networkPolicy.egress.allowHTTPS.destinations[0]="0.0.0.0/0"
```

#### 2. Backend Timeout Too Short

**Solution:**
```yaml
# Increase timeouts
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set backend.connectionTimeout=30 \
  --set backend.healthCheck.timeout=10
```

#### 3. Pod Resource Limits

**Solution:**
```bash
# Check if pod is being throttled
kubectl describe pod -n consonant-system <POD_NAME> | grep -A 10 "Limits"

# Increase resources
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.resources.limits.cpu=2000m \
  --set relayer.resources.limits.memory=2Gi
```

## 🔐 Secret Management Issues

### Issue: External Secrets Not Working

**Symptoms:**
```
ExternalSecret is not ready
Secret not found
```

**Diagnosis:**
```bash
# Check ExternalSecret status
kubectl get externalsecrets -n consonant-system

# Describe for errors
kubectl describe externalsecret -n consonant-system \
  consonant-prod-consonant-relayer-llm

# Check SecretStore
kubectl get secretstore,clustersecretstore -A

# Check External Secrets Operator logs
kubectl logs -n external-secrets-system \
  -l app.kubernetes.io/name=external-secrets
```

**Common Causes:**

#### 1. SecretStore Not Configured

**Solution:**
```bash
# Create SecretStore for Vault
kubectl apply -f - <<EOF
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
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets-system
EOF

# Verify
kubectl get clustersecretstore vault-prod
```

#### 2. Secret Path Incorrect

**Error:**
```
error getting secret: secret not found
```

**Solution:**
```bash
# Test secret path manually
# For Vault:
vault kv get secret/consonant/llm-key

# For AWS:
aws secretsmanager get-secret-value \
  --secret-id consonant/llm-key

# Update path in values
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set secrets.external.paths.llmApiKey.key="secret/data/consonant/llm-key"
```

#### 3. Permissions Issue

**Error:**
```
permission denied
access denied
```

**Solution:**
```bash
# For Vault: Update policy
vault policy write external-secrets - <<EOF
path "secret/data/consonant/*" {
  capabilities = ["read"]
}
EOF

# Bind to Kubernetes auth role
vault write auth/kubernetes/role/external-secrets \
  bound_service_account_names=external-secrets-sa \
  bound_service_account_namespaces=external-secrets-system \
  policies=external-secrets \
  ttl=24h

# For AWS: Update IAM policy
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

### Issue: Kubernetes Secrets Not Found

**Symptoms:**
```
Error: secret "consonant-prod-consonant-relayer-llm" not found
```

**Diagnosis:**
```bash
# List secrets
kubectl get secrets -n consonant-system

# Check if secret was created
kubectl describe pod -n consonant-system <POD_NAME>
```

**Solution:**
```bash
# Ensure secrets.mode is set correctly
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set secrets.mode=kubernetes \
  --set secrets.kubernetes.llmApiKey="sk-ant-..." \
  --set secrets.kubernetes.tunnelToken="eyJ..."

# Or create secret manually
kubectl create secret generic \
  consonant-prod-consonant-relayer-llm \
  --from-literal=apiKey="sk-ant-..." \
  --namespace=consonant-system
```

## 🌐 Network Issues

### Issue: NetworkPolicy Blocking Traffic

**Symptoms:**
- Pods can't reach external APIs
- Cloudflared can't connect
- DNS resolution fails

**Diagnosis:**
```bash
# Test DNS
kubectl exec -n consonant-system <POD_NAME> -c relayer -- \
  nslookup google.com

# Test HTTPS
kubectl exec -n consonant-system <POD_NAME> -c relayer -- \
  wget -qO- https://api.anthropic.com/v1/messages --timeout=5

# Check NetworkPolicy
kubectl get networkpolicy -n consonant-system -o yaml
```

**Solution:**

#### Temporarily Disable NetworkPolicy
```bash
# Disable for testing
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set networkPolicy.enabled=false

# Test if issue resolved
# If yes, adjust NetworkPolicy rules
```

#### Add Required Egress Rules
```yaml
# Update values
networkPolicy:
  enabled: true
  egress:
    allowDNS: true
    allowKubeAPI: true
    allowHTTPS:
      enabled: true
      destinations:
        # Anthropic API
        - "52.94.133.131/32"
        # OpenAI API
        - "104.18.0.0/15"
        # Cloudflare
        - "198.41.128.0/17"
        # Or allow all (less secure)
        - "0.0.0.0/0"
```

### Issue: DNS Resolution Fails

**Symptoms:**
```
dial tcp: lookup backend.company.com: no such host
```

**Diagnosis:**
```bash
# Test DNS from pod
kubectl exec -n consonant-system <POD_NAME> -c relayer -- \
  nslookup backend.company.com

# Check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Check DNS config
kubectl exec -n consonant-system <POD_NAME> -c relayer -- \
  cat /etc/resolv.conf
```

**Solution:**
```bash
# Ensure NetworkPolicy allows DNS
kubectl get networkpolicy -n consonant-system \
  consonant-prod-consonant-relayer \
  -o jsonpath='{.spec.egress[*].to[*].namespaceSelector}'

# Should allow kube-system namespace
# If not:
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set networkPolicy.egress.allowDNS=true
```

## 🤖 KAgent Issues

### Issue: No Telemetry Data

**Symptoms:**
- Agents created but no data in UI
- OTEL endpoint not receiving data

**Diagnosis:**
```bash
# Check KAgent logs
kubectl logs -n consonant-system -l app.kubernetes.io/name=kagent

# Check relayer OTEL endpoint
kubectl port-forward -n consonant-system \
  svc/consonant-prod-consonant-relayer 4317:4317

# Try sending test OTEL data
# (requires grpcurl)
grpcurl -plaintext localhost:4317 list
```

**Common Causes:**

#### 1. KAgent Can't Reach Relayer

**Solution:**
```bash
# Check service exists
kubectl get svc -n consonant-system

# Test connectivity from KAgent namespace
kubectl run -it --rm test --image=curlimages/curl --restart=Never -- \
  curl -v telnet://consonant-prod-consonant-relayer.consonant-system:4317

# Check NetworkPolicy allows KAgent → Relayer
kubectl get networkpolicy -n consonant-system -o yaml | grep -A 20 ingress

# Update NetworkPolicy if needed
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set networkPolicy.ingress.allowKAgent=true
```

#### 2. Wrong OTEL Endpoint

**Solution:**
```bash
# Check Agent OTEL config
kubectl get agent -n consonant-system test-agent -o yaml | grep otel

# Should be: consonant-prod-consonant-relayer.consonant-system:4317

# Check ModelConfig
kubectl get modelconfig -n consonant-system -o yaml

# Update if needed
kubectl edit modelconfig -n consonant-system default-anthropic
# Change otelEndpoint to correct value
```

#### 3. LLM API Key Invalid

**Solution:**
```bash
# Test API key manually
# For Anthropic:
curl https://api.anthropic.com/v1/messages \
  -H "x-api-key: $API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d '{
    "model": "claude-3-5-sonnet-20241022",
    "max_tokens": 1024,
    "messages": [{"role": "user", "content": "Hello"}]
  }'

# If invalid, update secret
kubectl create secret generic \
  consonant-prod-consonant-relayer-llm \
  --from-literal=apiKey="NEW_KEY" \
  --namespace=consonant-system \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pods
kubectl rollout restart deployment -n consonant-system
```

### Issue: Agent Creation Fails

**Symptoms:**
```
Error from server: error creating agent
```

**Diagnosis:**
```bash
# Check KAgent CRDs
kubectl get crd | grep kagent

# Check KAgent controller
kubectl logs -n consonant-system -l app.kubernetes.io/name=kagent-controller

# Describe agent
kubectl describe agent -n consonant-system test-agent
```

**Solution:**
```bash
# Reinstall KAgent if CRDs missing
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set kagent.installCRDs=true

# Or install manually
kubectl apply -f https://raw.githubusercontent.com/kagent-dev/kagent/main/config/crd/bases/kagent.yaml
```

## 📊 Performance Issues

### Issue: High CPU Usage

**Diagnosis:**
```bash
# Check resource usage
kubectl top pods -n consonant-system

# Check for CPU throttling
kubectl describe pod -n consonant-system <POD_NAME> | grep -i throttl
```

**Solution:**
```bash
# Increase CPU limits
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.resources.limits.cpu=4000m

# Enable HPA if needed
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.autoscaling.enabled=true \
  --set relayer.autoscaling.minReplicas=3 \
  --set relayer.autoscaling.maxReplicas=10 \
  --set relayer.autoscaling.targetCPUUtilizationPercentage=70
```

### Issue: High Memory Usage

**Diagnosis:**
```bash
# Check memory
kubectl top pods -n consonant-system

# Check for OOM kills
kubectl get events -n consonant-system | grep OOM
```

**Solution:**
```bash
# Increase memory limits
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.resources.limits.memory=4Gi

# Reduce batch sizes
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.otel.batchSize=100 \
  --set relayer.otel.maxQueueSize=1000
```

### Issue: Slow Response Times

**Diagnosis:**
```bash
# Check latency metrics in Prometheus
# Query: histogram_quantile(0.99, rate(relayer_request_duration_bucket[5m]))

# Check backend response times
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer \
  | grep -i "duration\|latency"
```

**Solution:**
```bash
# Increase replicas
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.replicas=5

# Tune reconnection backoff
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set backend.reconnection.maxDelay=10000 \
  --set backend.reconnection.multiplier=1.5

# Optimize OTEL batching
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.otel.flushInterval=5000 \
  --set relayer.otel.batchSize=500
```

## 🔧 Recovery Procedures

### Complete Reinstall
```bash
# 1. Backup cluster credentials
kubectl get secret -n consonant-system \
  consonant-prod-consonant-relayer-cluster \
  -o yaml > cluster-credentials-backup.yaml

# 2. Backup values
helm get values consonant-prod -n consonant-system > values-backup.yaml

# 3. Uninstall
helm uninstall consonant-prod -n consonant-system

# 4. Clean up resources
kubectl delete all -n consonant-system -l app.kubernetes.io/instance=consonant-prod
kubectl delete secret -n consonant-system -l app.kubernetes.io/instance=consonant-prod
kubectl delete configmap -n consonant-system -l app.kubernetes.io/instance=consonant-prod

# 5. Reinstall
helm install consonant-prod consonant/consonant-relayer \
  -f values-backup.yaml \
  --namespace consonant-system

# 6. Restore credentials if registration fails
kubectl apply -f cluster-credentials-backup.yaml
```

### Force Pod Restart
```bash
# Restart all relayer pods
kubectl rollout restart deployment -n consonant-system \
  consonant-prod-consonant-relayer

# Delete specific pod
kubectl delete pod -n consonant-system <POD_NAME>

# Scale down and up
kubectl scale deployment -n consonant-system \
  consonant-prod-consonant-relayer --replicas=0
sleep 10
kubectl scale deployment -n consonant-system \
  consonant-prod-consonant-relayer --replicas=3
```

### Reset Circuit Breaker
```bash
# Restart pods to reset circuit breaker state
kubectl rollout restart deployment -n consonant-system

# Or adjust thresholds
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set backend.circuitBreaker.failureThreshold=10 \
  --set backend.circuitBreaker.timeout=120
```

## 📝 Logging and Debugging

### Enable Debug Logging
```bash
helm upgrade consonant-prod consonant/consonant-relayer \
  --reuse-values \
  --set relayer.logging.level=debug
```

### Structured Log Queries
```bash
# Filter by level
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer \
  | jq 'select(.level=="error")'

# Filter by component
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer \
  | jq 'select(.component=="socket")'

# Show connection events
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer \
  | jq 'select(.msg | contains("connect"))'
```

### Export Logs for Analysis
```bash
# Export last hour of logs
kubectl logs -n consonant-system \
  -l app.kubernetes.io/component=relayer \
  --since=1h \
  --all-containers=true > relayer-logs-$(date +%Y%m%d-%H%M%S).log

# Export with timestamps
kubectl logs -n consonant-system \
  -l app.kubernetes.io/component=relayer \
  --timestamps=true \
  --since=24h > relayer-logs-24h.log
```

## 🆘 Getting Help

### Gather Diagnostic Bundle
```bash
#!/bin/bash
# collect-diagnostics.sh

BUNDLE_DIR="consonant-diagnostics-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BUNDLE_DIR"

# Helm info
helm list -n consonant-system > "$BUNDLE_DIR/helm-list.txt"
helm get values consonant-prod -n consonant-system > "$BUNDLE_DIR/helm-values.yaml"
helm get manifest consonant-prod -n consonant-system > "$BUNDLE_DIR/helm-manifest.yaml"

# Kubernetes resources
kubectl get all -n consonant-system -o yaml > "$BUNDLE_DIR/resources.yaml"
kubectl get secrets -n consonant-system > "$BUNDLE_DIR/secrets-list.txt"
kubectl get events -n consonant-system --sort-by='.lastTimestamp' > "$BUNDLE_DIR/events.txt"

# Pod details
kubectl describe pods -n consonant-system > "$BUNDLE_DIR/pod-describe.txt"
kubectl top pods -n consonant-system > "$BUNDLE_DIR/pod-top.txt"

# Logs
kubectl logs -n consonant-system -l app.kubernetes.io/component=relayer --tail=1000 > "$BUNDLE_DIR/relayer-logs.txt"
kubectl logs -n consonant-system -l app.kubernetes.io/name=kagent --tail=1000 > "$BUNDLE_DIR/kagent-logs.txt"

# Jobs
kubectl logs -n consonant-system job/consonant-prod-consonant-relayer-register > "$BUNDLE_DIR/registration-job.txt"

# Compress
tar czf "$BUNDLE_DIR.tar.gz" "$BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"

echo "Diagnostic bundle created: $BUNDLE_DIR.tar.gz"
```

### Contact Support

Email: support@consonant.xyz

Include:
- Diagnostic bundle
- Helm chart version
- Kubernetes version
- Error messages
- Steps to reproduce

---

**Last Updated:** 2026-01-03