resource "kubectl_manifest" "argocd_server_hostaliases" {
  count = var.enable_sso && var.enable_argocd ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: apps/v1
kind: Deployment
metadata:
  name: argocd-server
  namespace: ${var.argocd_namespace}
spec:
  template:
    spec:
      hostAliases:
        - ip: ${kubernetes_service_v1.platform_gateway_nginx_internal[0].spec[0].cluster_ip}
          hostnames:
            - ${local.dex_public_host}
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = true
  server_side_apply = true

  depends_on = [
    helm_release.argocd,
    kubernetes_service_v1.platform_gateway_nginx_internal,
  ]
}

resource "kubectl_manifest" "headlamp_hostaliases" {
  count = var.enable_sso && var.enable_headlamp ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: apps/v1
kind: Deployment
metadata:
  name: headlamp
  namespace: ${kubernetes_namespace_v1.headlamp[0].metadata[0].name}
spec:
  template:
    spec:
      hostAliases:
        - ip: ${kubernetes_service_v1.platform_gateway_nginx_internal[0].spec[0].cluster_ip}
          hostnames:
            - ${local.dex_public_host}
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = true
  server_side_apply = true

  depends_on = [
    null_resource.wait_headlamp_deployment,
    kubectl_manifest.argocd_app_headlamp,
    kubernetes_service_v1.platform_gateway_nginx_internal,
  ]
}

resource "null_resource" "wait_headlamp_deployment" {
  count = var.enable_sso && var.enable_headlamp ? 1 : 0

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail

      ns="${kubernetes_namespace_v1.headlamp[0].metadata[0].name}"
      for i in {1..300}; do
        if kubectl -n "${kubernetes_namespace_v1.headlamp[0].metadata[0].name}" get deploy headlamp >/dev/null 2>&1; then
          kubectl -n "${kubernetes_namespace_v1.headlamp[0].metadata[0].name}" rollout status deploy/headlamp --timeout=600s
          exit 0
        fi
        sleep 2
      done

      echo "Timed out waiting for deployment/headlamp in namespace ${kubernetes_namespace_v1.headlamp[0].metadata[0].name}" >&2
      kubectl -n "${kubernetes_namespace_v1.headlamp[0].metadata[0].name}" get all || true
      exit 1
    EOT
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    local_sensitive_file.kubeconfig,
    kubectl_manifest.argocd_app_headlamp,
  ]
}
