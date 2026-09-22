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

## Key Decisions

1. **Alloy over raw OTel Collector.** **Why:** Alloy IS an OpenTelemetry distribution with native Grafana integration, Prometheus scraping, Loki log shipping, and Pyroscope profiling built in. Single binary replaces Promtail + OTel Collector + Grafana Agent. **Trade-off:** Vendor lock-in to Grafana ecosystem; standard OTel Collector would be more portable.

2. **Monolithic Loki/Tempo.** **Why:** SimpleScalable is deprecated in Loki 4.0. Monolithic is recommended for clusters <50 nodes. Same rationale for Tempo. **Trade-off:** Can't scale read/write paths independently; sufficient for 5-node cluster.

3. **Standalone Grafana (not bundled in kube-prometheus-stack).** **Why:** Independent version pinning and upgrade path. The kps Grafana subchart consistently lags months behind standalone. JWT auth config is cleaner on standalone. **Trade-off:** One more ArgoCD Application to manage.

4. **Both node-exporter + Alloy DaemonSets.** **Why:** Failure isolation — node-exporter provides host metrics, Alloy collects logs + traces. If Alloy OOMs, metrics keep flowing. **Trade-off:** Two DaemonSets per node (~138MB vs ~150MB if consolidated). Consolidation tracked in TODO.md.

5. **Single-tier Alloy (no gateway tier).** **Why:** 5 nodes don't need centralized processing. DaemonSet agents push directly to backends. **Trade-off:** No tail-based trace sampling or cross-node aggregation; add gateway tier later if needed.

6. **App-of-apps with ApplicationSet.** **Why:** Auto-discovers apps from `apps/*/*` directory structure. Adding a new app = creating a directory. **Trade-off:** Inner Application names must differ from parent names (we use `-stack` suffix).

7. **Manual K8s Secrets (ESO planned for Phase 2).** **Why:** Simplest to start. No Vault or ESO dependency. **Trade-off:** Secrets aren't in git; must be created manually on each cluster rebuild.

8. **local-path storage (Longhorn planned for Phase 2).** **Why:** K3s default, zero setup. **Trade-off:** No replication — a node failure loses that node's PVC data.

9. **JWT auth on production Grafana (not separate demo instance).** **Why:** Avoids running two Grafana instances on Pi hardware. Password auth kept as fallback for direct Traefik access. **Trade-off:** JWT config is in the production Grafana values.

10. **ArgoCD anonymous read-only (no Gateway proxy).** **Why:** ArgoCD doesn't support header-based JWT auth. Anonymous read-only via Traefik is sufficient — Twingate controls network access to the cluster already. A Gateway proxy adds no value over Traefik here. **Trade-off:** No user identity in ArgoCD audit logs; write operations require CLI. OIDC SSO tracked in TODO.md.

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

## Label Taxonomy

| Label | Values | Purpose |
|-------|--------|---------|
| `octolet/layer` | `observability`, `networking`, `platform`, `twindemo`, `hardware` | App category (maps to `apps/` subdirectories) |
| `octolet/component` | `prometheus`, `loki`, `grafana`, `twingate`, `httpbin`, `sshd`, `homepage`, etc. | Specific component |
| `managed-by` | `argocd`, `helm`, `manual` | How the resource is deployed |
| `project` | `octolet` | Always `octolet` — for cost allocation and filtering |

## Naming Conventions

| Thing | Pattern | Example |
|-------|---------|---------|
| Helm releases | `<component>-stack` | `prometheus-stack`, `loki-stack`, `alloy-stack` |
| ArgoCD inner apps | `<component>-stack` | Avoids collision with parent app names from ApplicationSet |
| Ingress hostnames | `<component>.octolet.int` | `grafana.octolet.int`, `prometheus.octolet.int` |
| Twingate aliases | `<service>.octolet.int` or `<service>.int` | `grafana-jwt.octolet.int`, `app.int`, `ssh.octolet.int` |
| K8s Secrets | `<component>-<purpose>` | `twingate-operator-api-key`, `grafana-admin`, `twingate-ssh-ca` |
| Twingate resources | `"<Category> · <Name>"` | `"Demo · Grafana (JWT)"`, `"Demo · SSH Server"`, `"Infra · ArgoCD"` |
| Connectors | `prem-tejon-octolet-twop-<n>` | `prem-tejon-octolet-twop-1` |
| Namespaces | By function | `monitoring`, `twingate`, `default` (demos), `admin` (homepage), `argocd` |

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

### Operator CRD Drift (ignoreDifferences)

Kubernetes operators that write back to their own CRs (adding `spec.id`, `status`, finalizers) cause permanent ArgoCD OutOfSync drift — ArgoCD applies the template, the operator enriches the CR, ArgoCD sees the diff and marks it OutOfSync, repeat forever.

