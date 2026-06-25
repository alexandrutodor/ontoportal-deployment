# Release process

This repository publishes deployment code, Helm values, generated Compose snapshots, Terraform deployment module, and optional image build definitions. A release is only trustworthy when the exact commit/tag has recorded validation evidence.

## Versioning

Use date-based deployment tags until the chart/API surface needs semantic versioning:

```text
vYYYY.MM.DD              # normal release, e.g. v2026.06.14
vYYYY.MM.DD.N            # same-day follow-up, e.g. v2026.06.14.1
vYYYY.MM.DD-rc.N         # optional release candidate
```

Application images are versioned independently from this deployment repository. Release notes must list both the deployment tag and the application image tags/digests actually deployed.

## Release candidate checklist

Start from a clean working tree on `main`:

```bash
git status --short
git pull --ff-only
python3 -m py_compile scripts/*.py
make validate
make validate-generated
make compose-config
helm lint chart/ontoportal -f values/profiles/ontoportal-clean.yaml -f values/profiles/k3s-local.yaml
helm lint chart/ontoportal -f values/profiles/agroportal-clean.yaml -f values/profiles/k3s-local.yaml
helm lint chart/ontoportal -f values/profiles/matportal.yaml -f values/profiles/k3s-local.yaml -f values/addons/matomo.yaml -f values/addons/fairness.yaml
make production-check PROFILE=ontoportal-clean
make production-check PROFILE=matportal
git diff --check
```

If Terraform paths or values changed, also run:

```bash
make terraform-validate
```

If native Terraform is unavailable, use the Docker-backed command pattern from `docs/validation-evidence.md`.

## Live validation matrix

Record every live test in `docs/validation-evidence.md` before tagging.

| Area | Required evidence before production use |
| --- | --- |
| Clean OntoPortal k3s | `k3s-smoke` GitHub Actions pass and/or local disposable k3s smoke pass |
| MatPortal k3s wiring | `matportal-k3s-smoke` GitHub Actions pass; note that it uses the CI-only public-runtime overlay |
| Native k3s tutorial | full `docs/tutorial-k3s-laptop-server.md` rehearsal on a VM/server |
| Real MatPortal runtime | smoke test with private MatPortal UI/FAIRness images and production-like site values |
| Upgrade/rollback | `helm upgrade`, `helm rollback`, and preserved-PVC reinstall output |
| Backup/restore | Restic/VolSync/Velero restore into a new namespace plus smoke output |
| HA | node drain/failover evidence if HA guidance is claimed for the release |
| Terraform | `terraform plan`/`apply` evidence for Terraform-managed environments |

If a row is not tested, say so explicitly in the release notes.

## Image digest capture

For every image deployed to production-like environments, record the tag and digest. Examples:

```bash
kubectl -n ontoportal get pods \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.image}{"\t"}{.imageID}{"\n"}{end}{end}'
```

For images built by this repository, prefer immutable digests in site values after acceptance:

```yaml
images:
  api:
    repository: ghcr.io/matportal/example-api
    tag: sha-abcdef0
    digest: sha256:...
```

If the chart does not yet support a digest field for a component, pin the tag to an immutable release tag and record the digest in the release notes.

## Tagging

Create an annotated tag only after validation evidence is updated:

```bash
VERSION=v2026.06.14
git tag -a "$VERSION" -m "OntoPortal deployment $VERSION"
git push origin "$VERSION"
```

After pushing the tag, watch workflows triggered by tag rules, especially image builds when enabled:

```bash
gh run list --limit 10
gh run watch <run-id> --exit-status
```

## Release notes template

```markdown
# OntoPortal deployment vYYYY.MM.DD

## Summary
- What changed:
- Who should upgrade:

## Deployment commit/tag
- Commit:
- Tag:

## Tested matrix
- Static validation:
- GitHub `validate`:
- GitHub `terraform`:
- GitHub `k3s-smoke`:
- GitHub `matportal-k3s-smoke`:
- Native k3s rehearsal:
- Backup/restore drill:
- HA/failover:

## Image versions and digests
| Component | Image tag | Digest | Notes |
| --- | --- | --- | --- |
| API | | | |
| Cron | | | |
| UI | | | |
| Solr | | | |
| Redis | | | |
| Store | | | |

## Upgrade procedure
1. Back up values and Secrets.
2. Confirm latest PVC/application backup.
3. Run `helm diff upgrade` if available.
4. Run `helm upgrade --install ...` with the same site values.
5. Run `SMOKE_DEEP=true scripts/smoke.sh <namespace> <release>`.

## Rollback procedure
1. Run `helm history <release> -n <namespace>`.
2. Run `helm rollback <release> <revision> -n <namespace>`.
3. Run smoke tests.
4. Restore data from backup only if schema/data migrations require it.

## Known gaps
- Explicitly list every untested area.
```

## Branch protection guidance

Required checks should stay limited to always-running workflows such as `validate` unless path-filtered workflows are configured to report no-op success. Keep expensive/manual workflows such as `k3s-smoke` and `matportal-k3s-smoke` non-required until runtime and flakiness are acceptable for every PR.
