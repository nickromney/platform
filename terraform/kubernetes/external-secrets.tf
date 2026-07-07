resource "kubernetes_namespace_v1" "external_secrets" {
  count = var.enable_external_secrets ? 1 : 0

  metadata {
    name = "external-secrets"
    labels = {
      "app.kubernetes.io/name"                             = "external-secrets"
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

resource "kubectl_manifest" "argocd_app_external_secrets" {
  count = var.enable_external_secrets && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: external-secrets
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "86"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${kubernetes_namespace_v1.external_secrets[0].metadata[0].name}
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.external_secrets}
    helm:
      releaseName: external-secrets
      values: |
        installCRDs: true
        image:
          repository: ghcr.io/external-secrets/external-secrets
          tag: ${var.external_secrets_image_tag}
        webhook:
          image:
            repository: ghcr.io/external-secrets/external-secrets
            tag: ${var.external_secrets_image_tag}
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 128Mi
        certController:
          image:
            repository: ghcr.io/external-secrets/external-secrets
            tag: ${var.external_secrets_image_tag}
          resources:
            requests:
              cpu: 10m
              memory: 32Mi
            limits:
              cpu: 100m
              memory: 128Mi
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            cpu: 100m
            memory: 128Mi
        podLabels:
          app.kubernetes.io/part-of: platform-secrets
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
    kubernetes_namespace_v1.external_secrets,
  ]
}

resource "kubectl_manifest" "argocd_app_eso_demo" {
  count = var.enable_external_secrets && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: eso-demo
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "87"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: eso-demo
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/eso-demo
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
    kubectl_manifest.argocd_app_external_secrets,
  ]
}
