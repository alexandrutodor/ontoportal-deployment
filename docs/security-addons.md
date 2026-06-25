# Security and observability add-ons

## Monitoring

Application-level monitoring is split into two layers:

1. The OntoPortal chart can emit a `ServiceMonitor` when `monitoring.serviceMonitor.enabled=true`.
2. The platform can install kube-prometheus-stack through Terraform `enable_monitoring=true` or manually with Helm.

Manual install example:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace \
  -f values/addons/monitoring-kube-prometheus-stack.yaml
```

Then install OntoPortal with:

```bash
-f values/addons/monitoring-servicemonitor.yaml
```

## Trivy Operator

Terraform:

```hcl
enable_trivy_operator = true
```

Manual Helm:

```bash
helm repo add aqua https://aquasecurity.github.io/helm-charts
helm upgrade --install trivy-operator aqua/trivy-operator \
  --namespace trivy-system --create-namespace \
  -f values/addons/trivy-operator.yaml
```

## SonarQube

SonarQube is useful for code quality and security scanning of the source repositories. It should not be part of the OntoPortal application release. Install it as a separate platform service:

```hcl
enable_sonarqube = true
```

or manually:

```bash
helm repo add sonarqube https://SonarSource.github.io/helm-chart-sonarqube
helm upgrade --install sonarqube sonarqube/sonarqube \
  --namespace sonarqube --create-namespace \
  -f values/addons/sonarqube-community.yaml
```

## Wazuh

Wazuh has a separate Kubernetes deployment model and certificate workflow, so this repository includes a wrapper rather than embedding it in the Helm chart:

```bash
WAZUH_VERSION=v4.14.5 WAZUH_ENV=local-env scripts/addons/wazuh-deploy.sh
```

Review storage classes and resource requests before using Wazuh outside a test cluster.

## Missing security items to consider

- NetworkPolicies for namespace isolation.
- External secret manager integration.
- Image signing and admission control.
- SBOM generation in CI.
- Backup restore drills, not only backup creation.
- TLS automation with cert-manager.
- Rate limiting at ingress for public API endpoints.
- Separate service accounts and RBAC if components need Kubernetes API access later.


## Loki and Grafana Alloy

Metrics alone are not enough for production operations. Use Loki for logs and Grafana Alloy to collect Kubernetes pod logs.

Development or low-volume k3s install:

```bash
helm repo add grafana-community https://grafana-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
kubectl create namespace observability || true
helm upgrade --install loki grafana-community/loki \
  --namespace observability \
  -f values/addons/loki-monolithic-dev.yaml
helm upgrade --install grafana-alloy grafana/alloy \
  --namespace observability \
  -f values/addons/grafana-alloy-loki.yaml
```

Production Loki should use object storage and a deployment mode sized for expected volume. Do not use the filesystem-only development values for durable production log retention.

## cert-manager

cert-manager should be a platform add-on installed once per cluster, not an OntoPortal subchart.

```bash
helm repo add jetstack https://charts.jetstack.io
helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  -f values/addons/cert-manager.yaml
```

After installation, create an Issuer or ClusterIssuer that matches the site certificate policy.

## External Secrets Operator

Use External Secrets Operator, Sealed Secrets, SOPS, Vault, or a cloud-native secret manager for production. The chart-generated secret path is for development and disposable test clusters.

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm upgrade --install external-secrets external-secrets/external-secrets \
  --namespace external-secrets --create-namespace \
  -f values/addons/external-secrets.yaml
```

Then install OntoPortal with `secrets.existingSecret`.

A complete k3s rehearsal using ESO's Kubernetes provider is included in `examples/external-secrets/`. It creates a source namespace, read-only RBAC, a `ClusterSecretStore`, and an `ExternalSecret` that materializes the exact Secret keys expected by the chart. Use that example for local validation, then replace the provider with Vault, AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, 1Password, SOPS, or another production secret backend.

## Kyverno

Kyverno can enforce admission policies such as disallowing privileged pods, requiring resource requests, requiring image registries, or blocking floating tags. Start in audit mode before enforcement.

```bash
helm repo add kyverno https://kyverno.github.io/kyverno/
helm upgrade --install kyverno kyverno/kyverno \
  --namespace kyverno --create-namespace \
  -f values/addons/kyverno-ha.yaml
```

## Velero

Velero requires provider-specific configuration for object storage, snapshots, and credentials. `values/addons/velero-provider.example.yaml` must be copied and completed with provider-specific settings before use.

Use it as a reminder that production backup is not done until a restore has been tested.
