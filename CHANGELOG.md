# Changelog

## Unreleased

### Added

- Operations guide for future testing and maintenance work.
- Code, deployment, and documentation update policy.
- Production readiness document and static production-readiness checker.
- Production recommended values overlay.
- Optional Loki and Grafana Alloy values for Kubernetes logging.
- Optional cert-manager, External Secrets Operator, Kyverno, and Velero provider values.
- Terraform switches for Loki, Grafana Alloy, cert-manager, External Secrets Operator, Kyverno, Velero, KEDA, and VPA.
- Optional chart templates for NetworkPolicy, PodDisruptionBudget, API/UI HorizontalPodAutoscaler, KEDA ScaledObjects, and VerticalPodAutoscaler resources.
- Observability guide and troubleshooting runbook.
- Pull request checklist requiring documentation updates.
- GitHub private repository setup checklist.
- Site overlay examples for OntoPortal dev and MatPortal production templates.
- Generated Compose snapshot validation in CI and Makefile.
- Expanded secret-contract, ServiceMonitor CRD, Terraform state, and Compose safety documentation.
- Single-node k3s laptop/server tutorial.
- High-availability deployment guide.
- Restic backup and restore strategy.
- Validation evidence document that separates tested checks from pending live-cluster tests.
- Compose `config` validation target and CI step.
- Optional multi-architecture image build workflow for GHCR/Docker Hub.
- Image build definition examples and documentation.
- First live k3s clean OntoPortal smoke-test evidence.
- Scheduled/manual k3s smoke GitHub Actions workflow and k3s CI values overlay.
- Terraform static validation GitHub Actions workflow and Makefile target.
- Deep smoke checks for UI login, Solr, Redis, RDF store status, mgrep TCP, rollouts, pod status, and restarts.
- HPA, KEDA, and VPA autoscaling overlays, live resource check scripts, and manual k3s smoke workflows.
- Dependabot configuration and `.dockerignore` for safer image build contexts.

### Fixed

- Clean k3s startup issues found during k3s testing: namespace ownership, API probe path, UI Puma/Rails database preparation, MySQL database name, cron log directory, and cron image compatibility.
- Hardened optional image builds with PR push suppression, safer manual dispatch defaults, image allowlist validation, Buildx cache, and Trivy filesystem/image scans.
- Improved Restic docs to preserve original deployment replica counts during quiesce/restore.
- Guarded autoscaling validation so API/UI horizontal scaling requires RWX storage and RollingUpdate strategy, and mutating VPA cannot conflict with CPU/memory HPA/KEDA.

### Notes

- Loki development values use monolithic/filesystem mode and are not production storage guidance.
- Production use still requires site-specific image pinning, secrets, TLS, storage, backup, and restore configuration.
