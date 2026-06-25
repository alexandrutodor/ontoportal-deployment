# Modular deployment environments

This repository now treats a deployment target as a composition of reusable
layers rather than a copied one-off directory. The design mirrors the public
OntoPortal ecosystem patterns:

- local Compose/DIP-style developer environments can run dependencies only,
  existing images, or source-mounted/source-built application services;
- virtual-appliance-style deployments need a full-stack bundle with explicit
  storage, ingress, admin provisioning, and service dependencies;
- AgroPortal/MatPortal/BioPortal deployments share the same core shape but need
  different branding, images, optional services, storage, and operational add-ons.

## Layer model

The layers are intentionally small and ordered:

1. `chart/ontoportal/values.yaml`: neutral defaults and component contracts.
2. `values/profiles/*.yaml`: distribution profile such as `ontoportal-clean`,
   `agroportal-clean`, or `matportal`.
3. `values/profiles/k3s-*.yaml` or `values/cloud/*.yaml`: provider/runtime
   overlay for storage, ingress, and cluster assumptions.
4. `values/addons/*.yaml`: optional platform/application capabilities such as
   Matomo, FAIRness, HPA, KEDA, VPA, monitoring, logging, policy, and backup.
5. `values/image-builds/*.yaml`: optional source-repository image build plan.
6. `values/sites/*.yaml`: private/site-specific hosts, TLS, secrets references,
   image pins, identity annotations, and final sizing.
7. `environments/*.yaml`: a recipe that names the ordered files for a target and
   renders generated outputs under `dist/environments/<name>/`.

The Helm chart remains the deployment source of truth. Docker Compose and
environment bundles are generated from the same values model.

## Environment recipe format

Example:

```yaml
apiVersion: deployment.ontoportal.org/v1alpha1
kind: Environment
metadata:
  name: agroportal-aws-eks
spec:
  profile: agroportal-clean
  distribution: agroportal
  runtime: kubernetes
  provider: aws-eks
  valuesFiles:
    - values/profiles/agroportal-clean.yaml
    - values/profiles/production-recommended.yaml
    - values/cloud/aws-eks.yaml
  imageBuildValuesFiles:
    - values/image-builds/agroportal-source.yaml
  terraform:
    enabled: true
    namespace: agroportal
    release_name: agroportal
    create_namespace: true
    enable_cert_manager: true
    enable_external_secrets: true
    enable_monitoring: true
```

Render it:

```bash
python3 scripts/render-environment.py environments/agroportal-aws-eks.yaml --image-tag sha-validated
```

Outputs:

- `values.yaml`: merged Helm values for the target;
- `values-files.txt`: ordered source files for review;
- `image-values.yaml`: generated image repository/tag overlay when source builds
  are enabled;
- `build-matrix.json`: image build jobs derived from `imageBuilds`;
- `terraform.tfvars`: Terraform inputs for Kubernetes recipes;
- `docker-compose.yml` and `.env.sample`: Compose output for Compose recipes;
- `summary.json`: machine-readable summary of the rendered bundle.

## Existing images versus source builds

Use existing images by setting `images.<component>.repository/tag` in profile or
site values. This is the simplest and safest production path when images are
published by their source repositories.

Use source builds when a deployment needs to rebuild from public or private Git
repositories. Add a source-build values file such as:

```yaml
imageBuilds:
  enabled: true
  components:
    api:
      enabled: true
      image: ghcr.io/example/ontologies-api
      helmImage: api
      source:
        type: git
        url: https://github.com/ontoportal/ontologies_api.git
        ref: master
        context: .
        dockerfile: Dockerfile
```

Then generate the build matrix and build through the manual GitHub workflow:

```bash
python3 scripts/image-build-matrix.py -f values/image-builds/ontoportal-source.yaml
```

After the image is built, tested, and accepted, render the environment with the
accepted immutable tag:

```bash
python3 scripts/render-environment.py environments/bioportal-compose-source.yaml --image-tag sha-<accepted>
```

Commit or store the resulting `image-values.yaml` only if it does not contain
site secrets and it uses an immutable, accepted tag.

## Provider targets

Provider overlays are deliberately separated from distributions:

| Distribution | Runtime | Provider overlay | Example recipe |
| --- | --- | --- | --- |
| OntoPortal | Compose | `values/profiles/docker-compose.yaml` | `ontoportal-compose-existing.yaml` |
| BioPortal-style | Compose + source builds | `values/profiles/docker-compose.yaml` | `bioportal-compose-source.yaml` |
| AgroPortal | Kubernetes | `values/cloud/aws-eks.yaml` | `agroportal-aws-eks.yaml` |
| OntoPortal | Kubernetes | `values/cloud/gcp-gke.yaml` | `ontoportal-gcp-gke.yaml` |
| MatPortal | Kubernetes | `values/cloud/azure-aks.yaml` | `matportal-azure-aks.yaml` |

Add new environments by composing existing layers before adding chart features.
Only add a new chart value when a deployment need cannot be represented as a
profile, provider overlay, add-on, site file, or image build plan.

## Validation

Run:

```bash
make validate-environments
make validate
```

Validation checks:

- environment recipe schema basics;
- referenced files exist and stay inside the repository;
- image build values produce a matrix;
- rendered environment bundles can be created;
- duplicate YAML keys are rejected.

The validation intentionally does not clone remote image sources or assert that a
remote repository has a Dockerfile. The `build-source-images` workflow performs
that live check when the build is requested.


For private GitHub source repositories, set the optional `SOURCE_GIT_TOKEN` repository secret with read access to those repositories. SSH-style Git URLs are accepted by the matrix/fetch scripts, but the workflow runner must be configured with an SSH key before they can be cloned.

Branch, tag, and commit SHA refs are supported by the source fetch script.
