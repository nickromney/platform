# App-of-apps bootstrap:
# - The policies repo (seeded into in-cluster Gitea) holds a directory of manifests.
# - This root Application syncs that directory, which can include child Argo CD Applications.
# - It is gated by enable_app_of_apps so lower stages can run without GitOps app sync.

resource "kubectl_manifest" "argocd_app_of_apps" {
  count = var.enable_app_of_apps && local.enable_gitops_repo && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: app-of-apps
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${var.argocd_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/argocd-apps
    directory:
      recurse: true
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
      - ServerSideApply=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    helm_release.argocd,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.wait_for_gateway_bootstrap_crds,
    # If actions-runner is enabled, ensure its secret exists before Argo starts
    # syncing the GitOps app-of-apps tree that includes the runner Application.
    kubernetes_secret_v1.gitea_runner,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
  ]
}
