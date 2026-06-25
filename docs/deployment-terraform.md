# Terraform deployment tutorial

Terraform installs the local Helm chart into an existing k3s/Kubernetes cluster and can optionally install platform add-ons. GitHub Actions runs static Terraform `fmt/init/validate`; live plan/apply still requires a disposable cluster or target environment.

## Clean OntoPortal

```bash
cd terraform
cp examples/ontoportal-clean-k3s.tfvars.example ontoportal-clean.auto.tfvars
# edit kubeconfig settings; prefer an existing Kubernetes Secret over putting secrets in tfvars
terraform init
terraform apply
```

## MatPortal with monitoring and Trivy

```bash
cd terraform
cp examples/matportal-k3s.tfvars.example matportal.auto.tfvars
# edit kubeconfig/add-on choices; protect Terraform state if set_sensitive_values is used
terraform init
terraform apply
```

## Validate Terraform changes

```bash
make terraform-validate
```

This runs `terraform fmt -check -recursive`, `terraform init -backend=false -lockfile=readonly`, and `terraform validate` under `terraform/`.

## Useful variables

```hcl
profile      = "matportal"
namespace    = "matportal"
release_name = "matportal"
additional_values_files = [
  "values/profiles/k3s-local.yaml",
  "values/addons/matomo.yaml",
  "values/addons/fairness.yaml"
]
enable_monitoring        = true
# Logging: development defaults. Replace Loki values before production.
enable_loki              = true
enable_grafana_alloy     = true
# Security and policy add-ons.
enable_trivy_operator    = true
enable_sonarqube         = false
enable_cert_manager      = true
enable_external_secrets  = true
enable_kyverno           = false
# Backup requires provider-specific values.
enable_velero            = false
# velero_values_file     = "values/sites/velero-provider.yaml"
```

## When not to use this Terraform module

Do not use this module to create k3s nodes, Proxmox containers, DNS zones, or TLS certificates. Keep that in an infrastructure repository and call this Terraform module only after the cluster exists.


## Production Terraform notes

The add-on flags install platform components with generic values. `set_sensitive_values` is marked sensitive in Terraform output, but values are still stored in Terraform state; use protected remote state or an external secret manager for production. If `monitoring.serviceMonitor.enabled=true`, install Prometheus Operator CRDs before applying the OntoPortal release or use a two-phase apply.

Production still requires site-specific decisions:

- Loki needs object storage, retention, and sizing values.
- Velero needs `velero_values_file` to point at cloud/provider plugin values, credentials, backup location, snapshot location, schedules, and a restore drill.
- cert-manager needs an Issuer or ClusterIssuer after installation.
- Grafana Alloy assumes the bundled Loki service endpoint unless its values are customized for an external Loki endpoint.
- External Secrets needs SecretStore or ClusterSecretStore configuration.
- Kyverno should start in audit mode with exclusions tested before enforce mode.
- SonarQube should be connected to CI/source repositories; it is not part of the OntoPortal runtime.

Keep infrastructure that creates k3s nodes, DNS, load balancers, and object storage outside this module unless the repository is intentionally expanded into a full infrastructure stack.
