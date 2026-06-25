locals {
  repo_root          = abspath("${path.module}/..")
  chart_path         = "${local.repo_root}/chart/ontoportal"
  profile_file       = "${local.repo_root}/values/profiles/${var.profile}.yaml"
  additional_files   = [for f in var.additional_values_files : startswith(f, "/") ? f : "${local.repo_root}/${f}"]
  ontoportal_values  = concat([file(local.profile_file)], [for f in local.additional_files : file(f)])
  kube_context_value = var.kube_context == "" ? null : var.kube_context
  helm_set_values    = merge({ "global.namespace" = var.namespace, "global.createNamespace" = "false" }, var.set_values)
  velero_values_file = var.velero_values_file == "" ? "" : (startswith(var.velero_values_file, "/") ? var.velero_values_file : "${local.repo_root}/${var.velero_values_file}")
  velero_values      = var.velero_values_file == "" ? [] : [file(local.velero_values_file)]
  keda_values_file   = var.keda_values_file == "" ? "" : (startswith(var.keda_values_file, "/") ? var.keda_values_file : "${local.repo_root}/${var.keda_values_file}")
  keda_values        = var.enable_keda && var.keda_values_file != "" ? [file(local.keda_values_file)] : []
  vpa_values_file    = var.vpa_values_file == "" ? "" : (startswith(var.vpa_values_file, "/") ? var.vpa_values_file : "${local.repo_root}/${var.vpa_values_file}")
  vpa_values         = var.enable_vpa && var.vpa_values_file != "" ? [file(local.vpa_values_file)] : []
}

provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = local.kube_context_value
}

provider "helm" {
  kubernetes {
    config_path    = var.kubeconfig_path
    config_context = local.kube_context_value
  }
}

resource "kubernetes_namespace" "ontoportal" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/part-of" = "ontoportal"
    }
  }
}

resource "helm_release" "ontoportal" {
  name             = var.release_name
  namespace        = var.namespace
  chart            = local.chart_path
  create_namespace = false
  wait             = true
  timeout          = 900
  atomic           = false

  values = local.ontoportal_values

  dynamic "set" {
    for_each = local.helm_set_values
    content {
      name  = set.key
      value = set.value
    }
  }

  dynamic "set_sensitive" {
    for_each = toset(nonsensitive(keys(var.set_sensitive_values)))
    content {
      name  = set_sensitive.value
      value = var.set_sensitive_values[set_sensitive.value]
    }
  }

  depends_on = [kubernetes_namespace.ontoportal, helm_release.keda, helm_release.vpa, helm_release.kube_prometheus_stack]
}

resource "kubernetes_namespace" "keda" {
  count = var.enable_keda ? 1 : 0
  metadata { name = var.keda_namespace }
}

resource "helm_release" "keda" {
  count      = var.enable_keda ? 1 : 0
  name       = "keda"
  namespace  = var.keda_namespace
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = var.keda_chart_version
  wait       = true
  timeout    = 900
  values     = local.keda_values
  depends_on = [kubernetes_namespace.keda]
}

resource "kubernetes_namespace" "vpa" {
  count = var.enable_vpa ? 1 : 0
  metadata { name = var.vpa_namespace }
}

resource "helm_release" "vpa" {
  count      = var.enable_vpa ? 1 : 0
  name       = "vpa"
  namespace  = var.vpa_namespace
  repository = "https://charts.fairwinds.com/stable"
  chart      = "vpa"
  version    = var.vpa_chart_version
  wait       = true
  timeout    = 900
  values     = local.vpa_values
  depends_on = [kubernetes_namespace.vpa]
}

resource "kubernetes_namespace" "monitoring" {
  count = var.enable_monitoring ? 1 : 0
  metadata { name = var.monitoring_namespace }
}

resource "helm_release" "kube_prometheus_stack" {
  count      = var.enable_monitoring ? 1 : 0
  name       = "kube-prometheus-stack"
  namespace  = var.monitoring_namespace
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  wait       = true
  timeout    = 900
  values     = [file("${local.repo_root}/values/addons/monitoring-kube-prometheus-stack.yaml")]
  depends_on = [kubernetes_namespace.monitoring]
}

resource "kubernetes_namespace" "trivy" {
  count = var.enable_trivy_operator ? 1 : 0
  metadata { name = var.trivy_namespace }
}

