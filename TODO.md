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

- [ ] **Alloy Twingate log pipeline** — Structured field extraction from Connector/Gateway logs
  - `loki.process "twingate"` with `stage.json`, `stage.labels`, `stage.metrics`
  - Promote fields: connector name, event type, connection duration, bytes transferred
  - Optional: derive Prometheus metrics from log lines

- [ ] **Custom dashboards** — `common/dashboards/`
  - Cluster overview (node CPU/mem/disk, pod health) for touchscreen
  - Twingate Connector L4 dashboard (LogQL-derived: connections/sec, bytes, unique clients)
  - Touchscreen summary (simplified view for kiosk rotation)

- [ ] **AlertManager routing** — Slack/Discord receivers for critical alerts

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

- [ ] **BlinkStick USB LED indicators** — `apps/hardware/blinkstick/`
  - Containerized BlinkStick controller as DaemonSet on each node
  - USB device access via `securityContext.privileged` + `hostPath` for `/dev/bus/usb`
  - Queries Prometheus API for node/cluster health
  - State-to-color mapping (ConfigMap):
    - Solid green: node healthy, all pods running
    - Pulsing blue: node under load (CPU/mem >70%)
    - Solid yellow: warning alerts firing on this node
    - Pulsing red: critical alerts or node NotReady
    - Rainbow/chase: cluster-wide event (deploy in progress)
  - Custom container: Python + `blinkstick` library + Prometheus client

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

- [ ] **Health probes audit** — Add startup/readiness/liveness probes to all custom deployments
  - Helm charts (Prometheus, Grafana, Loki, Tempo, Alloy) already have probes built in
  - Custom manifests need probes added:
    - `apps/twindemo/sshd/deployment.yaml` — exec probe: `ssh-keygen -l -f /etc/ssh/twingate_ca.pub`
    - `apps/platform/homepage/deployment.yaml` — HTTP probe: GET `:3000/api/healthcheck`
  - Document probe convention in CLAUDE.md: all custom deployments must include at least readiness + liveness
  - Consider startup probes for slow-starting containers (sshd installs packages at startup)
