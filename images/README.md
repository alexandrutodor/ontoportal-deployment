# Multi-architecture image builds

This directory is reserved for optional image build definitions used by `.github/workflows/build-images.yml`.

The deployment repository primarily ships Helm values and operational docs. Most images referenced by the chart are built in their upstream application repositories. Use this directory only for images that this repository is responsible for building, such as small wrapper images, migration helpers, or MatPortal-specific runtime images that intentionally live with deployment code.

## Enable an image build

Create a subdirectory with a Dockerfile and an `image.json` file:

```text
images/my-helper/
  Dockerfile
  image.json
```

Example `image.json`:

```json
{
  "enabled": true,
  "image": "ghcr.io/matportal/my-helper",
  "context": "images/my-helper",
  "dockerfile": "images/my-helper/Dockerfile",
  "platforms": "linux/amd64,linux/arm64",
  "tags": "type=ref,event=branch\ntype=ref,event=tag\ntype=sha,prefix=sha-"
}
```

The workflow scans `images/*/image.json` on pull requests, pushes to `main`, and `v*` tags, then builds every config with `enabled: true`. Pull requests use `push=false`; publishing happens only on non-PR runs when the config allows it. It also supports manual `workflow_dispatch` builds for one-off contexts outside this directory, with manual `push` defaulting to `false`.

## Registries

### GitHub Container Registry

Images under `ghcr.io/<owner>/<image>` use the built-in `GITHUB_TOKEN`. The workflow has `packages: write` permission.

### Docker Hub

Images under Docker Hub, such as `docker.io/matportal/my-helper`, require repository secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Use a Docker Hub access token, not an account password.

## Platforms

The default platforms are:

```text
linux/amd64,linux/arm64
```

The workflow uses QEMU and Docker Buildx. Multi-arch builds can be slower than single-arch builds, and some base images or native dependencies may not support both architectures. If an image cannot build on ARM64, document why and narrow `platforms` for that image.

## Safety rules

- Do not bake secrets, kubeconfigs, `.env`, `*.tfvars`, or cluster dumps into images.
- Prefer immutable runtime inputs through Kubernetes Secrets and ConfigMaps.
- Image names must start with `ghcr.io/matportal/` or `docker.io/matportal/`.
- Keep Dockerfiles inside their build context and avoid using the repository root for publishable images.
- Tag releases with semantic version tags when promoting to production.
- Update Helm values only after the pushed image digest or immutable tag has been validated.
