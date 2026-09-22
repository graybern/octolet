# Handoff Prompt

Paste this into a new Claude Code session to continue development.

---

You are continuing work on octolet. It is a GitOps-managed observability and networking stack for a 5-node Raspberry Pi K3s cluster (ARM64), deployed via ArgoCD with an app-of-apps pattern via ApplicationSet.

Tech stack: kube-prometheus-stack, standalone Grafana (JWT auth), Loki (monolithic), Tempo (monolithic), Grafana Alloy (DaemonSet), Twingate Operator + Gateway, Homepage dashboard, Headlamp K8s dashboard, Wetty web SSH. Everything is Helm charts or Kustomize manifests managed by ArgoCD.

Key directories: apps/ (each apps/<category>/<app>/ is an ArgoCD Application), common/ (shared alert rules, dashboards), appconfig/ (ArgoCD bootstrap), docs/ (architecture, this file).

Read CLAUDE.md for full project context — architecture decisions, naming conventions, label taxonomy, patterns, current state, and operational pitfalls.
Read TODO.md for Phase 2 items (ESO, Pyroscope, Grafana Kiosk, BlinkStick, Longhorn, Envoy Gateway).

Cluster details:
- 5 Raspberry Pi nodes: 3 control-plane (node 1 has Ubuntu Desktop + touchscreen), 2 workers
- K3s with Traefik ingress, `*.octolet.int` domain pattern
- Twingate network: `gbernard`, Gateway at `api-k8s.octolet.int`, 2 connectors
- ArgoCD at `argocd.octolet.int` (anonymous read-only, not managed by this repo)
- All images must be ARM64 compatible. Conservative resource requests (Pi hardware).
- Storage: local-path provisioner. Longhorn planned for Phase 2.

Current state (2026-09-22):
- Full LGTMP observability stack deployed and healthy
- Twingate Operator fully ArgoCD-managed (OCI chart v2.0.2, old Helm release removed)
- Demo apps: sshd (Alpine, SSH cert auth via Gateway), httpbin (WebApp JWT), Grafana JWT/Basic
- Wetty web-based SSH terminal (cert-based auth, same CA as Gateway)
- Homepage with Ingress annotation auto-discovery + manual entries
- Headlamp K8s dashboard (HA, 3 replicas, auto-auth via ServiceAccount token)
- Architecture diagram at docs/architecture.html

Next tasks:
1. **Agent Pod** — `apps/platform/agent/` — AI coding agent pod with herdr pre-installed, PVC for persistent project storage, SSH access at `agent.octolet.int` via Twingate SSH Gateway. Separate from the demo sshd pod. See memory file `project_agent-pod-plan.md`.
2. **Wetty fixes** — Stabilize Wetty, verify it connects to sshd via cert auth
3. **Prometheus/AlertManager** — Verify they're accessible via Twingate after reconnecting Client (ExternalName wrapper Services were just deployed)
4. **Pre-built sshd image** — Consider building a container image with openssh pre-installed instead of `apk add` at startup

Begin by reading CLAUDE.md and TODO.md, then ask what to work on.

---

Generated on 2026-09-22.
