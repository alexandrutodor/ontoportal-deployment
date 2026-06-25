## What changed

Describe the deployment, code, values, Terraform, script, or documentation change.

## Validation

- [ ] `make validate`
- [ ] Helm render for clean OntoPortal
- [ ] Helm render for MatPortal
- [ ] Compose regenerated when relevant
- [ ] Docker Compose config checked when relevant
- [ ] k3s smoke test when relevant
- [ ] Terraform validate/plan when relevant
- [ ] Production readiness check when relevant

## Documentation

- [ ] I updated the docs affected by this change.
- [ ] I updated runbooks for new or changed failure modes.
- [ ] I updated `CHANGELOG.md`.
- [ ] I regenerated generated files if needed.

## Production impact

- [ ] No secret values are committed.
- [ ] No new required manual steps are undocumented.
- [ ] No optional add-on was enabled in the clean baseline.
- [ ] New production image tags are pinned or digest-based.
- [ ] Rollback/migration notes are documented if required.