Fix: add `ignoreDifferences` to the ArgoCD Application:
```yaml
ignoreDifferences:
  - group: twingate.com
    kind: TwingateConnector
    jsonPointers:
      - /spec/id
      - /status
```
And `RespectIgnoreDifferences=true` in `syncOptions` so auto-sync also honors the ignore list.

This applies to any operator-managed CRD, not just Twingate. The pattern: ignore fields the operator owns (IDs, status, timestamps) and let ArgoCD own the spec fields you define in git.

### Gateway TLS Cert — Do Not Override Auto-Generation

The Twingate Gateway subchart auto-generates a self-signed TLS cert (`tls.autoGenerated.enabled: true` is the default). **Do not change this.** Specifically:

- **Never set `tls.existingSecret` + `autoGenerated.enabled: false`** — ArgoCD prunes the TLS Secret because the chart stops rendering it. The Gateway loses its cert and ALL connections fail (TLS handshake EOF on every connection).
- **Never set `tls.autoGenerated.enabled: false`** without first creating the Secret out-of-band and excluding it from ArgoCD prune.
- The chart regenerates the cert on upgrades. The Twingate cloud accepts the new cert after the Gateway re-registers on startup. Connectors may need a moment to reconnect.
- If the Gateway enters a TLS error loop after a cert change, kill the pods (`kubectl delete pod -l app.kubernetes.io/name=gateway -n twingate`) and let the Deployment recreate them with the fresh cert.

### Gateway Re-Registration After Recreation

When the TwingateGateway CR is deleted and recreated (e.g., after `helm uninstall` → ArgoCD redeploy), the operator tries `gatewayCreate` which may fail ("Gateway must have an SSH CA"). The existing gateway object in the Twingate cloud still exists. Fix: patch the CR with the existing cloud ID:
```bash
kubectl patch twingategateway twop-gateway -n twingate --type=json \
  -p '[{"op":"add","path":"/spec/id","value":"<GATEWAY_ID_FROM_CLOUD>"}]'
```
Find the ID via: `curl -s -X POST "$API_URL" -H "X-API-KEY: $TOKEN" -H "Content-Type: application/json" -d '{"query":"{ gateways { edges { node { id address } } } }"}'`

### Homepage Auto-Discovery (Ingress Annotations)

Services with Ingresses can auto-appear on the Homepage dashboard via annotations instead of manual `services.yaml` entries. Add to any Ingress:
```yaml
annotations:
  gethomepage.dev/enabled: "true"
  gethomepage.dev/name: "Grafana"
  gethomepage.dev/group: "Observability"
  gethomepage.dev/icon: "grafana.svg"
  gethomepage.dev/description: "Dashboards (JWT auto-login)"
```

Services without Ingresses (sshd, Twingate Gateway/Connectors) stay as manual entries in `services.yaml`. Mixed approach works fine.

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
- `twingate-ssh-ca` in namespace `twingate` — SSH CA key pair for Gateway cert signing (keys: `ssh-privatekey`, `ssh-publickey`)

### Pi Constraints

- **ARM64 only**: All container images must have ARM64 variants
- **Resources**: Conservative requests (Prometheus 512Mi, Loki 256Mi, Tempo 256Mi, Grafana 256Mi, Alloy 128Mi/node)
- **Retention**: Prometheus 15d, Loki 14d, Tempo 7d (SD card/SSD friendly)
- **Tolerations**: Alloy + node-exporter tolerate all NoSchedule taints (run on control-plane)
- **Scrape interval**: 30s (not 15s) to reduce CPU load

### Ingress

**Traefik ingress** (`*.octolet.int`, direct HTTP access):
- `grafana.octolet.int` — Grafana (password or JWT auth)
- `prometheus.octolet.int` — Prometheus
- `alertmanager.octolet.int` — AlertManager
- `homepage.octolet.int` — Homepage dashboard
- `argocd.octolet.int` — ArgoCD (password login)

**Twingate Gateway** (`*.octolet.int` / `*.int`, L7 proxy with JWT/SSH):
- `grafana-jwt.octolet.int` — Grafana (auto-login via JWT)
- `app.int` — httpbin (WebApp with JWT)
- `ssh.octolet.int` — sshd (SSH cert auth)
- `api-k8s.octolet.int` — K8s API (kubectl via Gateway)

**Twingate Connectors** (L4 tunnel, Network-type resources):
- `grafana-basic.octolet.int` — Grafana (password auth via tunnel)

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
task secrets:create-ssh-ca   # Generate SSH CA key pair for Gateway
```
