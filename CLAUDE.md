# Octolet — GitOps Observability for a Raspberry Pi K3s Cluster

## Cluster

- **Octolet**: 5-node Raspberry Pi K3s cluster (ARM64)
  - 3 control-plane nodes (one runs Ubuntu Desktop + touchscreen monitor)
  - 2 worker nodes
- **Ingress**: Traefik (K3s built-in), domain pattern `*.octolet.int`
- **GitOps**: ArgoCD at `argocd.octolet.int` (pre-deployed, not managed by this repo)
- **Storage**: local-path provisioner (K3s default). Longhorn planned for Phase 2.
- **Twingate**: Operator + Gateway + 2 Connectors in the `twingate` namespace

## Architecture

### Observability Stack (LGTMP)

| Signal | Component | Mode | Chart |
|--------|-----------|------|-------|
| Metrics | kube-prometheus-stack | Standard (includes node-exporter, kube-state-metrics, AlertManager) | `prometheus-community/kube-prometheus-stack` |
| Visualization | Grafana | Standalone (separate lifecycle from Prometheus) | `grafana/grafana` |
| Logs | Loki | Monolithic (`SingleBinary`) | `grafana/loki` |
| Traces | Tempo | Monolithic | `grafana/tempo` |
| Collection | Grafana Alloy | DaemonSet (single-tier) | `grafana/alloy` |

### Why These Choices

- **Alloy over raw OTel Collector**: Alloy IS an OpenTelemetry distribution with native Grafana integration, Prometheus scraping, Loki log shipping, and Pyroscope profiling built in. Single binary replaces Promtail + OTel Collector + Grafana Agent.
- **Monolithic Loki/Tempo**: SimpleScalable is deprecated in Loki 4.0. Monolithic is recommended for clusters <50 nodes. Same rationale for Tempo.
- **Standalone Grafana**: Decoupled from kube-prometheus-stack for independent version pinning and upgrade path. The kps Grafana subchart consistently lags behind.
- **node-exporter + Alloy (both DaemonSets)**: Kept separate for failure isolation. node-exporter provides host metrics; Alloy collects logs + traces. If Alloy OOMs, metrics keep flowing. Alloy CAN replace node-exporter via `prometheus.exporter.unix` — tracked in TODO.md.
- **Single-tier Alloy**: 5 nodes don't need a gateway tier. DaemonSet agents push directly to backends.

### Data Flow

```
Alloy DaemonSet (per node)
├── Pod logs → Loki
├── OTLP traces → Tempo
└── Self-metrics → Prometheus (remote-write)

Prometheus (scrapes via ServiceMonitors)
├── node-exporter (host metrics)
├── kube-state-metrics (K8s object metrics)
├── Gateway :9090 (Twingate L7/L4/API/Auth metrics)
└── Any ServiceMonitor-annotated workload

Tempo metrics-generator → Prometheus (remote-write, RED metrics from traces)

Grafana datasources (cross-linked):
├── Prometheus → exemplar traceID links to Tempo
├── Loki → derived field traceID links to Tempo
└── Tempo → traces-to-logs links to Loki, service map from Prometheus
```

### Twingate Monitoring

- **Gateway**: 28 Prometheus metrics on port 9090 (HTTP, TCP, K8s API, Auth, Sessions). Built-in ServiceMonitor, Grafana dashboard, and PrometheusRules — enabled in values.
- **Connectors**: No native metrics endpoint. Structured L4 connection logs via `logAnalytics: true` → collected by Alloy → query with LogQL in Grafana. Log-derived metrics via `rate()`/`count_over_time()`.
- **Operator**: Kopf-based Python operator. Set `logFormat: "json"` for structured logs.

## Repo Conventions

### Directory Layout

```
apps/<category>/<app>/     — Each leaf = one ArgoCD Application
common/<type>/             — Shared resources (dashboards, alert rules)
appconfig/                 — ArgoCD bootstrap (ApplicationSet + AppProject)
```

