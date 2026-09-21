# Architecture

## Cluster Hardware

| Node | Hostname | Role | Notes |
|------|----------|------|-------|
| 1 | octolet-control-1 | Control plane | Ubuntu Desktop + touchscreen monitor |
| 2 | octolet-control-2 | Control plane | |
| 3 | octolet-control-3 | Control plane | |
| 4 | octolet-worker-1 | Worker | |
| 5 | octolet-worker-2 | Worker | |

All nodes are Raspberry Pi (ARM64) running K3s. Storage uses the local-path provisioner (K3s default), with Longhorn distributed storage planned for Phase 2.

## Network Topology

```
Internet
    │
    ▼
Twingate Cloud ◄──── Twingate Client (user device)
    │
    ▼
┌─────────────────────────────────────────────────┐
│              Octolet Pi Cluster                  │
│                                                  │
│  Traefik Ingress (*.octolet.int)                │
│  ├── grafana.octolet.int    → Grafana :80       │
│  ├── prometheus.octolet.int → Prometheus :9090   │
│  ├── alertmanager.octolet.int → AlertManager     │
│  ├── homepage.octolet.int   → Homepage :3000     │
│  └── argocd.octolet.int    → ArgoCD :443        │
│                                                  │
│  Twingate Gateway (L7 proxy, *.int aliases)      │
│  ├── api-k8s.octolet.int   → K8s API (kubectl)  │
│  ├── grafana-jwt.octolet.int → Grafana (JWT SSO)│
│  ├── argocd-gw.octolet.int → ArgoCD (read-only) │
│  ├── app.int               → httpbin (JWT)       │
│  └── ssh.octolet.int       → sshd (cert auth)   │
│                                                  │
│  Twingate Connectors (2x, L4 tunnel)             │
│  ├── grafana-basic.octolet.int → Grafana (basic)│
│  └── (any Network-type resource)                 │
│                                                  │
└─────────────────────────────────────────────────┘
```

**Two access paths:**
- **Traefik ingress** (`*.octolet.int`) — Direct HTTP access for users on the network. Standard browser access with authentication at the application level.
- **Twingate Gateway** (L7 proxy, `*.int` aliases) — Zero-trust access via Twingate Client. Gateway handles auth, injects JWT headers for WebApp resources, signs SSH certificates for SSH resources.
- **Twingate Connectors** (L4 tunnel) — Network-type resources accessed via Twingate Client. No header injection, just encrypted tunnel to the service.

## Observability Stack (LGTMP)

| Signal | Component | Chart | Version | Mode |
|--------|-----------|-------|---------|------|
| Metrics | kube-prometheus-stack | `prometheus-community/kube-prometheus-stack` | 91.4.1 | Standard |
| Visualization | Grafana | `grafana/grafana` | 10.5.15 | Standalone, JWT auth |
| Logs | Loki | `grafana/loki` | 7.3.0 | SingleBinary (monolithic) |
| Traces | Tempo | `grafana/tempo` | 1.24.4 | Monolithic |
| Collection | Grafana Alloy | `grafana/alloy` | 1.12.1 | DaemonSet (single-tier) |

### Data Flow

```
┌─────────────────────────────────────────────────────┐
│            Grafana Alloy DaemonSet (5 nodes)         │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────┐ │
│  │ Pod logs     │  │ OTLP traces  │  │ Self-      │ │
│  │ /var/log/pods│  │ :4317/:4318  │  │ metrics    │ │
│  └──────┬──────┘  └──────┬───────┘  └─────┬──────┘ │
└─────────┼────────────────┼─────────────────┼────────┘
          ▼                ▼                 ▼
    ┌──────────┐    ┌──────────┐    ┌──────────────┐
    │   Loki   │    │  Tempo   │    │  Prometheus  │
    │ (mono)   │    │ (mono)   │    │  (scrapes    │
    │ 14d ret. │    │ 7d ret.  │    │   via SvcMon)│
    └────┬─────┘    └────┬─────┘    │  15d ret.    │
         │               │          └──────┬───────┘
         │               │                 │
         │    Tempo metrics generator ──►  │
         │    (RED metrics from traces)    │
         │                                 │
    ┌────▼─────────────────────────────────▼───────┐
    │                  Grafana                       │
    │  Datasources (cross-linked):                   │
    │  • Prometheus → exemplar traceID → Tempo       │
    │  • Loki → derived field traceID → Tempo        │
    │  • Tempo → traces-to-logs → Loki               │
    │  • Tempo → service map → Prometheus             │
    └──────────────────────────────────────────────┘
```

