# Migration from the current MatPortal Kubernetes tree

## What was found

The existing `projects/ontoportal-k8s` tree is operational but mixes several concerns:

- the Helm chart name and templates are MatPortal-specific;
- service names such as `matportal-api`, `matportal-ui`, `matportal-store`, and `matportal-solr` are embedded in templates and scripts;
- clean OntoPortal, MatPortal branding, analytics, assistant integration, FAIRness, runtime hotfixes, and k3s scheduling are layered together;
- MatPortal UI overrides and API monkey patches are injected during container startup;
- monitoring is present but separate from a clean ServiceMonitor toggle;
- Terraform is focused on a Proxmox/LXC/k3s environment rather than a reusable Helm release deployment;
- many templates reference secrets, but a reusable secret contract was not consistently isolated as a baseline interface.

## Migration target

Move to this structure:

```text
base chart -> profile values -> optional add-ons -> site-specific secret/host values
```

This lets the same release machinery support:

- clean upstream-compatible OntoPortal;
- AgroPortal-style clean installs;
- MatPortal with controlled differences;
- Docker Compose rendered from the same profiles;
- Terraform-based Helm deployment to k3s.

## Step-by-step migration

### 1. Freeze current MatPortal values

Export the current release values:

```bash
helm -n matportal get values matportal -o yaml > current-matportal-values.yaml
```

### 2. Map values into the new profile model

Put generic values into a private/site overlay. Start by copying the template, for example `cp values/sites/matportal-prod.example.yaml values/sites/matportal-prod.yaml`, then edit the copy:

```yaml
ingress:
  hosts:
    ui: matportal.example.org
    api: api.matportal.example.org
ui:
  supportEmail: support@example.org
```

Keep MatPortal-only defaults in `values/profiles/matportal.yaml`.

### 3. Move runtime patches behind gates

Old runtime patches should become one of:

1. upstream PRs to OntoPortal/AgroPortal code;
2. MatPortal images built from a MatPortal branch;
3. explicit Helm patch gates under `patches.*`.

Avoid adding anonymous startup `sed`/`cat` blocks to the shared templates.

### 4. Migrate services by release name

Install the new chart in a new namespace first:

```bash
helm upgrade --install matportal-next chart/ontoportal \
  --namespace matportal-next --create-namespace \
  -f values/profiles/matportal.yaml \
  -f values/profiles/k3s-local.yaml \
  -f values/addons/matomo.yaml \
  -f values/addons/fairness.yaml \
  -f values/sites/matportal-prod.yaml \
  --set global.createNamespace=false
  # or use values/sites/matportal-prod.example.yaml only for a dry-run/template rehearsal
```

### 5. Migrate data

For k3s `local-path`, copy PVC data carefully while workloads are stopped. Prefer application-level export/import or snapshots where possible. Validate:

- repository files;
- Solr cores;
- RDF store KB;
- mgrep dictionary;
- UI database;
- Matomo DB when enabled.

### 6. Cut over ingress

Point DNS or ingress hosts to the new release only after smoke tests pass.

### 7. Remove old hard-coded service references

Search old scripts and docs for these tokens:

```bash
grep -R "matportal-api\|matportal-ui\|matportal-store\|matportal-solr\|matportal-cache" -n .
```

Replace them with release-derived names or values.

## Recommended cleanup after migration

- Convert remaining MatPortal UI override ConfigMaps into a versioned MatPortal image or explicit add-on.
- Add CI to run `make validate`, `helm template`, Trivy image scans, and Compose rendering on every PR.
- Add NetworkPolicies once service communication paths are confirmed.
- Add backup restore drills to the release checklist.
