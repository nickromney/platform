resource "kubernetes_namespace_v1" "gitea" {
  count = var.enable_gitea ? 1 : 0

  metadata {
    name = "gitea"
    labels = {
      "kyverno.io/isolate" = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubernetes_namespace_v1" "headlamp" {
  count = var.enable_headlamp ? 1 : 0

  metadata {
    name = "headlamp"
    labels = {
      "kyverno.io/isolate" = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubernetes_namespace_v1" "gitea_runner" {
  count = var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0

  metadata {
    name = "gitea-runner"
    labels = {
      "app.kubernetes.io/name"       = "gitea-actions-runner"
      "app.kubernetes.io/part-of"    = "gitea"
      "app.kubernetes.io/managed-by" = "terraform"
      "kyverno.io/isolate"           = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubernetes_namespace_v1" "dev" {
  count = var.enable_argocd && (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) ? 1 : 0

  metadata {
    name = "dev"
    labels = {
      "app.kubernetes.io/name"       = "dev"
      "app.kubernetes.io/managed-by" = "terraform"
      "kyverno.io/isolate"           = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubernetes_namespace_v1" "uat" {
  count = var.enable_argocd && (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) ? 1 : 0

  metadata {
    name = "uat"
    labels = {
      "app.kubernetes.io/name"       = "uat"
      "app.kubernetes.io/managed-by" = "terraform"
      "kyverno.io/isolate"           = "true"
      "security-tier"                = "strict"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubernetes_namespace_v1" "apim" {
  count = var.enable_argocd && local.enable_subnetcalc_workloads_effective ? 1 : 0

  metadata {
    name = "apim"
    labels = {
      "app.kubernetes.io/component"  = "apim"
      "app.kubernetes.io/name"       = "apim"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["argocd.argoproj.io/tracking-id"],
    ]
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}
