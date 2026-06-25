# Multi-architecture image build automation

The repository includes `.github/workflows/build-images.yml` for optional multi-architecture Docker builds. It can publish `linux/amd64` and `linux/arm64` images to GitHub Container Registry (GHCR) or Docker Hub, using Buildx cache plus Trivy filesystem/image scans before publishing.

## When to use it

Most OntoPortal, AgroPortal, and MatPortal application images should be built in their source repositories. Use this deployment repository's image workflow only for images that intentionally live with deployment code, for example:

- small operational helper images;
- migration or backup utility images;
- deployment-specific wrapper images;
- temporary MatPortal runtime images during a migration.

Do not move full application source builds here unless this repository becomes the source of truth for that image.

## GitHub Container Registry

GHCR works with the built-in `GITHUB_TOKEN` and does not require extra repository secrets.

Create `images/<name>/Dockerfile` and `images/<name>/image.json`:

```json
{
  "enabled": true,
  "image": "ghcr.io/matportal/<name>",
  "context": "images/<name>",
  "dockerfile": "images/<name>/Dockerfile",
  "platforms": "linux/amd64,linux/arm64",
  "tags": "type=ref,event=branch\ntype=ref,event=tag\ntype=sha,prefix=sha-"
}
```

Push to `main` or push a `v*` release tag. Pull requests build with `push=false`; pushes build and publish the multi-arch manifest when an enabled image definition has `push` unset or `true`.

## Docker Hub

For Docker Hub images such as `docker.io/matportal/<name>`, configure these repository secrets first:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Then set `image` to the Docker Hub repository in `image.json`.

## Manual build

Use **Actions > build-images > Run workflow** to build an arbitrary context without adding an enabled `image.json` first. Set:

- `image`: `ghcr.io/matportal/<name>` or `docker.io/matportal/<name>`
- `context`: build context path
- `dockerfile`: Dockerfile path
- `platforms`: default `linux/amd64,linux/arm64`
- `push`: `true` to publish, `false` to compile-test only; manual dispatch defaults to `false` for safety

## Validation

Run before enabling a new image:

```bash
make validate
```

`make validate` parses repository YAML, environment recipes, source-build values, and `images/*/image.json`. Enabled in-repository image configs must point to an in-repository context and Dockerfile. Enabled image names must start with an allowed registry prefix, Dockerfiles must live inside their build context, and publishable local configs may not use the repository root as the build context. The disabled example at `images/_example/image.json` documents the legacy helper-image schema without producing an image.

The root `.dockerignore` excludes Git metadata, local env files, Terraform state, kubeconfigs, archives, and local data directories from ad-hoc image contexts. Keep image contexts narrow anyway.


## Source repository builds

In addition to `images/*/image.json` helper images, deployments can define source builds under `values/image-builds/*.yaml`. These files describe which application component should be built, the target registry repository, and either a local or Git source. The manual `build-source-images` workflow reads those values through `scripts/image-build-matrix.py`, fetches Git sources when needed, runs Trivy scans, and builds/pushes with Docker Buildx when `push=true` is requested.

The repository includes public source-build plans for OntoPortal, BioPortal, and AgroPortal. Their primary image targets are GHCR, and `publishImages` mirrors the same tags to Docker Hub when `push=true`. Remove or override `publishImages` if you only want GHCR. MatPortal is different: not every MatPortal source repository or runtime image is public/released from this deployment repository, so `values/image-builds/matportal-source.example.yaml` is disabled until the site operator fills in accessible repositories and registry targets.

Example:

```bash
python3 scripts/image-build-matrix.py -f values/image-builds/ontoportal-source.yaml
python3 scripts/render-environment.py environments/bioportal-compose-source.yaml --image-tag sha-accepted
```

The render step creates `image-values.yaml`, which maps the built image repositories and accepted immutable tag back to Helm `images.*`. Keep the source-build workflow separate from deployment: build, scan, run smoke tests, then promote the accepted immutable tag through a site values file or rendered environment bundle.

Remote Git sources are restricted to allowed hosts declared in `imageBuilds.defaults.allowedGitHosts`, HTTP(S) or SSH Git URLs are supported, and local build contexts must stay inside the repository. The validation scripts do not clone remote repositories; the workflow performs that live check when a build is requested.

### Publishing to GHCR and Docker Hub

Each source-build component has a primary `image` and optional `publishImages` mirrors:

```yaml
imageBuilds:
  defaults:
    allowedImagePrefixes: ["ghcr.io/example/", "docker.io/example/"]
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

The primary `image` is what `render-environment.py --image-tag ...` writes into Helm values. `publishImages` receives the same tags in the same workflow run, which is useful for mirroring to Docker Hub. GHCR uses the workflow `GITHUB_TOKEN`; Docker Hub requires `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` repository secrets. Custom registries are intentionally not wired into the stock workflow; use GHCR or Docker Hub unless you maintain a local workflow extension.

## Production tagging policy

For production, prefer immutable tags or digests in Helm values. A typical promotion flow is:

1. Open a pull request and let the workflow build with `push=false` plus Trivy scans.
2. Build on `main` and publish `main`/`sha-*` tags.
3. Test the `sha-*` image in a disposable namespace.
4. Create a release tag such as `v2026.06.13` if the image is accepted.
5. Update site Helm values to the release tag, or set `images.<component>.digest` to the accepted digest.
6. Record the validation evidence in the deployment issue or runbook.


For private GitHub source repositories, set the optional `SOURCE_GIT_TOKEN` repository secret with read access to those repositories. SSH-style Git URLs are accepted by the matrix/fetch scripts, but the workflow runner must be configured with an SSH key before they can be cloned.

Branch, tag, and commit SHA refs are supported by the source fetch script.