resource "helm_release" "trivy_operator" {
  count      = var.enable_trivy_operator ? 1 : 0
  name       = "trivy-operator"
  namespace  = var.trivy_namespace
  repository = "https://aquasecurity.github.io/helm-charts"
  chart      = "trivy-operator"
  wait       = true
  timeout    = 600
  values     = [file("${local.repo_root}/values/addons/trivy-operator.yaml")]
  depends_on = [kubernetes_namespace.trivy]
}

resource "kubernetes_namespace" "sonarqube" {
  count = var.enable_sonarqube ? 1 : 0
  metadata { name = var.sonarqube_namespace }
}

resource "helm_release" "sonarqube" {
  count      = var.enable_sonarqube ? 1 : 0
  name       = "sonarqube"
  namespace  = var.sonarqube_namespace
  repository = "https://SonarSource.github.io/helm-chart-sonarqube"
  chart      = "sonarqube"
  wait       = true
  timeout    = 1200
  values     = [file("${local.repo_root}/values/addons/sonarqube-community.yaml")]
  depends_on = [kubernetes_namespace.sonarqube]
}


resource "kubernetes_namespace" "observability" {
  count = (var.enable_loki || var.enable_grafana_alloy) ? 1 : 0
  metadata { name = var.observability_namespace }
}

resource "helm_release" "loki" {
  count      = var.enable_loki ? 1 : 0
  name       = "loki"
  namespace  = var.observability_namespace
  repository = "https://grafana-community.github.io/helm-charts"
  chart      = "loki"
  wait       = true
  timeout    = 1200
  values     = [file(startswith(var.loki_values_file, "/") ? var.loki_values_file : "${local.repo_root}/${var.loki_values_file}")]
  depends_on = [kubernetes_namespace.observability]
}

resource "helm_release" "grafana_alloy" {
  count      = var.enable_grafana_alloy ? 1 : 0
  name       = "grafana-alloy"
  namespace  = var.observability_namespace
  repository = "https://grafana.github.io/helm-charts"
  chart      = "alloy"
  wait       = true
  timeout    = 900
  values     = [file(startswith(var.grafana_alloy_values_file, "/") ? var.grafana_alloy_values_file : "${local.repo_root}/${var.grafana_alloy_values_file}")]
  depends_on = [kubernetes_namespace.observability, helm_release.loki]
}

resource "kubernetes_namespace" "cert_manager" {
  count = var.enable_cert_manager ? 1 : 0
  metadata { name = var.cert_manager_namespace }
}

resource "helm_release" "cert_manager" {
  count      = var.enable_cert_manager ? 1 : 0
  name       = "cert-manager"
  namespace  = var.cert_manager_namespace
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  wait       = true
  timeout    = 900
  values     = [file("${local.repo_root}/values/addons/cert-manager.yaml")]
  depends_on = [kubernetes_namespace.cert_manager]
}

resource "kubernetes_namespace" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0
  metadata { name = var.external_secrets_namespace }
}

resource "helm_release" "external_secrets" {
  count      = var.enable_external_secrets ? 1 : 0
  name       = "external-secrets"
  namespace  = var.external_secrets_namespace
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  wait       = true
  timeout    = 900
  values     = [file("${local.repo_root}/values/addons/external-secrets.yaml")]
  depends_on = [kubernetes_namespace.external_secrets]
}

resource "kubernetes_namespace" "kyverno" {
  count = var.enable_kyverno ? 1 : 0
  metadata { name = var.kyverno_namespace }
}

resource "helm_release" "kyverno" {
  count      = var.enable_kyverno ? 1 : 0
  name       = "kyverno"
  namespace  = var.kyverno_namespace
  repository = "https://kyverno.github.io/kyverno/"
  chart      = "kyverno"
  wait       = true
  timeout    = 1200
  values     = [file("${local.repo_root}/values/addons/kyverno-ha.yaml")]
  depends_on = [kubernetes_namespace.kyverno]
}

resource "kubernetes_namespace" "velero" {
  count = var.enable_velero ? 1 : 0
  metadata { name = var.velero_namespace }
}

resource "helm_release" "velero" {
  count      = var.enable_velero ? 1 : 0
  name       = "velero"
  namespace  = var.velero_namespace
  repository = "https://vmware-tanzu.github.io/helm-charts"
  chart      = "velero"
  wait       = true
  timeout    = 900
  values     = local.velero_values
  depends_on = [kubernetes_namespace.velero]

  lifecycle {
    precondition {
      condition     = var.velero_values_file != ""
      error_message = "enable_velero=true requires velero_values_file to point at a site-specific values file."
    }
  }
}
