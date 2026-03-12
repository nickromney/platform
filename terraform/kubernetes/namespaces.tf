resource "kubernetes_namespace_v1" "gitea" {
  count = var.enable_gitea ? 1 : 0

  metadata {
    name = "gitea"
    labels = {
      "platform.publiccloudexperiments.net/namespace-role" = "platform"
      "kyverno.io/isolate"                                 = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubectl_manifest" "namespace_cert_manager" {
  count = (var.enable_cert_manager || var.enable_gateway_tls) && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Namespace
metadata:
  name: cert-manager
  labels:
    "platform.publiccloudexperiments.net/namespace-role": platform
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubectl_manifest" "namespace_kyverno" {
  count = var.enable_policies && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Namespace
metadata:
  name: kyverno
  labels:
    "platform.publiccloudexperiments.net/namespace-role": platform
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubectl_manifest" "namespace_policy_reporter" {
  count = var.enable_policies && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Namespace
metadata:
  name: policy-reporter
  labels:
    "platform.publiccloudexperiments.net/namespace-role": platform
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

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
      "platform.publiccloudexperiments.net/namespace-role" = "platform"
      "kyverno.io/isolate"                                 = "true"
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
      "app.kubernetes.io/name"                             = "gitea-actions-runner"
      "app.kubernetes.io/part-of"                          = "gitea"
      "app.kubernetes.io/managed-by"                       = "terraform"
      "platform.publiccloudexperiments.net/namespace-role" = "platform"
      "kyverno.io/isolate"                                 = "true"
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
      "app.kubernetes.io/name"                             = "dev"
      "app.kubernetes.io/managed-by"                       = "terraform"
      "platform.publiccloudexperiments.net/namespace-role" = "application"
      "platform.publiccloudexperiments.net/environment"    = "dev"
      "kyverno.io/isolate"                                 = "true"
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
      "app.kubernetes.io/name"                             = "uat"
      "app.kubernetes.io/managed-by"                       = "terraform"
      "platform.publiccloudexperiments.net/namespace-role" = "application"
      "platform.publiccloudexperiments.net/environment"    = "uat"
      "platform.publiccloudexperiments.net/sensitivity"    = "private"
      "kyverno.io/isolate"                                 = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubernetes_namespace_v1" "sit" {
  count = var.enable_argocd ? 1 : 0

  metadata {
    name = "sit"
    labels = {
      "app.kubernetes.io/name"                             = "sit"
      "app.kubernetes.io/managed-by"                       = "terraform"
      "platform.publiccloudexperiments.net/namespace-role" = "application"
      "platform.publiccloudexperiments.net/environment"    = "sit"
      "kyverno.io/isolate"                                 = "true"
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
      "app.kubernetes.io/component"                        = "apim"
      "app.kubernetes.io/name"                             = "apim"
      "app.kubernetes.io/managed-by"                       = "terraform"
      "platform.publiccloudexperiments.net/namespace-role" = "shared"
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
