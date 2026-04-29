resource "kubectl_manifest" "argocd_app_apim" {
  count = local.enable_subnetcalc_workloads_effective && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: apim
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "72"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: apim
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/apim
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubectl_manifest.argocd_app_cilium_policies,
    null_resource.wait_subnetcalc_images,
  ]
}

resource "kubectl_manifest" "namespace_idp" {
  count = var.enable_sso && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Namespace
metadata:
  name: idp
  labels:
    platform.publiccloudexperiments.net/namespace-role: platform
    platform.publiccloudexperiments.net/sensitivity: internal
    kyverno.io/isolate: "true"
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

resource "kubectl_manifest" "namespace_mcp" {
  count = var.enable_sso && local.enable_subnetcalc_workloads_effective && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Namespace
metadata:
  name: mcp
  labels:
    platform.publiccloudexperiments.net/namespace-role: shared
    platform.publiccloudexperiments.net/sensitivity: internal
    kyverno.io/isolate: "true"
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

resource "kubectl_manifest" "argocd_app_idp" {
  count = var.enable_sso && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: idp
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "78"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: idp
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/idp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubectl_manifest.namespace_idp,
    kubernetes_secret_v1.backstage_gitea_credentials,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubectl_manifest.argocd_app_cilium_policies,
  ]
}

resource "kubectl_manifest" "argocd_app_mcp" {
  count = var.enable_sso && local.enable_subnetcalc_workloads_effective && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: mcp
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "79"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: mcp
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/mcp
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubectl_manifest.namespace_mcp,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubectl_manifest.argocd_app_cilium_policies,
    kubectl_manifest.argocd_app_apim,
  ]
}

resource "kubectl_manifest" "argocd_app_dev" {
  count = (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: dev
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "74"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: dev
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubectl_manifest.argocd_app_cilium_policies,
    kubectl_manifest.argocd_app_apim,
    null_resource.wait_sentiment_images,
    null_resource.wait_subnetcalc_images,
  ]
}

resource "kubectl_manifest" "argocd_app_uat" {
  count = (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: uat
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "76"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: uat
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/uat
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
    retry:
      limit: 5
      backoff:
        duration: 10s
        factor: 2
        maxDuration: 3m
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubectl_manifest.argocd_app_cilium_policies,
    kubectl_manifest.argocd_app_apim,
    null_resource.wait_sentiment_images,
    null_resource.wait_subnetcalc_images,
  ]
}
