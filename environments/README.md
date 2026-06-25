# Integrated deployment environments

Environment recipes are small YAML files that describe one complete target without
copying all Helm values into another monolith. A recipe names the distribution,
runtime, provider, ordered values overlays, optional image-build source overlays,
and Terraform/Compose output preferences.

Render a plan:

```bash
python3 scripts/render-environment.py environments/ontoportal-compose-existing.yaml
python3 scripts/render-environment.py environments/agroportal-aws-eks.yaml --image-tag sha-<validated-build>
```

Outputs are written to `dist/environments/<name>/` and may include:

- `values.yaml`: merged Helm values for review or direct `helm template` use;
- `image-values.yaml`: generated image repository/tag overlay when source builds are enabled;
- `build-matrix.json`: image build jobs derived from `imageBuilds`;
- `docker-compose.yml` and `.env.sample` for Compose recipes;
- `terraform.tfvars` for Kubernetes recipes using the Terraform module.

The recipes are intentionally examples, not secret-bearing production files.
Keep site-specific hostnames, TLS certificate references, external secret names,
cloud identity bindings, and final immutable image tags in `values/sites/*.yaml`
or a private repository.

## Source-build recipes

Recipes with `imageBuildValuesFiles` do not clone or build repositories during rendering. They generate `build-matrix.json` and, when an image tag is provided, `image-values.yaml`. Run the manual `build-source-images` workflow or an equivalent local Buildx process first, then render with the accepted immutable tag. For private GitHub sources, configure `SOURCE_GIT_TOKEN` or runner SSH credentials.

A source-build component can publish the same build to both GHCR and Docker Hub by setting a primary `image` plus `publishImages` mirrors. Docker Hub publishing requires `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets; GHCR uses `GITHUB_TOKEN`.

MatPortal recipes may require private or unreleased images/source repositories. The public MatPortal CI profile validates the deployment wiring with substitute images, not the complete private MatPortal application stack.

## Cloud recipes

AWS, Azure, and GCP recipes target existing Kubernetes clusters. They do not provision EKS, AKS, GKE, node pools, cloud databases, DNS, or certificate resources. Use provider IaC outside this repository for platform resources, then combine the rendered values with a private site overlay for hosts, TLS, external secret names, identity annotations, image pins, and final resource sizing.
