resource "kubernetes_namespace_v1" "agentgateway" {
  count = var.enable_agentgateway_ai_gateway ? 1 : 0

  metadata {
    name = var.agentgateway_namespace
    labels = {
      "app.kubernetes.io/name"                             = "agentgateway"
      "app.kubernetes.io/component"                        = "ai-gateway-control-plane"
      "platform.publiccloudexperiments.net/namespace-role" = "shared"
      "platform.publiccloudexperiments.net/sensitivity"    = "internal"
      "kyverno.io/isolate"                                 = "true"
    }
  }

  depends_on = [
    kind_cluster.local,
    null_resource.ensure_kind_kubeconfig,
  ]
}

resource "kubectl_manifest" "argocd_app_agentgateway_crds" {
  count = var.enable_agentgateway_ai_gateway && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: agentgateway-crds
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "68"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${var.agentgateway_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/vendor/charts/agentgateway-crds
    helm:
      releaseName: agentgateway-crds
      skipCrds: false
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubernetes_namespace_v1.agentgateway,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    null_resource.wait_for_gateway_bootstrap_crds,
    kubectl_manifest.argocd_app_cilium_policies,
  ]
}

resource "kubectl_manifest" "argocd_app_agentgateway" {
  count = var.enable_agentgateway_ai_gateway && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: agentgateway
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "69"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${var.agentgateway_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/vendor/charts/agentgateway
    helm:
      releaseName: agentgateway
      skipCrds: false
      values: |
        podSecurityContext:
          seccompProfile:
            type: RuntimeDefault
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          seccompProfile:
            type: RuntimeDefault
          capabilities:
            drop:
              - ALL
      parameters:
        - name: controller.extraEnv.KGW_ENABLE_GATEWAY_API_EXPERIMENTAL_FEATURES
          value: "true"
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubernetes_namespace_v1.agentgateway,
    kubectl_manifest.argocd_app_agentgateway_crds,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    null_resource.wait_for_gateway_bootstrap_crds,
    kubectl_manifest.argocd_app_cilium_policies,
  ]
}

resource "kubectl_manifest" "argocd_app_agentgateway_ai_gateway" {
  count = var.enable_agentgateway_ai_gateway && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: agentgateway-ai-gateway
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "73"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: ${var.agentgateway_namespace}
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/agentgateway-ai-gateway
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
    kubectl_manifest.argocd_app_agentgateway,
    kubernetes_namespace_v1.agentgateway,
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubectl_manifest.argocd_app_cilium_policies,
  ]
}
