# Tutorial: create a custom profile and build images from source

This tutorial shows how to create a site profile, optionally build application images from source, publish them to GHCR and/or Docker Hub, and deploy only pinned image versions.

## 1. Choose the starting point

Use the closest existing profile as a base:

- `values/profiles/ontoportal-clean.yaml`: clean OntoPortal baseline.
- `values/profiles/agroportal-clean.yaml`: AgroPortal-style public images.
- `values/profiles/matportal.yaml`: MatPortal deployment shape.

MatPortal note: the MatPortal profile is not a fully public, reproducible distribution. Some MatPortal repositories or images may be private, unreleased, or site-specific. The CI profile `values/profiles/matportal-k3s-ci.yaml` swaps some MatPortal runtime images for public smoke-compatible images; it validates Kubernetes wiring, not private MatPortal application code.

## 2. Create a profile overlay

Copy the closest profile and change only the site-specific deltas:

```bash
cp values/profiles/ontoportal-clean.yaml values/profiles/example.yaml
```

Edit the profile metadata, namespace, public URLs, and image choices:

```yaml
profile:
  name: example
  matportal: false
  description: Example site profile.

global:
  namespace: example
  imagePullSecrets: []

api:
  publicUrl: https://data.example.org
  restUrlPrefix: https://data.example.org

ui:
  siteName: Example Portal
  orgName: Example Organization
  uiUrl: https://portal.example.org
  publicApiUrl: https://data.example.org

images:
  api:
    repository: ghcr.io/example/ontologies-api
    tag: v2026.06.25
  cron:
    repository: ghcr.io/example/ncbo-cron
    tag: v2026.06.25
  ui:
    repository: ghcr.io/example/web-ui
    tag: v2026.06.25
```

For private registries, create the Kubernetes pull secret separately and list it under `global.imagePullSecrets`.

## 3. Pin production images

For production, do not deploy floating tags like `latest`, `development`, `main`, or `master`. Use a release tag or a digest:

```yaml
images:
  api:
    repository: ghcr.io/example/ontologies-api
    tag: v2026.06.25
    # or use digest instead of tag:
    # digest: sha256:0123456789abcdef...
```

The Helm chart and generated Compose files prefer `digest` when present and otherwise use `repository:tag`.

## 4. Define source builds

Create a build overlay for the application repositories you control:

```yaml
# values/image-builds/example-source.yaml
deploymentTarget:
  imageMode: build

imageBuilds:
  enabled: true
  defaults:
    platforms: linux/amd64,linux/arm64
    push: true
    allowedImagePrefixes: ["ghcr.io/example/", "docker.io/example/"]
    allowedGitHosts: ["github.com"]
    tags: |-
      type=ref,event=branch
      type=ref,event=tag
      type=sha,prefix=sha-
  components:
    api:
      enabled: true
      image: ghcr.io/example/ontologies-api
      publishImages:
        - docker.io/example/ontologies-api
      helmImage: api
      source:
        type: git
        url: https://github.com/ontoportal/ontologies_api.git
        ref: master
        context: .
        dockerfile: Dockerfile
```

`image` is the primary image repository used when rendering Helm values. `publishImages` is optional and mirrors the same build to extra repositories, for example Docker Hub. Add more enabled components for `cron`, `ui`, `mgrep`, `fairness`, `assistant`, or `ontopanel` only when you have accessible source repositories and Dockerfiles for them; set `helmImage` to the matching chart image key.

For private GitHub repositories, add a repository secret named `SOURCE_GIT_TOKEN` with read access. For Docker Hub publishing, add `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`. GHCR publishing uses the workflow `GITHUB_TOKEN`.

## 5. Build and publish

Generate the matrix locally first:

```bash
python3 scripts/image-build-matrix.py -f values/image-builds/example-source.yaml
```

Then run **Actions > build-source-images**:

- `values_files`: `values/image-builds/example-source.yaml`
- `push`: `false` for compile/scan-only, `true` to publish
- `platforms`: leave empty unless overriding the values file

The workflow fetches the source repository, scans the filesystem, builds an amd64 image for scanning, and then builds the requested multi-arch image. With the sample above, the same build is tagged for both GHCR and Docker Hub.

## 6. Render deployable values with the accepted tag

After testing a build, render an environment recipe that includes `imageBuildValuesFiles`; otherwise there is no source-build matrix and no `image-values.yaml` to generate. For example, the bundled BioPortal source-build recipe works like this:

```bash
python3 scripts/render-environment.py environments/bioportal-compose-source.yaml \
  --image-tag sha-<accepted>
```

For a custom environment recipe, add your profile and source-build overlay:

```yaml
apiVersion: deployment.ontoportal.org/v1alpha1
kind: Environment
metadata:
  name: example-k3s
spec:
  profile: ontoportal-clean
  distribution: example
  runtime: kubernetes
  provider: k3s
  valuesFiles:
    - values/profiles/example.yaml
    - values/profiles/k3s-local.yaml
  imageBuildValuesFiles:
    - values/image-builds/example-source.yaml
```

Render it:

```bash
python3 scripts/render-environment.py environments/example-k3s.yaml --image-tag sha-<accepted>
```

Use the generated `dist/environments/example-k3s/image-values.yaml` with Helm or copy the pinned image values into a private site overlay. If you render a recipe without `imageBuildValuesFiles`, no image overlay is produced by design.

## 7. Validate before deployment

Run the repository checks:

```bash
make validate
make validate-environments
make production-check PROFILE=ontoportal-clean
```

Render and lint your exact stack:

```bash
helm lint chart/ontoportal \
  -f values/profiles/example.yaml \
  -f values/profiles/k3s-local.yaml \
  -f dist/environments/example-k3s/image-values.yaml
```

Deploy to a disposable namespace before production and run `scripts/smoke.sh`; add `scripts/app-smoke.sh` and `scripts/ui-e2e.sh` when API credentials and test ontology data are available.
