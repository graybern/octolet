# Phase 2 — TODO

Tracked items for future implementation. Each becomes an `apps/` directory when ready.

## Secrets Management

- [ ] **External Secrets Operator** — `apps/platform/external-secrets/`
  - Deploy ESO via Helm chart from `https://charts.external-secrets.io`
  - Create ClusterSecretStore (`apps/platform/external-secrets-config/`) pointing to Vault
  - Migrate Twingate API key from manual K8s Secret to ExternalSecret
  - Follow homelab-ops pattern: `http://vault.vault.svc.cluster.local:8200`, K8s auth, `eso-reader` role

## Observability

- [ ] **Pyroscope** — `apps/observability/pyroscope/`
  - Continuous profiling (CPU, memory, goroutines) for all cluster workloads
  - Monolithic mode, Grafana Alloy scrapes profiles via `prometheus.exporter.pyroscope`
  - Chart: `grafana/pyroscope` — ARM64 confirmed

- [x] **Alloy Twingate log pipeline** — ✅ `stage.match` in `loki.process` extracts `event_type`, `connector_name`, `connection_protocol` as Loki labels. High-cardinality fields stay in log line for `| json` query-time extraction.

- [x] **Custom dashboards** — ✅ Deployed via `apps/observability/dashboards/` (ArgoCD-managed)
  - Cluster Overview (9 panels: node status, CPU/mem/disk, pod health, alerts, temperature, top pods)
  - Touchscreen Summary (11 panels: node tiles, gauges, Twingate connections, BlinkStick status)
  - Twingate Connector L4 (10 panels: connections/sec, protocol, resources, traffic, duration, bytes)
  - BlinkStick Controller (10 panels: nodes, ticks, overlays, MQTT, clock skew)

- [ ] **AlertManager routing** — Slack/Discord receivers for critical alerts
  - Requires: Slack incoming webhook URL + channel (create at api.slack.com → Incoming Webhooks)
  - Create manual K8s Secret with webhook URL on cluster
  - Update `alertmanager.config` in `apps/observability/prometheus/values.yaml`
  - Route `severity=critical` to dedicated receiver, `severity=warning` to general
  - Plan ready in `.claude/plans/` Phase 10

- [ ] **Alloy consolidation** — Evaluate replacing node-exporter with Alloy's built-in `prometheus.exporter.unix`
  - Reduces to one DaemonSet per node (from two)
  - Metric names are identical — dashboards still work
  - Trade-off: simpler topology vs single point of failure for all signals

## Storage

- [ ] **Longhorn** — `apps/storage/longhorn/`
  - Replace local-path provisioner with distributed replicated storage
  - Volumes survive node failure — critical for Prometheus/Loki/Tempo data durability
  - ARM64 support confirmed

## Touchscreen

- [ ] **Grafana Kiosk** — `apps/platform/grafana-kiosk/`
  - Install on Ubuntu Desktop control-plane node (Node 1)
  - ARM64 binary: `grafana-kiosk.linux.arm64`
  - Auto-rotating dashboards in fullscreen Chromium
  - Enable Grafana anonymous read-only auth: `grafana.ini.auth.anonymous.enabled: true`
  - Restrict anonymous access via NetworkPolicy to touchscreen node's IP only

## Hardware

- [x] **BlinkStick USB LED indicators** — ✅ Complete through Phase 4b
  - Agent DaemonSet + Mosquitto MQTT broker + Controller deployment
  - 7 background/foreground modes: status, direct, music, knight-rider, rainbow-wave, breathing, temperature
  - 3 event overlays: Twingate connection flash (Loki), ArgoCD deploy wave, AlertManager escalation
  - Split LED: LED 0 = background, LED 1 = overlay with priority queue
  - Web UI with overlay badge, mode selector, Settings event history
  - ServiceMonitor (`/api/v1/metrics`), PrometheusRule (3 alerts), Grafana dashboard
  - App code: `graybern/k8s-blinkstick` | K8s manifests: `apps/hardware/blinkstick/`

## Networking

- [ ] **Envoy Gateway (Gateway API)** — `apps/networking/envoy-gateway/`
  - K8s is moving from Ingress to Gateway API — Envoy Gateway is the reference implementation
  - Install as a separate `GatewayClass` alongside existing Traefik Ingress (completely isolated)
  - Traefik continues handling all `*.octolet.int` Ingress resources
  - New test services use `HTTPRoute` resources pointing to the Envoy `GatewayClass`
  - Both run side-by-side — no risk to existing setup
  - Chart: `oci://docker.io/envoyproxy/gateway-helm`
  - Alternative: enable Gateway API on existing Traefik v3 (less isolation, no new controller)
  - Deploy in `envoy-gateway-system` namespace

- [ ] **ArgoCD OIDC SSO** — Configure ArgoCD Dex with IdP (Google/Okta)
  - Full auto-login with user identity (not anonymous read-only)
  - Requires `argocd-cm` ConfigMap + Dex connector configuration
  - ArgoCD not yet managed by this repo — would need to be added or configured manually

## Reliability

- [x] **Health probes audit** — ✅ All custom deployments now have probes
  - sshd: startup + readiness + liveness (tcpSocket :2222)
  - homepage: startup + readiness + liveness (tcpSocket :3000)
  - blinkstick-controller: startup + readiness + liveness (httpGet /healthz, /readyz)
  - blinkstick-agent: skipped — DaemonSet restart + `BlinkStickAgentOffline` alert covers this
