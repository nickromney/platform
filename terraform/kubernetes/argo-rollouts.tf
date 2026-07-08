resource "kubernetes_namespace_v1" "argo_rollouts" {
  count = var.enable_progressive_delivery ? 1 : 0

  metadata {
    name = "argo-rollouts"
    labels = {
      "app.kubernetes.io/name"                             = "argo-rollouts"
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

resource "kubectl_manifest" "argocd_app_argo_rollouts" {
  count = var.enable_progressive_delivery && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: argo-rollouts
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "86"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${kubernetes_namespace_v1.argo_rollouts[0].metadata[0].name}
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.argo_rollouts}
    helm:
      releaseName: argo-rollouts
      values: |
        controller:
          image:
            registry: quay.io
            repository: argoproj/argo-rollouts
            tag: v1.9.0
          trafficRouterPlugins:
            - name: argoproj-labs/gatewayAPI
              location: https://github.com/argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi/releases/download/v0.5.0/gatewayapi-plugin-linux-amd64
        dashboard:
          enabled: true
  ignoreDifferences:
    - group: apiextensions.k8s.io
      kind: CustomResourceDefinition
      jsonPointers:
        - /spec/preserveUnknownFields
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
      - RespectIgnoreDifferences=true
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
    kubernetes_namespace_v1.argo_rollouts,
  ]
}
