# Handoff Prompt

Paste this into a new Claude Code session to continue development.

---

You are continuing work on octolet. It is a GitOps-managed observability and networking stack for a 5-node Raspberry Pi K3s cluster (ARM64), deployed via ArgoCD.

Tech stack: kube-prometheus-stack, Grafana (standalone with JWT auth), Loki (monolithic), Tempo (monolithic), Grafana Alloy (DaemonSet), Twingate Operator + Gateway, Homepage dashboard. Everything is Helm charts or Kustomize manifests managed by ArgoCD's ApplicationSet (app-of-apps pattern).

Key directories: apps/ (each apps/<category>/<app>/ is an ArgoCD Application), common/ (shared alert rules, dashboards), appconfig/ (ArgoCD bootstrap), docs/ (architecture, this file).

Read CLAUDE.md for full project context — architecture decisions, naming conventions, label taxonomy, patterns.
Read TODO.md for Phase 2 items (ESO, Pyroscope, Grafana Kiosk, BlinkStick, Longhorn).

Cluster details:
- 5 Raspberry Pi nodes: 3 control-plane (node 1 has Ubuntu Desktop + touchscreen), 2 workers
- K3s with Traefik ingress, `*.octolet.int` domain pattern
- Twingate network: `gbernard`, Gateway at `api-k8s.octolet.int`, 2 connectors
- ArgoCD at `argocd.octolet.int` (pre-deployed, not managed by this repo)
- All images must be ARM64 compatible. Conservative resource requests (Pi hardware).
- Storage: local-path provisioner. Longhorn planned for Phase 2.

Current state:
- Observability stack deployed and healthy (Prometheus, Grafana, Loki, Tempo, Alloy, AlertManager)
- Twingate Operator managed by ArgoCD (OCI chart v2.0.2)
- Demo apps: httpbin (WebApp JWT), sshd (SSH gateway), Grafana JWT/Basic
- Homepage dashboard at `homepage.octolet.int`
- Alert rules deployed (cluster + Twingate)
- Grafana has JWT auth enabled for access via Twingate Gateway

Begin by reading CLAUDE.md and TODO.md, then ask what to work on.

---

Generated on 2026-09-21.
