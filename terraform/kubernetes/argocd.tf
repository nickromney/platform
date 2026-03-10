resource "kubernetes_namespace" "argocd" {
  count = var.enable_argocd && var.provision_argocd ? 1 : 0

  metadata {
    name = var.argocd_namespace
    labels = {
      app = "argocd"
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "helm_release" "argocd" {
  count = var.enable_argocd && var.provision_argocd ? 1 : 0

  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_chart_version
  namespace        = var.argocd_namespace
  create_namespace = false

  wait    = true
  timeout = 1800

  values = [yamlencode(local.argocd_values)]

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
    helm_release.cilium,
    kubernetes_namespace.argocd,
  ]
}
