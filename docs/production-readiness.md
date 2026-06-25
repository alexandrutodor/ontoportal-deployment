# Production readiness review

A Helm render or disposable-cluster smoke test is not production approval.

## Current production-relevant coverage

Coverage exists for:

- clean OntoPortal, AgroPortal-style, BioPortal-style, and MatPortal profiles;
- k3s and cloud-provider overlays;
- Docker Compose, source-image, and Terraform Helm generation;
- Matomo, FAIRness, assistant, monitoring, logging, security, backup, and policy add-ons;
- HPA/KEDA/VPA autoscaling templates;
- shell and Playwright smoke tests.

Important gaps still require live cluster tests, source-image builds, deeper application tests, or site decisions. See also `docs/validation-evidence.md`, `docs/testing-plan.md`, `docs/high-availability.md`, `docs/backup-restic.md`, `docs/autoscaling-keda.md`, `docs/cloud-deployments.md`, and `docs/modular-environments.md`.

- Pin all production image versions or digests. Some defaults intentionally remain upstream-compatible development tags.
- Validate Virtuoso backup/restore and performance for production, or use an external RDF store profile.
- Decide Solr configset workflow: mounted generated configsets, init job, or prebuilt Solr image.
- Replace chart-generated secrets with External Secrets, Sealed Secrets, SOPS, Vault, cloud secret manager, or another approved secret flow.
- Move backups from documented commands to scheduled backups plus restore drills.
- Avoid API/UI replicas greater than one until shared data uses RWX storage or is externalized.
- Validate KEDA/Prometheus/HPA behavior under load and review VPA recommendations before enabling autoscaling in production.
- Add ontology import/search/annotator-specific smoke tests.

## Production profile

Use `values/profiles/production-recommended.yaml` as an overlay, not as a standalone profile:

```bash
helm upgrade --install ontoportal chart/ontoportal \
  --namespace ontoportal \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/sites/ontoportal-dev.example.yaml
```

For MatPortal:

```bash
helm upgrade --install matportal chart/ontoportal \
  --namespace matportal \
  -f values/profiles/matportal.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/addons/matomo.yaml \
  -f values/addons/fairness.yaml \
  -f values/sites/matportal-prod.example.yaml
```

## Static production check

Run:

```bash
python3 scripts/production-readiness-check.py \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/sites/ontoportal-dev.example.yaml
```

Use `--strict` in CI after the first production site values exist:

```bash
python3 scripts/production-readiness-check.py --strict \
  -f values/profiles/ontoportal-clean.yaml \
  -f values/profiles/production-recommended.yaml \
  -f values/sites/ontoportal-dev.example.yaml
```

`production-recommended.yaml` enables `monitoring.serviceMonitor.enabled`; install Prometheus Operator CRDs first or override it back to `false` until the CRDs exist. Any overlay that enables `autoscaling.*.mode=keda` requires KEDA CRDs first. Any overlay that enables `verticalPodAutoscaling.*` requires VPA CRDs first.


## Modular environment acceptance

For every environment recipe promoted beyond development, record at least:

1. rendered environment bundle path and source values file list;
2. image source mode: existing published images or source-built images;
3. immutable image tags/digests accepted for every application image;
4. provider overlay and site overlay used;
5. Helm render/lint output;
6. live install/upgrade/rollback smoke-test output;
7. ingress/TLS/browser-test evidence;
8. storage restart/drain evidence, especially for any RWX class;
9. autoscaling evidence if HPA, KEDA, or VPA are enabled;
10. backup/restore evidence.

The source-build workflow is not a substitute for product validation. A built API/UI/cron image must still pass application smoke tests and site acceptance tests before it is pinned into a deployment.

## Minimum production stack

| Capability | Recommended component | Repository status |
| --- | --- | --- |
| Metrics, dashboards, alerts | kube-prometheus-stack with Prometheus, Grafana, Alertmanager | Terraform flag and values included |
| App scrape discovery | OntoPortal `ServiceMonitor` | Values add-on included |
| Autoscaling | HPA or KEDA after RWX/external state is proven; VPA recommendation mode before mutating right-sizing | HPA, KEDA, and VPA chart templates plus validation included |
| Logs | Loki plus Grafana Alloy | Terraform flags and values included |
| Vulnerability/config scanning | Trivy Operator | Terraform flag and values included |
| Code quality/static analysis | SonarQube | Terraform flag and values included; wire to CI/source repos |
| TLS | cert-manager or managed ingress TLS | Terraform flag and values included |
| Secret management | External Secrets Operator or equivalent | Terraform flag and examples included |
| Backups/restore | Velero, Restic, VolSync, or storage/database-native backups | provider-specific values and docs included; requires site configuration |
| Admission/policy | Kyverno or Gatekeeper | Kyverno optional Terraform flag/values included |
| Network isolation | NetworkPolicy with a compatible CNI | optional chart template included; disabled by default |
| Browser smoke | Playwright against deployed UI/API | tests and k3s workflow hook included |

## Go/no-go checklist

Do not promote to production until all required items below are true:

- Helm renders clean, MatPortal, and site/autoscaling overlays without error.
- Docker Compose generation still works after values changes.
- k3s or target-cluster install succeeds from empty PVCs.
- Upgrade succeeds over existing PVCs.
- Uninstall/reinstall behavior is understood and does not delete data unless explicitly requested.
- API `/`, UI `/`, UI `/login`, Solr, Redis, RDF store status, mgrep, pod status, and restart checks pass `scripts/smoke.sh`.
- Playwright browser tests pass against the deployed UI/API.
- Ontology import, search, annotator, mgrep, Solr, RDF store, cron, UI login, and admin flows are tested.
- Production images are pinned.
- Secrets are externally managed.
- TLS is configured and verified.
- Logs and metrics are visible in the chosen observability platform.
- Alerts are routed and tested.
- Backup and restore are tested against a non-production namespace or cluster, with restore commands recorded.
- HPA/KEDA scaling is load-tested, `make keda-check` passes on the live release, VPA recommendation mode is observed with `make vpa-check`, and rollback behavior is tested.
- Docs and changelog match the exact commands used.
