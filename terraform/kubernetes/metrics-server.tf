resource "kubernetes_namespace_v1" "metrics_server" {
  count = var.enable_metrics_server ? 1 : 0

  metadata {
    name = "metrics-server"
    labels = {
      "app.kubernetes.io/name"                             = "metrics-server"
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

resource "kubectl_manifest" "argocd_app_metrics_server" {
  count = var.enable_metrics_server && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: metrics-server
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "88"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${kubernetes_namespace_v1.metrics_server[0].metadata[0].name}
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.metrics_server}
    helm:
      releaseName: metrics-server
      values: |
        image:
          repository: registry.k8s.io/metrics-server/metrics-server
          tag: ${var.metrics_server_image_tag}
        args:
          - --kubelet-insecure-tls
        resources:
          requests:
            cpu: 100m
            memory: 200Mi
          limits:
            cpu: 250m
            memory: 300Mi
        podLabels:
          app.kubernetes.io/part-of: platform-observability
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubernetes_namespace_v1.metrics_server,
  ]
}