Categories: `observability`, `networking`, `platform`, `twindemo`, `hardware`

### Per-App Structure

Every app directory under `apps/` contains:
- `kustomization.yaml` — Lists files for the ApplicationSet to process
- `application.yaml` — Multi-source ArgoCD Application CRD (Helm chart from registry + values from git)
- `values.yaml` — Helm values overrides

Some apps have additional manifests (CRDs, Secrets, RBAC) listed in kustomization.yaml.

### ArgoCD Pattern (App-of-Apps)

```
ApplicationSet (appconfig/applicationset.yaml)
  └── scans apps/*/* via Git directory generator
      └── creates parent App per directory (directory.recurse: true)
          └── parent App applies Application CRD + extra manifests
              └── Application CRD deploys Helm chart with values from git
```

Multi-source Application template:
```yaml
sources:
  - repoURL: <helm-registry>
    chart: <chart-name>
    targetRevision: "<pinned-version>"
    helm:
      releaseName: <name>
      valueFiles:
        - $values/apps/<category>/<app>/values.yaml
  - repoURL: https://github.com/graybern/octolet
    targetRevision: HEAD
    ref: values
```

### Secrets

Manual Kubernetes Secrets for now. External Secrets Operator planned for Phase 2 (see TODO.md).

**Never commit secrets to this repo.** Use `existingSecretName` in Helm values to reference pre-created Secrets.

Current manual secrets:
- `twingate-operator-api-key` in namespace `twingate` — Twingate API key
- `grafana-admin` in namespace `monitoring` — Grafana admin username and password (keys: `admin-user`, `admin-password`)

### Pi Constraints

- **ARM64 only**: All container images must have ARM64 variants
- **Resources**: Conservative requests (Prometheus 512Mi, Loki 256Mi, Tempo 256Mi, Grafana 256Mi, Alloy 128Mi/node)
- **Retention**: Prometheus 15d, Loki 14d, Tempo 7d (SD card/SSD friendly)
- **Tolerations**: Alloy + node-exporter tolerate all NoSchedule taints (run on control-plane)
- **Scrape interval**: 30s (not 15s) to reduce CPU load

### Ingress

Traefik with `*.octolet.int` internal DNS:
- `grafana.octolet.int`
- `prometheus.octolet.int`
- `alertmanager.octolet.int`

Loki and Tempo are accessed in-cluster only (via Grafana datasources and Alloy). No external ingress needed.

### Common Directory

- `common/dashboards/` — Grafana dashboard JSON files deployed as ConfigMaps with `grafana_dashboard: "1"` label (sidecar auto-imports)
- `common/alerts/` — PrometheusRule CRDs for cluster and Twingate alerting

## Patterns from homelab-ops

This repo adapts proven patterns from `homelab-ops` (the parent GitOps monorepo):

| Pattern | homelab-ops Source | Adaptation |
|---------|-------------------|------------|
| Multi-source Applications | `1-scaffolding/monitoring-*` | Same, pointed at `graybern/octolet` |
| ApplicationSet directory generator | `2-playground/appconfig/` | Two-level scan: `apps/*/*` |
| Grafana datasource cross-linking | `1-scaffolding/monitoring-grafana/values.yaml` | Same Prometheus↔Loki↔Tempo correlation |
| Alloy River pipeline | `1-scaffolding/monitoring-alloy/values.yaml` | Same log/trace/metric pipelines |
| Prometheus remote-write receiver | `1-scaffolding/monitoring-prometheus/values.yaml` | For Tempo metrics generator |

Key difference: no `/environments/` — this repo targets a single cluster. `/common/` replaces the shared module pattern.

## Useful Commands

```bash
task bootstrap               # Apply appconfig/ to cluster (one-time)
task status                  # Show all ArgoCD application statuses
task validate                # Dry-run validate all YAML
task secrets:create-all      # Create all required secrets (interactive)
task secrets:create-twingate # Create Twingate API key secret
task secrets:create-grafana  # Create Grafana admin credentials
```
