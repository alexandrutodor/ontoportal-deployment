# Terraform deployment

This Terraform entrypoint installs the local Helm chart into an existing k3s or Kubernetes cluster. It intentionally does not create VMs, LXC containers, DNS, or certificates; those belong in a separate infrastructure layer so the OntoPortal release can be updated without re-provisioning nodes.

## Clean OntoPortal on k3s

```bash
cd terraform
cp examples/ontoportal-clean-k3s.tfvars.example ontoportal-clean.auto.tfvars
# edit kubeconfig settings; prefer an existing Kubernetes Secret over putting secrets in tfvars
terraform init
terraform apply
```

## MatPortal on k3s with optional add-ons

```bash
cd terraform
cp examples/matportal-k3s.tfvars.example matportal.auto.tfvars
# edit kubeconfig/add-on choices; protect Terraform state if set_sensitive_values is used
terraform init
terraform apply
```

## Cloud Kubernetes targets

The module can install the chart into an existing EKS, AKS, or GKE cluster by combining a distribution profile with a provider overlay. Example tfvars files are included under `terraform/examples/`:

- `aws-eks.tfvars.example`
- `azure-aks.tfvars.example`
- `gcp-gke.tfvars.example`

These examples assume the cluster, node pools, ingress controller, CSI drivers, DNS, certificate issuer, and cloud identity bindings already exist. Keep site-specific hosts, external secret references, image pins, RWX storage classes, and cloud annotations in private values overlays.

## Static validation

Run this before submitting Terraform changes:

```bash
make terraform-validate
# or directly:
terraform -chdir=terraform fmt -check -recursive
terraform -chdir=terraform init -backend=false -lockfile=readonly
terraform -chdir=terraform validate
```

GitHub Actions runs the same static validation for Terraform changes. It does not prove a live plan/apply; use a disposable k3s/k3s cluster for that.

## Add-on model

Terraform can deploy KEDA, Vertical Pod Autoscaler, kube-prometheus-stack, Trivy Operator, SonarQube, Loki, Grafana Alloy, cert-manager, External Secrets Operator, Kyverno, and Velero as independent Helm releases. Wazuh is handled by `scripts/addons/wazuh-deploy.sh` because the upstream Wazuh Kubernetes package is Kustomize/cert-generation based and has its own upgrade lifecycle.

## Important boundaries

- Use Terraform for repeatable release installation and optional platform add-ons.
- Use Helm values for application configuration.
- Use external infrastructure Terraform for Proxmox, cloud nodes, DNS, and object storage.
- Use a snapshot-capable CSI driver or a dedicated backup tool for production backups.


## Optional production/platform add-ons

Additional optional flags are available:

```hcl
enable_keda              = true  # KEDA operator and ScaledObject CRDs
enable_vpa               = true  # Vertical Pod Autoscaler operator and CRDs
enable_monitoring        = true  # kube-prometheus-stack: Prometheus, Grafana, Alertmanager
enable_loki              = true  # Loki; dev values by default
enable_grafana_alloy     = true  # Kubernetes pod-log collection to Loki
enable_trivy_operator    = true  # vulnerability/config scanning
enable_sonarqube         = true  # code quality service; wire to CI/source repos
enable_cert_manager      = true  # TLS automation
enable_external_secrets  = true  # secret synchronization from external providers
enable_kyverno           = true  # policy/admission engine
enable_velero            = true  # backup/restore
velero_values_file       = "values/sites/velero-provider.yaml"  # required when enable_velero=true
```

Do not enable Velero without `velero_values_file` pointing to a completed site-specific values file with storage credentials and restore/retention decisions. Do not enable production Loki without site-specific storage credentials and retention decisions. Enable Grafana Alloy together with Loki unless `values/addons/grafana-alloy-loki.yaml` is customized to point at an external Loki endpoint. `set_sensitive_values` is marked sensitive in Terraform output, but secret values are still persisted in Terraform state; use protected remote state or an external secret manager for production.

If an OntoPortal values overlay enables `autoscaling.*.mode=keda`, apply KEDA CRDs before the OntoPortal release. Terraform does this automatically when `enable_keda=true`; otherwise install `kedacore/keda` separately. If an overlay enables `verticalPodAutoscaling.*.enabled=true`, apply VPA CRDs before the OntoPortal release. Terraform does this automatically when `enable_vpa=true`; otherwise install a VPA operator separately. If an overlay enables `monitoring.serviceMonitor.enabled`, apply kube-prometheus-stack/Prometheus Operator CRDs before the OntoPortal release or use a two-phase apply.
