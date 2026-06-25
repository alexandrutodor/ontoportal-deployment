# Code, deployment, and documentation update policy

## Principle

The deployment code and documentation are one product. A change is not complete until users can operate it from the repository documentation without guessing.

## Change classes

### Application image update

Use this flow when updating OntoPortal, AgroPortal, MatPortal, UI, cron, mgrep, Solr, Redis, MySQL/MariaDB, RDF store, Matomo, FAIRness, assistant, or OntoPanel images.

1. Open a change with the image tag/digest update in values or site-specific values.
2. Record the upstream source, release notes, and migration notes in the pull request.
3. Run `make validate`.
4. Render Helm manifests for clean OntoPortal and MatPortal.
5. Regenerate Compose if the changed image affects Compose output.
6. Deploy to a disposable namespace.
7. Run smoke tests plus component-specific checks.
8. Update docs if commands, environment variables, paths, ports, volumes, probes, or behavior changed.
9. Add an entry to `CHANGELOG.md`.

### Chart/template update

1. Add or update values in `chart/ontoportal/values.yaml`.
2. Add profile overrides only when behavior differs by profile.
3. Keep MatPortal-specific behavior behind explicit gates.
4. Render all profiles with Helm.
5. Update `docs/profiles.md`, deployment tutorials, and runbooks if user-facing behavior changed.
6. Add tests or validation script checks for regressions.

### Terraform/add-on update

1. Keep add-ons as independent releases unless they are truly part of the OntoPortal app.
2. Document default namespace, required credentials, storage assumptions, CRDs, and upgrade risks.
3. Add an enable flag and values file rather than enabling by default.
4. Update `docs/security-addons.md`, `docs/observability.md`, and `docs/production-readiness.md`.
5. Test add-on installation and uninstall in a disposable cluster.

### Documentation-only update

1. Verify commands still match file names and profiles.
2. Prefer copy-pasteable commands.
3. Record any assumptions, such as k3s Traefik, local-path storage, or external object storage.

## Required documentation updates by file type

| Changed area | Required documentation update |
| --- | --- |
| `chart/ontoportal/templates/*` | `docs/architecture.md`, `docs/profiles.md`, affected deployment docs |
| `values/profiles/*` | `docs/profiles.md`, README quick-start if relevant |
| `values/addons/*` | `docs/security-addons.md` or `docs/observability.md` |
| `scripts/*` | README and the tutorial that calls the script |
| `terraform/*` | `docs/deployment-terraform.md`, `terraform/README.md` |
| `compose/generated/*` | `docs/deployment-docker-compose.md`, only after regenerating |
| Runtime patches | `docs/migration-from-current-matportal-k8s.md` and a runbook note |

## Release cadence

- Patch deployment fixes can be merged as needed after validation.
- Dependency and image update reviews should be batched on a predictable monthly cadence unless there is a security fix.
- Security fixes should be handled immediately, with a temporary workaround documented if a full release cannot be completed safely.
- Once production is live, maintain separate `dev`, `stage`, and `prod` site values. Promote the same image digests from dev to stage to prod.

## Versioning

Use semantic versions for this deployment repository:

- MAJOR: breaking values/schema/profile changes or required migration steps.
- MINOR: new optional add-ons, new profiles, new generated deployment target support.
- PATCH: bug fixes, docs corrections, non-breaking defaults.

Application image versions are independent from deployment repository versions. The release notes must list both.

## Generated files

Generated Compose files are committed only for convenience. The source of truth is still `chart/ontoportal/values.yaml` plus profiles. Any change to the generator or relevant values requires:

```bash
make compose-all
make validate
```

## Production execution rule

Before executing new code in production:

1. Confirm the exact Git commit and values files.
2. Confirm image tags are pinned or digest-based.
3. Confirm secrets come from an approved secret source.
4. Confirm backups are current and restore has been tested recently.
5. Confirm rollback command and previous Helm revision.
6. Run stage smoke tests on the same values minus production-only hostnames/secrets.
7. Update docs and changelog in the same release branch.
