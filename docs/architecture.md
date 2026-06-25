# Architecture

## Goal

The deployment must support clean OntoPortal, AgroPortal-style, BioPortal-style, MatPortal, Docker Compose, k3s, and cloud Kubernetes installations without maintaining unrelated stacks. One Helm chart supports those targets through values layers and environment recipes.

## Source of truth

The Helm chart under `chart/ontoportal` is the source of truth. Profiles under `values/profiles` define deployment intent:

- `ontoportal-clean.yaml`: upstream-compatible, no MatPortal runtime patches.
- `agroportal-clean.yaml`: clean profile with AgroPortal-friendly naming and image defaults.
- `matportal.yaml`: MatPortal branding, URLs, feature hooks, and explicit patch gates.
- `k3s-local.yaml`: k3s-specific storage, scheduling, and Traefik defaults.
- `docker-compose.yaml`: changes suitable for local Compose rendering.

Optional features are layered with `values/addons/*.yaml`. The same add-on values can be used with Helm directly, through `scripts/deploy.sh`, through Terraform, or through `environments/*.yaml` recipes.

Additional reusable layers are separated by concern:

- `values/cloud/*.yaml`: AWS EKS, Azure AKS, and GKE storage/ingress assumptions.
- `values/image-builds/*.yaml`: source-repository image build plans for deployments that do not want to consume already-published images.
- `values/sites/*.yaml`: private final-mile choices such as hosts, TLS, external secret names, cloud identity annotations, image pins, and sizing.
- `environments/*.yaml`: named targets that compose profiles, provider overlays, add-ons, image-build plans, and Terraform/Compose output preferences.

## Core services

The chart models the standard OntoPortal runtime as separate components:

- API
- cron worker
- web UI
- RDF store: Virtuoso by default, or an external store through values
- Redis: shared or split persistent/goo/http-cache mode
- Solr: shared or split term/property search mode
- mgrep
- MySQL and memcached for the UI

## Optional services

Optional components are intentionally disabled in the clean baseline:

- Matomo analytics
- FAIRness assessment service
- assistant service
- OntoPanel
- ServiceMonitor integration

Security and platform add-ons are not embedded into the application chart:

- kube-prometheus-stack
- Trivy Operator
- SonarQube
- Wazuh

This avoids mixing app upgrades with CRD-heavy platform upgrades.

## Runtime patches

The old MatPortal chart mixed application deployment with runtime source modifications. This repository keeps only one sample patch gate:

```yaml
patches:
  matportalApiParentNormalization:
    enabled: true
```

That gate is enabled only in `values/profiles/matportal.yaml`. More runtime patches can be added as named gates, but the preferred long-term path is to upstream changes or build MatPortal images containing the required code.

## Naming model

Resources are named from the Helm release:

```text
<release>-api
<release>-cron
<release>-ui
<release>-redis-persistent
<release>-solr-term
```

This makes clean OntoPortal, AgroPortal, and MatPortal installs co-exist in the same cluster without chart edits.

## Integrated environment model

Environment recipes are not a second deployment system. They list the ordered values files for a target and let tooling render the same source of truth into generated artifacts:

```bash
python3 scripts/render-environment.py environments/agroportal-aws-eks.yaml --image-tag sha-validated
```

A rendered bundle can contain merged Helm values, generated image overrides, a Docker build matrix, Terraform tfvars, and Compose files. This makes provider/distribution combinations explicit while keeping the Helm chart reusable.

See `docs/modular-environments.md`, `docs/cloud-deployments.md`, and `docs/upstream-environment-map.md` for the operational model.
