# Remaining operational decisions and high-value work

The repository now includes the deployment baselines, generated Compose snapshots, Terraform add-ons, HPA/KEDA/VPA autoscaling support, deep shell smoke tests, and Playwright browser smoke tests. The items below are still needed before a production cutover.

## Configuration and secrets

- Site-specific ExternalSecret/SealedSecret/SOPS examples for real providers.
- Complete site overlays under `values/sites/<site>.yaml` for external databases/search/RDF stores.
- API key/client rotation procedure.

## Storage and backup

- CSI driver choice for production, not only k3s `local-path`.
- Automated backup jobs for shared repository files, RDF store, Solr, MySQL, and Matomo DB.
- Restore test runbooks with real recovery-time measurements.
- VolSync or Velero examples for the chosen storage provider.

## Networking

- cert-manager issuer and certificate values for each target site.
- external-dns or DNS automation.
- NetworkPolicies after service flows are verified.
- Ingress rate limiting for public API endpoints.

## Release engineering

- Extend Dependabot/Renovate coverage to Helm chart versions and production image digests.
- SBOM generation for images not built through the optional Buildx workflow.
- Image signing and admission policy.
- `helm unittest` or chart-testing once the Helm toolchain is available in CI.
- Promote scheduled/manual k3s smoke workflows to required PR status only after measuring reliability.

## OntoPortal-specific validation

- Standard ontology import fixture.
- API key/authentication test.
- Solr term/property search result correctness test, beyond core ping.
- mgrep dictionary generation test.
- UI admin login/action test.
- RDF store query/update test, beyond status endpoint.
- Autoscaling load test for HPA/KEDA overlays and recommendation review for VPA overlays.

## MatPortal-specific cleanup

- Replace runtime monkey patches with versioned MatPortal images where possible.
- Convert UI overrides to a proper MatPortal UI build.
- Keep assistant/MOBI/OAuth/Matomo integrations out of the clean baseline.

## Recently completed repository work

- Operations guide, update policy, production checks, and production overlay.
- Loki/Grafana Alloy logging path; cert-manager, External Secrets Operator, Kyverno, and Velero add-ons.
- NetworkPolicy, PDB, HPA, KEDA, and VPA templates.
- Single-node k3s tutorial, high-availability guide, Restic backup/restore strategy, and validation evidence document.
- Deep smoke workflows, Terraform validation workflow, Dependabot, image-build Trivy/cache hardening, and Playwright UI smoke tests.
