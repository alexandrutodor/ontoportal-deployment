# GitHub repository setup

Use this checklist when publishing the repository to `matportal/ontoportal-deployment` for the first time or managing repository configurations.

## Pre-push checks

Before executing the first push, ensure no sensitive data or unvalidated configurations are tracked:

1. **Verify no credentials or secrets exist**:
   - Check that TLS certificates (`.pem`, `.key`, `.crt`), Kubeconfigs, and cloud provider/Vault credentials are not present in the working tree.
   - Review staged files:
     ```bash
     git status
     git diff --cached
     ```
2. **Ensure generated files are up to date**:
   - Run the configuration generators and validation checks to verify that snapshot files are consistent:
     ```bash
     make compose-all
     make validate-generated
     ```
3. **Check `.gitignore`**:
   - Confirm that local environment files (`.env`, `.env.*`), local database storage (`data/`), Terraform state/vars (`.terraform/`, `*.tfstate`, `*.tfvars`), and Python cache files are correctly ignored.

## Create and push (first push)

If you are using the GitHub CLI (`gh`) to create and push the private repository:

```bash
gh repo create matportal/ontoportal-deployment --private --source . --remote origin --push
```

If the repository already exists on GitHub:

```bash
git remote add origin git@github.com:matportal/ontoportal-deployment.git
git branch -M main
git push -u origin main
```

## Repository settings

Immediately after pushing the repository:

1. **Access Control**: Keep the repository private. Grant access only to audited team members.
2. **Secret Scanning & Push Protection**:
   - Go to **Settings > Code security and analysis**.
   - Enable **Secret scanning** and **Push protection** to prevent accidental credential leakage.
3. **Branch Protection**:
   - Go to **Settings > Branches** and add a protection rule for `main`.
   - Enable **Require a pull request before merging** (with at least one review approval).
   - Enable **Require status checks to pass before merging** and select always-running required checks such as `validate`. Do not require path-filtered workflows like `terraform` or `build-images` globally unless GitHub is configured to report a no-op success for unaffected PRs; otherwise unrelated PRs can be blocked. Keep `k3s-smoke` and `matportal-k3s-smoke` scheduled/manual until their runtime cost and flakiness are acceptable as required checks.
   - Require review from designated code owners for Helm chart, Terraform, script, and production documentation changes.

## Never commit

Do not commit:
- Real production or staging secrets, passwords, tokens, API keys, or certificates.
- `.env` or `.env.*` files (except the committed generated samples under `compose/generated/.env.*.sample`).
- Terraform variable files containing real values (`*.tfvars`), `.terraform/` caches, or state files (`*.tfstate`).
- Raw Kubernetes config files or live cluster dumps containing secret data.
- Site-specific `values/sites/*.yaml` files unless they are sanitized `*.example.yaml` templates.

## Image publishing secrets

The optional multi-architecture image workflow can publish to GHCR with `GITHUB_TOKEN`. It builds pull requests with `push=false`, scans image contexts and local `linux/amd64` images with Trivy, and uses Buildx cache. To publish to Docker Hub, add repository secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`

Use a Docker Hub access token with the narrowest practical scope. See `docs/image-builds.md`.

## Update automation

A baseline `.github/dependabot.yml` is included for GitHub Actions, Terraform providers, and the disabled example Dockerfile. GitHub Actions and Terraform provider updates are grouped to reduce PR noise, and Terraform provider major-version bumps are ignored until the module is intentionally reviewed for that major. Dependabot's Docker ecosystem uses one directory per update entry, so add each future `images/<name>/` directory explicitly or use Renovate for glob-based image coverage. Configure Dependabot or Renovate to monitor additional dependencies as they appear:

- GitHub Actions workflows
- Terraform providers and modules
- Helm chart versions and container image tags (ensure all upgrades go through staging/smoke testing first).
