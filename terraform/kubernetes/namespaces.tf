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
    null_resource.ensure_kind_kubeconfig,
  ]
}

# Kyverno generates a default-deny NetworkPolicy for every isolated namespace,
# and the allow rules that reopen Gitea arrive as Cilium policies through Argo
# CD, which reaches Gitea over this very path. An apply that stops between the
# two seals Gitea off and cannot recover: Argo cannot read the repository that
# holds the policy that would let it read the repository. This Terraform-owned
# allow keeps the bootstrap path open without weakening the default-deny.
resource "kubernetes_network_policy_v1" "gitea_argocd_bootstrap" {
  count = var.enable_gitea && var.enable_argocd ? 1 : 0

  metadata {
    name      = "allow-argocd-bootstrap"
    namespace = kubernetes_namespace_v1.gitea[0].metadata[0].name
  }

  spec {
    pod_selector {
      match_labels = {
        "app.kubernetes.io/name" = "gitea"
      }
    }

    policy_types = ["Ingress"]

    ingress {
      from {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.argocd_namespace
          }
        }
      }

      ports {
        port     = "3000"
        protocol = "TCP"
      }

      ports {
        port     = "2222"
        protocol = "TCP"
      }
    }
  }

  depends_on = [
    kubernetes_namespace_v1.gitea,
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
    null_resource.ensure_kind_kubeconfig,
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
    null_resource.ensure_kind_kubeconfig,
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
    null_resource.ensure_kind_kubeconfig,
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
    null_resource.ensure_kind_kubeconfig,
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
    null_resource.ensure_kind_kubeconfig,
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
    null_resource.ensure_kind_kubeconfig,
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
    null_resource.ensure_kind_kubeconfig,
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
    null_resource.ensure_kind_kubeconfig,
  ]
}

resource "kubernetes_namespace_v1" "review" {
  count = local.enable_review_environments ? 1 : 0

  metadata {
    name = local.review_environment_contract.namespace
    labels = {
      "app.kubernetes.io/name"                                  = "review"
      "app.kubernetes.io/managed-by"                            = "terraform"
      "platform.publiccloudexperiments.net/namespace-role"      = "application"
      "platform.publiccloudexperiments.net/environment"         = local.review_environment_contract.namespace
      "platform.publiccloudexperiments.net/environment-purpose" = "branch-preview"
      "kyverno.io/isolate"                                      = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    null_resource.ensure_kind_kubeconfig,
  ]
}

resource "kubernetes_namespace_v1" "apim" {
  count = var.enable_argocd && local.enable_apim_simulator_effective ? 1 : 0

  metadata {
    name = "apim"
    labels = {
      "app.kubernetes.io/component"                        = "apim"
      "app.kubernetes.io/name"                             = "apim"
      "app.kubernetes.io/managed-by"                       = "terraform"
      "platform.publiccloudexperiments.net/namespace-role" = "shared"
      "kyverno.io/isolate"                                 = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      metadata[0].annotations["argocd.argoproj.io/tracking-id"],
    ]
  }

  depends_on = [
    kind_cluster.local,
    null_resource.ensure_kind_kubeconfig,
  ]
}

