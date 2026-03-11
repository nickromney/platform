resource "kubectl_manifest" "argocd_app_headlamp" {
  count = var.enable_headlamp && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: headlamp
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${kubernetes_namespace_v1.headlamp[0].metadata[0].name}
    server: https://kubernetes.default.svc
  source:
    repoURL: https://kubernetes-sigs.github.io/headlamp/
    chart: headlamp
    targetRevision: ${var.headlamp_chart_version}
    helm:
      releaseName: headlamp
      valuesObject: ${jsonencode(local.headlamp_values)}
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
    kubernetes_namespace_v1.headlamp,
    kubernetes_secret_v1.headlamp_mkcert_ca,
  ]
}
