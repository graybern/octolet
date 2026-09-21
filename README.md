# Octolet

GitOps-managed observability and networking stack for a 5-node Raspberry Pi K3s cluster.

## Cluster

| Node | Role | Notes |
|------|------|-------|
| Node 1 | Control plane | Ubuntu Desktop + touchscreen monitor |
| Node 2 | Control plane | |
| Node 3 | Control plane | |
| Node 4 | Worker | |
| Node 5 | Worker | |

## Stack

| Signal | Component | Endpoint |
|--------|-----------|----------|
| Metrics | Prometheus (kube-prometheus-stack) | `prometheus.octolet.int` |
| Logs | Loki (monolithic) | in-cluster only |
| Traces | Tempo (monolithic) | in-cluster only |
| Visualization | Grafana | `grafana.octolet.int` |
| Collection | Grafana Alloy (DaemonSet) | — |
| Alerts | AlertManager | `alertmanager.octolet.int` |
| Networking | Twingate Operator + Gateway | — |
| GitOps | ArgoCD | `argocd.octolet.int` |

## Architecture

```
apps/
├── observability/     Prometheus, Grafana, Loki, Tempo, Alloy
├── networking/        Twingate Operator + Gateway + Connectors
├── platform/          (Phase 2: ESO, Grafana Kiosk)
├── twindemo/          httpbin demo app
└── hardware/          (Phase 2: BlinkStick USB LEDs)

common/
├── dashboards/        Grafana dashboard JSON (auto-imported via sidecar)
└── alerts/            PrometheusRule CRDs

appconfig/             ArgoCD ApplicationSet + AppProject (bootstrap)
```

Each `apps/<category>/<app>/` directory is auto-discovered by the ArgoCD ApplicationSet and deployed as an independent Application.

## Quickstart

Prerequisites: ArgoCD running on the cluster, `kubectl` configured.

```bash
# 1. Create required secrets
task secrets:create-all

# 2. Bootstrap ArgoCD (one-time)
task bootstrap

# 3. Watch applications sync
task status
```

## Twingate

The Twingate Operator manages Connectors and a Gateway pod:

- **Gateway**: K8s API proxy (`api-k8s.octolet.int`), SSH, WebApp proxying. Exposes Prometheus metrics on `:9090`.
- **Connectors**: 2x connectors (`prem-tejon-octolet-twop-1/2`) for the `gbernard` network.
- **Monitoring**: Gateway metrics scraped by Prometheus via ServiceMonitor. Connector L4 logs collected by Alloy → Loki.

## Phase 2

See [TODO.md](TODO.md) for planned additions: External Secrets Operator, Pyroscope profiling, Grafana Kiosk for the touchscreen, BlinkStick USB LED indicators, Longhorn distributed storage, and more.
