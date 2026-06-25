output "release_name" {
  value = helm_release.ontoportal.name
}

output "namespace" {
  value = var.namespace
}

output "profile" {
  value = var.profile
}

output "enabled_addons" {
  value = {
    keda           = var.enable_keda
    monitoring     = var.enable_monitoring
    trivy_operator = var.enable_trivy_operator
    sonarqube      = var.enable_sonarqube
  }
}


output "observability_namespace" {
  value       = var.observability_namespace
  description = "Namespace used for Loki/Grafana Alloy when enabled."
}

output "platform_addons_enabled" {
  value = {
    keda             = var.enable_keda
    monitoring       = var.enable_monitoring
    loki             = var.enable_loki
    grafana_alloy    = var.enable_grafana_alloy
    trivy_operator   = var.enable_trivy_operator
    sonarqube        = var.enable_sonarqube
    cert_manager     = var.enable_cert_manager
    external_secrets = var.enable_external_secrets
    kyverno          = var.enable_kyverno
    velero           = var.enable_velero
  }
  description = "Optional platform add-ons enabled by this Terraform run."
}
