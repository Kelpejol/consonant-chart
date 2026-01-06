# Consonant Relayer Architecture

**Version:** 0.1.0-alpha.1  
**Last Updated:** 2026-01-05  
**Architecture Pattern:** Outbound gRPC, Self-Hosted Control Plane

## Table of Contents

- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Component Details](#component-details)
- [Authentication Flow](#authentication-flow)
- [Connection Lifecycle](#connection-lifecycle)
- [Data Flow](#data-flow)
- [Security Model](#security-model)
- [Failure Modes](#failure-modes)

---

## Overview

Consonant Relayer is a **cluster-resident agent** that establishes **outbound-only** connections to self-hosted Consonant backends via gRPC. It enables AI agent orchestration without requiring inbound cluster access, making it suitable for NAT'd, firewalled, and air-gapped environments.

### Design Principles

1. **Outbound-Only**: Relayer initiates connections TO backend, never reverse
2. **Self-Hosted**: No SaaS dependencies, complete data sovereignty
3. **Zero-Trust**: Bearer token authentication for registration, cluster credentials for runtime
4. **Observable**: Built-in OTEL Collector for comprehensive telemetry
5. **Resilient**: Circuit breaker, exponential backoff, automatic reconnection

### Key Differences from Traditional Architectures

| Traditional | Consonant Relayer |
|-------------|-------------------|
| Backend connects TO cluster | Relayer connects TO backend |
| Requires inbound firewall rules | Zero inbound requirements |
| WebSocket/Socket.io polling | gRPC bidirectional streaming |
| External tunnel services | Direct outbound connection |
| Complex NAT traversal | Works behind NAT automatically |

---

## System Architecture

### High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    USER'S INFRASTRUCTURE                          │
│                                                                   │
│  ┌──────────────────┐              ┌─────────────────────────┐  │
│  │  Backend Server  │              │  Kubernetes Cluster      │  │
│  │  (Self-Hosted)   │              │                          │  │
│  │                  │              │  ┌───────────────────┐   │  │
│  │  ┌────────────┐  │              │  │  Relayer Pod     │   │  │
│  │  │  Fastify   │  │              │  │                   │   │  │
│  │  │  Backend   │  │◄─────────────┼──┤  Node.js/Fastify  │   │  │
│  │  │            │  │   gRPC       │  │  (Outbound only)  │   │  │
│  │  │            │  │   Stream     │  │                   │   │  │
│  │  │  gRPC      │  │              │  └───────────────────┘   │  │
│  │  │  Server    │  │              │           ▲              │  │
│  │  └────────────┘  │              │           │ OTLP         │  │
│  │                  │              │  ┌────────┴──────────┐   │  │
│  │  ┌────────────┐  │              │  │  OTEL Collector   │   │  │
│  │  │ PostgreSQL │  │              │  │   (DaemonSet)     │   │  │
│  │  └────────────┘  │              │  └───────────────────┘   │  │
│  │                  │              │           ▲              │  │
│  │  ┌────────────┐  │              │  ┌────────┴──────────┐   │  │
│  │  │   Redis    │  │              │  │   KAgent Pods     │   │  │
│  │  └────────────┘  │              │  │   (AI Agents)     │   │  │
│  └──────────────────┘              │  └───────────────────┘   │  │
│                                     └─────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
                         gRPC Stream
                    (Outbound Connection Only)
```

### Network Architecture

```
Backend (Self-Hosted)                 Kubernetes Cluster
─────────────────────                 ──────────────────

┌─────────────────┐                   ┌─────────────────┐
│   gRPC Server   │                   │    Relayer     │
│   Port: 50051   │                   │                 │
│                 │◄──────────────────│  Initiates      │
│   Listening     │   Outbound gRPC   │  Connection     │
│                 │                   │                 │
└─────────────────┘                   └─────────────────┘
        │                                      │
        │                                      │
        ▼                                      ▼
┌─────────────────┐                   ┌─────────────────┐
│   Validates     │                   │   Maintains     │
│   Credentials   │                   │   Stream        │
│   (cluster_id   │                   │   Reconnects    │
│   + token)      │                   │   on Failure    │
└─────────────────┘                   └─────────────────┘

Firewall Rules Required:
Backend Side: LISTEN on 50051 (gRPC)
Cluster Side: NONE (outbound only, automatically allowed)
```

---

## Component Details

### 1. Relayer (Main Component)

**Technology:** Node.js with Fastify framework  
**Language:** JavaScript/TypeScript  
**Protocol:** gRPC (client)

**Responsibilities:**
- Establish outbound gRPC stream to backend
- Maintain connection with keepalive
- Handle reconnection with exponential backoff
- Execute commands received from backend
- Send events to backend
- Export telemetry to OTEL Collector

**Key Features:**
- **Circuit Breaker**: Prevents cascade failures
- **Reconnection Logic**: Exponential backoff with jitter
- **Health Checks**: Liveness, readiness, startup probes
- **Graceful Shutdown**: Waits for in-flight requests

**Configuration:**
```yaml
# Key environment variables
GRPC_ENDPOINT: "grpc://backend.company.com:50051"
CLUSTER_ID: "cls_abc123"  # From secret
CLUSTER_TOKEN: "..."       # From secret
GRPC_KEEPALIVE_TIME: "30"
GRPC_KEEPALIVE_TIMEOUT: "10"
```

### 2. OpenTelemetry Collector

**Technology:** OpenTelemetry Collector Contrib  
**Deployment:** DaemonSet (one per node) or Deployment  
**Protocol:** OTLP gRPC (port 4317)

**Responsibilities:**
- Receive telemetry from KAgent and other agents
- Buffer telemetry locally
- Process (filter, transform, enrich)
- Forward to backend or external systems

**Architecture Benefits:**
- **Decoupling**: Agents don't need to know backend details
- **Reliability**: Local buffering survives backend outages
- **Flexibility**: Can forward to multiple backends
- **Performance**: Batching and compression reduce overhead

**Configuration:**
```yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: "0.0.0.0:4317"

processors:
  batch:
    timeout: 10s
  memory_limiter:
    limit_mib: 512

exporters:
  logging:
    loglevel: info
  # Future: Forward to backend
  # otlphttp:
  #   endpoint: "https://backend/telemetry"
```

### 3. Pre-Install Registration Hook

**Technology:** Kubernetes Job with kubectl  
**Trigger:** Helm pre-install, pre-upgrade  
**Purpose:** Register cluster with backend

**Process:**
1. Read bearer token from values or existing secret
2. Call `POST /api/v1/clusters` on backend
3. Receive `cluster_id` and `cluster_token` in response
4. Create Kubernetes Secret with credentials
5. Exit successfully

**Security:**
- Bearer token used ONE TIME only
- Bearer token NOT stored in cluster
- Cluster credentials (id + token) stored for runtime
- Hook runs with elevated permissions (create secrets)
- Hook service account deleted after success

---

## Authentication Flow

### Registration Phase (Pre-Install)

```
┌─────────┐                                           ┌─────────┐
│  User   │                                           │ Backend │
└────┬────┘                                           └────┬────┘
     │                                                      │
     │ 1. Generate bearer token                            │
     │    openssl rand -base64 48                          │
     │                                                      │
     │ 2. helm install --set auth.bearerToken=TOKEN        │
     │                                                      │
     │                  ┌──────────────┐                   │
     │                  │ Pre-Install  │                   │
     │                  │     Hook     │                   │
     │                  └──────┬───────┘                   │
     │                         │                           │
     │                         │ 3. POST /api/v1/clusters  │
     │                         │    Authorization: Bearer  │
     │                         │    TOKEN                  │
     │                         ├──────────────────────────►│
     │                         │                           │
     │                         │                      4. Validate
     │                         │                         token
     │                         │                           │
     │                         │ 5. Return credentials     │
     │                         │    {                      │
     │                         │      id: "cls_abc123",    │
     │                         │      token: "..."         │
     │                         │    }                      │
     │                         │◄──────────────────────────┤
     │                         │                           │
     │                    6. Create                        │
     │                    K8s Secret                       │
     │                    - clusterId                      │
     │                    - clusterToken                   │
     │                         │                           │
     │                    7. Exit                          │
     │                    Success                          │
     │                         │                           │
```

**Key Points:**
- Bearer token is **ONE-TIME USE**
- Bearer token is **NOT stored** in cluster
- Cluster credentials are **long-lived**
- Registration is **idempotent** (can be run multiple times)

### Runtime Phase (Relayer)

```
┌──────────┐                                         ┌─────────┐
│ Relayer │                                         │ Backend │
└────┬─────┘                                         └────┬────┘
     │                                                     │
     │ 1. Read cluster credentials from secret            │
     │    - clusterId                                     │
     │    - clusterToken                                  │
     │                                                     │
     │ 2. Open gRPC stream                                │
     │    OpenCommandStream()                             │
     │    Metadata: cluster_id, cluster_token             │
     ├────────────────────────────────────────────────────►│
     │                                                     │
     │                                            3. Validate
     │                                               credentials
     │                                                     │
     │ 4. Stream accepted                                 │
     │◄────────────────────────────────────────────────────┤
     │                                                     │
     │ 5. Send initial handshake                          │
     │    StreamInit {                                    │
     │      cluster_id, version, capabilities             │
     │    }                                               │
     ├────────────────────────────────────────────────────►│
     │                                                     │
     │                                             6. Store
     │                                                session
     │                                                     │
     │ 7. Connection established                          │
     │    (bidirectional streaming)                       │
     │◄───────────────────────────────────────────────────►│
     │                                                     │
```

**Key Points:**
- Cluster credentials used for ALL runtime communication
- Credentials validated on EVERY request
- No need to re-register on reconnect
- Session maintained until disconnect

---

## Connection Lifecycle

### 1. Startup Sequence

```
Relayer Pod Start
       │
       ▼
Load Configuration
(ConfigMap)
       │
       ▼
Wait for Credentials
(Init Container)
       │
       ▼
Read Credentials
(cluster_id, cluster_token)
       │
       ▼
Establish gRPC Stream
       │
       ├─── Success ───►  Send Handshake
       │                        │
       │                        ▼
       │                  Enter Main Loop
       │                  (send/receive)
       │
       └─── Failure ───►  Circuit Breaker Check
                                │
                                ├─── Open ───► Wait & Retry
                                │
                                └─── Closed ──► Retry
```

### 2. Main Event Loop

```
┌─────────────────────────────────────────┐
│         Main Event Loop                  │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │  Listen for Backend Commands       │ │
│  │  (on gRPC stream)                  │ │
│  └────────┬───────────────────────────┘ │
│           │                              │
│           ▼                              │
│  ┌────────────────────────────────────┐ │
│  │  Execute Command                   │ │
│  │  - Validate                        │ │
│  │  - Execute                         │ │
│  │  - Capture output                  │ │
│  └────────┬───────────────────────────┘ │
│           │                              │
│           ▼                              │
│  ┌────────────────────────────────────┐ │
│  │  Send Result to Backend            │ │
│  │  (on same gRPC stream)             │ │
│  └────────────────────────────────────┘ │
│           │                              │
│           ▼                              │
│  ┌────────────────────────────────────┐ │
│  │  Send Events (if any)              │ │
│  │  - Health status                   │ │
│  │  - Telemetry metrics               │ │
│  └────────────────────────────────────┘ │
│           │                              │
│           └────────► Loop                │
└─────────────────────────────────────────┘
```

### 3. Reconnection Logic

**Exponential Backoff with Jitter:**

```python
def calculate_delay(attempt):
    base_delay = INITIAL_DELAY  # 1000ms
    max_delay = MAX_DELAY        # 30000ms
    multiplier = MULTIPLIER      # 2.0
    jitter_factor = JITTER       # 0.25
    
    # Exponential backoff
    delay = min(max_delay, base_delay * (multiplier ** attempt))
    
    # Add jitter (±25%)
    jitter = delay * jitter_factor * (random() * 2 - 1)
    final_delay = max(0, delay + jitter)
    
    return final_delay

# Example sequence:
# Attempt 1: ~1000ms   (1s)
# Attempt 2: ~2000ms   (2s)
# Attempt 3: ~4000ms   (4s)
# Attempt 4: ~8000ms   (8s)
# Attempt 5: ~16000ms  (16s)
# Attempt 6: ~30000ms  (30s, capped)
# Attempt 7+: ~30000ms (stays at cap)
```

**Circuit Breaker State Machine:**

```
┌──────────┐
│  CLOSED  │  ◄─── Normal operation
└────┬─────┘
     │
     │ 5 consecutive failures
     │
     ▼
┌──────────┐
│   OPEN   │  ◄─── Stop attempting connections
└────┬─────┘       (wait timeout period)
     │
     │ Timeout expires (60s)
     │
     ▼
┌──────────┐
│ HALF-OPEN│  ◄─── Try one connection
└────┬─────┘
     │
     ├─── Success ───► CLOSED
     │
     └─── Failure ───► OPEN
```

### 4. Graceful Shutdown

```
SIGTERM Received
       │
       ▼
Stop Accepting New Commands
       │
       ▼
Wait for In-Flight Commands
(max 10 seconds)
       │
       ▼
Send Final Events to Backend
       │
       ▼
Close gRPC Stream Gracefully
       │
       ▼
Flush OTEL Data
       │
       ▼
Exit with Status 0
```

---

## Data Flow

### Telemetry Collection Flow

```
┌──────────────┐
│   KAgent     │
│   (AI Agent) │
└──────┬───────┘
       │
       │ OTLP/gRPC
       │ (port 4317)
       ▼
┌──────────────┐
│     OTEL     │
│  Collector   │
│ (DaemonSet)  │
└──────┬───────┘
       │
       │ Local Processing:
       │ - Batching
       │ - Filtering
       │ - Enrichment
       │
       ▼
┌──────────────┐
│   Relayer   │
│              │
└──────┬───────┘
       │
       │ gRPC Stream
       │ (includes OTEL data)
       ▼
┌──────────────┐
│   Backend    │
│              │
└──────┬───────┘
       │
       │ Store & Process
       ▼
┌──────────────┐
│  PostgreSQL  │
│   Database   │
└──────────────┘
```

### Command Execution Flow

```
┌──────────────┐
│   Backend    │
│              │
└──────┬───────┘
       │
       │ gRPC Stream
       │ Command {
       │   id, type, payload
       │ }
       ▼
┌──────────────┐
│   Relayer   │
│              │
└──────┬───────┘
       │
       │ 1. Validate command
       │ 2. Check permissions
       │ 3. Execute via K8s API
       │
       ▼
┌──────────────┐
│  Kubernetes  │
│     API      │
└──────┬───────┘
       │
       │ Result
       ▼
┌──────────────┐
│   Relayer   │
│              │
└──────┬───────┘
       │
       │ gRPC Stream
       │ CommandResult {
       │   id, status, output
       │ }
       ▼
┌──────────────┐
│   Backend    │
│              │
└──────────────┘
```

---

## Security Model

### Defense in Depth

```
┌─────────────────────────────────────────────┐
│          Layer 1: Network                    │
│  - Outbound-only connections                 │
│  - NetworkPolicy egress restrictions         │
│  - No inbound firewall rules needed          │
└─────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│          Layer 2: Transport                  │
│  - TLS encryption (gRPC over TLS)            │
│  - Certificate validation                    │
│  - Keepalive prevents idle closure           │
└─────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│       Layer 3: Authentication                │
│  - Bearer token (registration only)          │
│  - Cluster credentials (runtime)             │
│  - Token rotation supported                  │
└─────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│        Layer 4: Authorization                │
│  - RBAC for Kubernetes API access            │
│  - Namespace-scoped permissions              │
│  - Read-only for most operations             │
└─────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│         Layer 5: Container                   │
│  - Non-root containers (UID 1000)            │
│  - Read-only root filesystem                 │
│  - Drop all capabilities                     │
│  - Seccomp profile enforced                  │
└─────────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────┐
│          Layer 6: Secrets                    │
│  - Kubernetes Secrets (encrypted at rest)    │
│  - External Secrets Operator support         │
│  - No secrets in environment variables       │
└─────────────────────────────────────────────┘
```

### Trust Boundaries

```
┌────────────────────────────────────────────┐
│           Trusted Zone                      │
│  ┌──────────────┐    ┌──────────────┐      │
│  │   Backend    │    │  PostgreSQL  │      │
│  │   Server     │────│   Database   │      │
│  └──────┬───────┘    └──────────────┘      │
│         │                                   │
└─────────┼───────────────────────────────────┘
          │ gRPC/TLS
          │ Authenticated
          │
┌─────────┼───────────────────────────────────┐
│         │        Semi-Trusted Zone          │
│  ┌──────▼───────┐                           │
│  │   Relayer   │                           │
│  │    (Pod)     │                           │
│  └──────┬───────┘                           │
│         │                                   │
│         │ RBAC-Controlled                   │
│         │                                   │
│  ┌──────▼────────────────┐                 │
│  │   Kubernetes API      │                 │
│  └───────────────────────┘                 │
│                                             │
└─────────────────────────────────────────────┘
```

---

## Failure Modes

### 1. Backend Unreachable

**Symptoms:**
- Relayer cannot establish gRPC connection
- Health check shows `"connected": false`

**Behavior:**
1. Circuit breaker opens after 5 failures
2. Stop connection attempts for 60 seconds
3. After timeout, attempt one connection (half-open)
4. If successful, close circuit; if failed, reopen

**Impact:**
- Commands cannot be executed
- Events cannot be sent
- Telemetry buffered locally by OTEL Collector
- No cluster impact (agents continue running)

**Recovery:**
- Automatic when backend becomes available
- No manual intervention required

### 2. Network Partition

**Symptoms:**
- Established gRPC stream breaks
- Keepalive fails

**Behavior:**
1. Detect stream failure immediately
2. Wait initial delay (1s) with jitter
3. Attempt reconnection
4. If failed, exponential backoff (2s, 4s, 8s, ...)
5. Cap at max delay (30s)

**Impact:**
- Same as Backend Unreachable
- OTEL Collector continues buffering

**Recovery:**
- Automatic when network restored
- Uses same cluster credentials (no re-registration)

### 3. Relayer Pod Crash

**Symptoms:**
- Pod restart
- New gRPC connection established

**Behavior:**
1. Init container waits for credentials secret
2. New pod reads same cluster credentials
3. Establishes new gRPC stream
4. Backend associates new stream with cluster

**Impact:**
- Brief interruption (typically < 10s)
- In-flight commands may be lost
- Backend handles cleanup of old stream

**Recovery:**
- Automatic via Kubernetes restart policy
- No data loss due to OTEL Collector buffering

### 4. Credentials Invalid

**Symptoms:**
- gRPC connection rejected (401 Unauthorized)
- All attempts fail immediately

**Behavior:**
1. Circuit breaker opens
2. Logs error with clear message
3. Pod enters `CrashLoopBackoff`

**Impact:**
- Cluster disconnected
- Manual intervention required

**Recovery:**
1. Verify credentials in backend database
2. If needed, delete cluster credentials secret
3. Helm upgrade triggers re-registration
4. New credentials created automatically

---

## Conclusion

This architecture provides:

✅ **Simplicity**: Single outbound gRPC connection  
✅ **Security**: Multiple layers of defense  
✅ **Reliability**: Circuit breaker, reconnection, buffering  
✅ **Observability**: Complete telemetry via OTEL  
✅ **Flexibility**: Works in any network environment  

For operational procedures, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).  
For security details, see [SECURITY.md](SECURITY.md).