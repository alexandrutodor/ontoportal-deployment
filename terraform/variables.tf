variable "kubeconfig_path" {
  description = "Path to kubeconfig for the target k3s/Kubernetes cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "Optional kubeconfig context. Leave empty to use the current context."
  type        = string
  default     = ""
}

variable "release_name" {
  description = "Helm release name."
  type        = string
  default     = "ontoportal"
}

variable "namespace" {
  description = "Target namespace for OntoPortal."
  type        = string
  default     = "ontoportal"
}

variable "profile" {
  description = "Deployment profile under values/profiles without .yaml suffix."
  type        = string
  default     = "ontoportal-clean"

  validation {
    condition     = contains(["ontoportal-clean", "agroportal-clean", "matportal"], var.profile)
    error_message = "profile must be one of: ontoportal-clean, agroportal-clean, matportal."
  }
}

variable "additional_values_files" {
  description = "Additional values files relative to repository root or absolute paths."
  type        = list(string)
  default     = ["values/profiles/k3s-local.yaml"]
}

variable "set_values" {
  description = "Plain Helm set values."
  type        = map(string)
  default     = {}
}

variable "set_sensitive_values" {
  description = "Sensitive Helm set values, for example secrets.apiKey."
  type        = map(string)
  sensitive   = true
  default     = {}
}

variable "create_namespace" {
  description = "Create target namespace before installing the release."
  type        = bool
  default     = true
}


variable "enable_keda" {
  description = "Install KEDA operator and CRDs before deploying OntoPortal KEDA ScaledObjects."
  type        = bool
  default     = false
}

variable "keda_namespace" {
  description = "Namespace for KEDA."
  type        = string
  default     = "keda"
}

variable "keda_chart_version" {
  description = "kedacore/keda Helm chart version."
  type        = string
  default     = "2.20.1"
}

variable "keda_values_file" {
  description = "Values file for the kedacore/keda Helm chart. Defaults to values/addons/keda-operator.yaml."
  type        = string
  default     = "values/addons/keda-operator.yaml"
}

variable "enable_vpa" {
  description = "Install Vertical Pod Autoscaler operator and CRDs before deploying OntoPortal VPA resources."
  type        = bool
  default     = false
}

variable "vpa_namespace" {
  description = "Namespace for Vertical Pod Autoscaler."
  type        = string
  default     = "vpa"
}

variable "vpa_chart_version" {
  description = "Fairwinds vpa Helm chart version."
  type        = string
  default     = "4.12.2"
}

variable "vpa_values_file" {
  description = "Values file for the Fairwinds vpa Helm chart. Defaults to values/addons/vpa-operator.yaml."
  type        = string
  default     = "values/addons/vpa-operator.yaml"
}


variable "enable_monitoring" {
  description = "Install kube-prometheus-stack in monitoring_namespace."
  type        = bool
  default     = false
}

variable "monitoring_namespace" {
  type        = string
  description = "Namespace for kube-prometheus-stack."
  default     = "monitoring"
}

variable "enable_trivy_operator" {
  description = "Install Aqua Trivy Operator."
  type        = bool
  default     = false
}

variable "trivy_namespace" {
  type        = string
  description = "Namespace for Trivy Operator."
  default     = "trivy-system"
}

variable "enable_sonarqube" {
  description = "Install SonarQube Community Build Helm chart. Requires enough CPU/RAM and storage."
  type        = bool
  default     = false
}

variable "sonarqube_namespace" {
  type        = string
  description = "Namespace for SonarQube."
  default     = "sonarqube"
}


variable "enable_loki" {
  description = "Install Grafana Loki in observability_namespace. Development values are monolithic/filesystem; provide production values before real use."
  type        = bool
  default     = false
}

variable "observability_namespace" {
  type        = string
  description = "Namespace for Loki and Grafana Alloy."
  default     = "observability"
}

variable "loki_values_file" {
  description = "Values file for Loki. Defaults to values/addons/loki-monolithic-dev.yaml."
  type        = string
  default     = "values/addons/loki-monolithic-dev.yaml"
}

variable "enable_grafana_alloy" {
  description = "Install Grafana Alloy for log collection to Loki."
  type        = bool
  default     = false
}

variable "grafana_alloy_values_file" {
  description = "Values file for Grafana Alloy. Defaults to values/addons/grafana-alloy-loki.yaml."
  type        = string
  default     = "values/addons/grafana-alloy-loki.yaml"
}

variable "enable_cert_manager" {
  description = "Install cert-manager as a platform add-on."
  type        = bool
  default     = false
}

variable "cert_manager_namespace" {
  type        = string
  description = "Namespace for cert-manager."
  default     = "cert-manager"
}

variable "enable_external_secrets" {
  description = "Install External Secrets Operator as a platform add-on."
  type        = bool
  default     = false
}

variable "external_secrets_namespace" {
  type        = string
  description = "Namespace for External Secrets Operator."
  default     = "external-secrets"
}

variable "enable_kyverno" {
  description = "Install Kyverno as an optional policy engine."
  type        = bool
  default     = false
}

variable "kyverno_namespace" {
  type        = string
  description = "Namespace for Kyverno."
  default     = "kyverno"
}

variable "enable_velero" {
  description = "Install Velero. Requires provider-specific values and credentials before production use."
  type        = bool
  default     = false
}

variable "velero_namespace" {
  type        = string
  description = "Namespace for Velero."
  default     = "velero"
}

variable "velero_values_file" {
  description = "Provider-specific values file for Velero. Required when enable_velero=true."
  type        = string
  default     = ""
}
