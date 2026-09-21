# Octolet

GitOps-managed observability and networking stack for a 5-node Raspberry Pi K3s cluster.

## Cluster

| Node | Role | Notes |
|------|------|-------|
| Node 1 (octolet-control-1) | Control plane | Ubuntu Desktop + touchscreen monitor |
| Node 2 (octolet-control-2) | Control plane | |
| Node 3 (octolet-control-3) | Control plane | |
| Node 4 (octolet-worker-1) | Worker | |
| Node 5 (octolet-worker-2) | Worker | |

## Stack

| Component | Endpoint | Access |
|-----------|----------|--------|
| Grafana | `grafana.octolet.int` (Traefik) / `grafana-jwt.octolet.int` (Gateway) | Password or JWT auto-login |
| Prometheus | `prometheus.octolet.int` | Traefik ingress |
| AlertManager | `alertmanager.octolet.int` | Traefik ingress |
| Loki | in-cluster only | Via Grafana datasource |
| Tempo | in-cluster only | Via Grafana datasource |
| Alloy | DaemonSet (5 nodes) | Logs → Loki, traces → Tempo |
| Homepage | `homepage.octolet.int` | Service dashboard |
| ArgoCD | `argocd.octolet.int` (Traefik) / `argocd-gw.octolet.int` (Gateway) | Password or anonymous read-only |
| Twingate Gateway | `api-k8s.octolet.int`, `ssh.octolet.int`, `app.int` | K8s API, SSH, WebApp proxy |

## Architecture

See [docs/architecture.md](docs/architecture.md) for the full architecture documentation.

```
apps/
├── observability/     Prometheus, Grafana, Loki, Tempo, Alloy, Alerts
├── networking/        Twingate Operator + Gateway + Connectors
├── platform/          Homepage dashboard
├── twindemo/          httpbin, sshd, Grafana JWT/Basic, ArgoCD proxy
└── hardware/          (Phase 2: BlinkStick USB LEDs)

common/
├── dashboards/        Grafana dashboard JSON (auto-imported via sidecar)
└── alerts/            PrometheusRule CRDs (cluster + Twingate)

appconfig/             ArgoCD ApplicationSet + AppProject (bootstrap)
docs/                  Architecture, handoff prompt
```

Each `apps/<category>/<app>/` directory is auto-discovered by the ArgoCD ApplicationSet and deployed as an independent Application.

## Quickstart

Prerequisites: ArgoCD running on the cluster, `kubectl` configured, [go-task](https://taskfile.dev) installed.

```bash
# 1. Create required secrets
task secrets:create-all

# 2. Bootstrap ArgoCD (one-time)
task bootstrap

# 3. Watch applications sync
task status
```

## Twingate Demo Resources

| Resource | Type | Endpoint | Auth Method |
|----------|------|----------|-------------|
| httpbin | WebApp | `app.int` | JWT (`Authorization: Bearer`) |
| Grafana JWT | WebApp | `grafana-jwt.octolet.int` | JWT (`X-JWT-Assertion`) — auto-login |
| Grafana Basic | Network | `grafana-basic.octolet.int` | Username/password |
| SSH Server | SSH | `ssh.octolet.int` | Certificate (CA-signed, short-lived) |
| ArgoCD | WebApp | `argocd-gw.octolet.int` | Anonymous read-only (Gateway enforces Twingate auth) |
| K8s API | Kubernetes | `api-k8s.octolet.int` | RBAC (Admins → cluster-admin) |

## Documentation

- [CLAUDE.md](CLAUDE.md) — Architecture decisions, naming conventions, label taxonomy, patterns
- [docs/architecture.md](docs/architecture.md) — Full architecture documentation with data flow diagrams
- [docs/handoff-prompt.md](docs/handoff-prompt.md) — Session handoff for new Claude Code sessions
- [TODO.md](TODO.md) — Phase 2 items (ESO, Pyroscope, Grafana Kiosk, BlinkStick, Longhorn)