### What Prometheus Scrapes

| Target | Source | Metrics |
|--------|--------|---------|
| node-exporter (5 DaemonSet pods) | kube-prometheus-stack | Host CPU, memory, disk, network, filesystem |
| kube-state-metrics | kube-prometheus-stack | K8s object state (pods, deployments, nodes) |
| Twingate Gateway :9090 | ServiceMonitor (via chart) | HTTP requests, TCP connections, API server, auth, sessions (28 metrics) |
| Alloy :12345 | ServiceMonitor | Alloy pipeline metrics (self-monitoring) |
| Loki | ServiceMonitor | Loki internal metrics |
| Tempo | ServiceMonitor | Tempo internal metrics |
| Tempo metrics generator | Remote-write to Prometheus | RED metrics derived from traces |

### What Alloy Collects

| Signal | Source | Destination |
|--------|--------|-------------|
| Pod logs | `/var/log/pods/` on each node | Loki (`loki.monitoring:3100`) |
| Traces | OTLP gRPC/HTTP (:4317/:4318) | Tempo (`tempo.monitoring:4317`) |
| Self-metrics | localhost:12345 | Prometheus (remote-write) |

## Twingate Deployment

| Component | Namespace | Chart | Details |
|-----------|-----------|-------|---------|
| Operator | twingate | `oci://ghcr.io/twingate/helmcharts/twingate-operator` v2.0.2 | Kopf-based, watches CRDs, JSON logs |
| Gateway | twingate | Subchart of operator (`gateway` v1.1.0) | K8s API proxy, SSH (cert-based), WebApp (JWT) |
| Connectors | twingate | TwingateConnector CRs | 2x (`prem-tejon-octolet-twop-1/2`), logAnalytics enabled |

### Demo Resources

| Resource | Type | Access Path | Auth |
|----------|------|-------------|------|
| httpbin | WebApp | `app.int` via Gateway | JWT (`Authorization: Bearer {{jwt}}`) |
| Grafana JWT | WebApp | `grafana-jwt.octolet.int` via Gateway | JWT (`X-JWT-Assertion: {{jwt}}`) |
| Grafana Basic | Network | `grafana-basic.octolet.int` via Connector | Username/password |
| SSH Server | SSH | `ssh.octolet.int` via Gateway | Certificate (CA-signed, short-lived) |
| ArgoCD | WebApp | `argocd-gw.octolet.int` via Gateway | Anonymous read-only (Gateway enforces Twingate auth) |
| K8s API | Kubernetes | `api-k8s.octolet.int` via Gateway | RBAC (Admins → cluster-admin) |

## ArgoCD Pattern

```
ApplicationSet (appconfig/applicationset.yaml)
  └── Git directory generator: scans apps/*/*
      └── Creates parent Application per directory
          └── Parent syncs directory via Kustomize
              └── Applies inner Application CRD + extra manifests
                  └── Inner Application deploys Helm chart with $values ref
```

| App Layer | Example | Naming |
|-----------|---------|--------|
| Parent (from ApplicationSet) | `prometheus`, `grafana`, `twingate` | Directory basename |
| Inner (from application.yaml) | `prometheus-stack`, `grafana-stack`, `twingate-operator` | `<component>-stack` to avoid collision |

## Alert Rules

### Cluster Alerts (`common/alerts/cluster-alerts.yaml`)
- `NodeNotReady` — Node not ready >5m (critical)
- `PodCrashLoopBackOff` — Pod restarting >5 times/hour for >10m (warning)
- `PVCNearlyFull` — PVC >85% used (critical — Pi storage constraint)
- `KubePodNotReady` — Pod not ready >15m (warning)

### Twingate Alerts (`common/alerts/twingate-alerts.yaml`)
- `TwingateConnectorDown` — <2 connectors running >5m (critical)
- `TwingateOperatorDown` — Operator pod missing >5m (critical)
- Gateway alerts (built-in via chart): HTTP error rate, API server error rate, auth failures

### Recording Rules
- `twingate:gateway_http_error_rate:5m`
- `twingate:gateway_request_rate:5m`
- `twingate:gateway_active_connections`

## Storage Strategy

**Current:** local-path provisioner (K3s default). Data lives on each node's SSD/SD card. Not replicated — a node failure loses that node's PVC data.

**Retention** (tuned for Pi storage):
- Prometheus: 15 days
- Loki: 14 days
- Tempo: 7 days

**Planned (Phase 2):** Longhorn distributed storage for volume replication across nodes.
