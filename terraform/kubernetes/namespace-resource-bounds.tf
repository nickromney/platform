locals {
  application_namespace_resource_quota_hard = {
    "requests.cpu"               = "4"
    "requests.memory"            = "6Gi"
    "limits.cpu"                 = "8"
    "limits.memory"              = "12Gi"
    "requests.ephemeral-storage" = "4Gi"
    "limits.ephemeral-storage"   = "8Gi"
    "requests.storage"           = "8Gi"
    pods                         = "40"
    persistentvolumeclaims       = "8"
  }

  application_namespace_limit_range_defaults = {
    default = {
      cpu                 = "250m"
      memory              = "256Mi"
      "ephemeral-storage" = "256Mi"
    }
    default_request = {
      cpu                 = "25m"
      memory              = "64Mi"
      "ephemeral-storage" = "64Mi"
    }
  }
}

resource "kubernetes_limit_range_v1" "dev_application_defaults" {
  count = var.enable_namespace_resource_bounds && var.enable_argocd && (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) ? 1 : 0

  metadata {
    name      = "application-container-defaults"
    namespace = kubernetes_namespace_v1.dev[0].metadata[0].name
  }

  spec {
    limit {
      type            = "Container"
      default         = local.application_namespace_limit_range_defaults.default
      default_request = local.application_namespace_limit_range_defaults.default_request
    }
  }
}

resource "kubernetes_resource_quota_v1" "dev_application_quota" {
  count = var.enable_namespace_resource_bounds && var.enable_argocd && (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) ? 1 : 0

  metadata {
    name      = "application-resource-quota"
    namespace = kubernetes_namespace_v1.dev[0].metadata[0].name
  }

  spec {
    hard = local.application_namespace_resource_quota_hard
  }
}

resource "kubernetes_limit_range_v1" "sit_application_defaults" {
  count = var.enable_namespace_resource_bounds && var.enable_argocd ? 1 : 0

  metadata {
    name      = "application-container-defaults"
    namespace = kubernetes_namespace_v1.sit[0].metadata[0].name
  }

  spec {
    limit {
      type            = "Container"
      default         = local.application_namespace_limit_range_defaults.default
      default_request = local.application_namespace_limit_range_defaults.default_request
    }
  }
}

resource "kubernetes_resource_quota_v1" "sit_application_quota" {
  count = var.enable_namespace_resource_bounds && var.enable_argocd ? 1 : 0

  metadata {
    name      = "application-resource-quota"
    namespace = kubernetes_namespace_v1.sit[0].metadata[0].name
  }

  spec {
    hard = local.application_namespace_resource_quota_hard
  }
}

resource "kubernetes_limit_range_v1" "uat_application_defaults" {
  count = var.enable_namespace_resource_bounds && var.enable_argocd && (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) ? 1 : 0

  metadata {
    name      = "application-container-defaults"
    namespace = kubernetes_namespace_v1.uat[0].metadata[0].name
  }

  spec {
    limit {
      type            = "Container"
      default         = local.application_namespace_limit_range_defaults.default
      default_request = local.application_namespace_limit_range_defaults.default_request
    }
  }
}

resource "kubernetes_resource_quota_v1" "uat_application_quota" {
  count = var.enable_namespace_resource_bounds && var.enable_argocd && (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) ? 1 : 0

  metadata {
    name      = "application-resource-quota"
    namespace = kubernetes_namespace_v1.uat[0].metadata[0].name
  }

  spec {
    hard = local.application_namespace_resource_quota_hard
  }
}
