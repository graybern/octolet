# Handoff Prompt

Paste this into a new Claude Code session to continue development.

---

You are continuing work on octolet. It is a GitOps-managed observability and networking stack for a 5-node Raspberry Pi K3s cluster (ARM64), deployed via ArgoCD with an app-of-apps pattern via ApplicationSet.

Tech stack: kube-prometheus-stack, standalone Grafana (JWT + password auth), Loki (monolithic), Tempo (monolithic), Grafana Alloy (DaemonSet), Twingate Operator + Gateway, Homepage dashboard, Headlamp K8s dashboard, Wetty web SSH. Everything is Helm charts or Kustomize manifests managed by ArgoCD.

Key directories: apps/ (each apps/<category>/<app>/ is an ArgoCD Application), common/ (shared alert rules, dashboards), appconfig/ (ArgoCD bootstrap), docs/ (architecture, this file).

Read CLAUDE.md for full project context — architecture decisions, naming conventions, label taxonomy, patterns, current state, and operational pitfalls (especially the TLS cert and Alloy pipeline sections).
Read TODO.md for Phase 2 items.

Cluster details:
- 5 Raspberry Pi nodes: 3 control-plane, 2 workers
- **control-1 is tainted** (`dedicated=touchscreen:NoSchedule`) — runs Ubuntu Desktop + touchscreen, only DaemonSet pods allowed
- K3s with Traefik ingress, `*.octolet.int` domain pattern
- Twingate network: `gbernard`, Gateway at `api-k8s.octolet.int`, 2 connectors
- ArgoCD at `argocd.octolet.int` (anonymous read-only, not managed by this repo)
- All images must be ARM64 compatible. Conservative resource requests (Pi hardware).
- Storage: local-path provisioner. Longhorn planned for Phase 2.

Critical operational knowledge:
- Gateway TLS cert is frozen via `ignoreDifferences` on Secret /data + /metadata/annotations. Never disable this.
- Alloy log pipeline requires `local.file_match` between `discovery.relabel` and `loki.source.file` — Alloy can't resolve globs itself.
- sshd host keys must be signed with the SSH CA at startup to prevent Gateway host key mismatch on pod restart.
- Grafana has `cookie_secure: false` and `root_url: http://` for Pi touchscreen HTTP access.
- Loki canary is disabled via top-level `lokiCanary.enabled: false` (not nested under monitoring).
- ExternalName Services don't remap ports — use ClusterIP wrapper Services for non-port-80 backends.

Current state (2026-09-28):
- Full LGTMP stack deployed and healthy, all logs flowing with K8s metadata labels
- 12 TwingateResources + 1 SSH resource (via API)
- Twingate Operator fully ArgoCD-managed, Gateway TLS stable
- Demo apps: sshd (Alpine, SSH cert auth), httpbin (JWT), Grafana JWT/Basic, Wetty
- Homepage with auto-discovery + manual entries
- control-1 tainted for touchscreen use, Grafana accessible via /etc/hosts

Next tasks:
1. **Agent Pod** — `apps/platform/agent/` — AI coding agent pod with herdr pre-installed, PVC for persistent project storage, SSH access at `agent.octolet.int` via Twingate SSH Gateway. See memory file `project_agent-pod-plan.md`.
2. **Grafana Kiosk** — Set up auto-rotating dashboard on the touchscreen (Grafana Kiosk binary or Chrome kiosk mode)
3. **Custom Grafana dashboards** — Twingate connector/gateway overview, cluster touchscreen summary
4. **Wetty stability** — Verify cert-based SSH works, consider pre-built image

Begin by reading CLAUDE.md and TODO.md, then ask what to work on.

---

Generated on 2026-09-28.
