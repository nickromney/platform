resource "kubectl_manifest" "argocd_app_cert_manager" {
  count = (var.enable_cert_manager || var.enable_gateway_tls) && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "-20"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: cert-manager
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: ${local.vendored_chart_paths.cert_manager}
    helm:
      releaseName: cert-manager
      values: |
        installCRDs: true
        containerSecurityContext:
          runAsNonRoot: true
          runAsUser: 65532
        webhook:
          containerSecurityContext:
            runAsNonRoot: true
            runAsUser: 65532
        cainjector:
          containerSecurityContext:
            runAsNonRoot: true
            runAsUser: 65532
        startupapicheck:
          containerSecurityContext:
            runAsNonRoot: true
            runAsUser: 65532
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
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
  ]
}

resource "null_resource" "bootstrap_mkcert_ca" {
  count = var.enable_gateway_tls ? 1 : 0

  triggers = {
    script_sha     = filesha256(abspath("${path.module}/scripts/bootstrap-mkcert-ca.sh"))
    kubeconfig_sha = fileexists(local.kubeconfig_path_expanded) ? filesha256(local.kubeconfig_path_expanded) : "missing"
  }

  provisioner "local-exec" {
    command     = "bash \"${path.module}/scripts/bootstrap-mkcert-ca.sh\""
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    local_sensitive_file.kubeconfig,
    kubectl_manifest.namespace_cert_manager,
  ]
}

resource "kubectl_manifest" "argocd_app_cert_manager_config" {
  count = var.enable_gateway_tls && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager-config
  namespace: ${var.argocd_namespace}
  annotations:
    argocd.argoproj.io/sync-wave: "5"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: cert-manager
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/cert-manager-config
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - ServerSideApply=true
      - SkipDryRunOnMissingResource=true
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    null_resource.bootstrap_mkcert_ca,
  ]
}
