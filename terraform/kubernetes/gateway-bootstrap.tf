data "kubectl_file_documents" "gateway_api_crds" {
  count = var.enable_gateway_tls ? 1 : 0

  content = file("${path.module}/apps/nginx-gateway-fabric-crds/gateway-api-crds.yaml")
}

data "kubectl_file_documents" "nginx_gateway_fabric_crds" {
  count = var.enable_gateway_tls ? 1 : 0

  content = file("${path.module}/apps/nginx-gateway-fabric-crds/crds.yaml")
}

locals {
  gateway_bootstrap_crd_manifests = var.enable_gateway_tls ? merge(
    data.kubectl_file_documents.gateway_api_crds[0].manifests,
    data.kubectl_file_documents.nginx_gateway_fabric_crds[0].manifests,
  ) : {}

  gateway_bootstrap_crd_names = var.enable_gateway_tls ? sort(distinct(concat(
    [for doc in data.kubectl_file_documents.gateway_api_crds[0].documents : yamldecode(doc).metadata.name],
    [for doc in data.kubectl_file_documents.nginx_gateway_fabric_crds[0].documents : yamldecode(doc).metadata.name],
  ))) : []
}

resource "kubectl_manifest" "gateway_bootstrap_crds" {
  for_each = local.gateway_bootstrap_crd_manifests

  yaml_body = each.value

  wait              = true
  validate_schema   = false
  force_conflicts   = true
  server_side_apply = true

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "null_resource" "wait_for_gateway_bootstrap_crds" {
  count = var.enable_gateway_tls ? 1 : 0

  triggers = {
    crd_names          = join(",", local.gateway_bootstrap_crd_names)
    kubeconfig_path    = local.kubeconfig_path_for_providers
    kubeconfig_context = local.kubeconfig_context_for_providers != null ? local.kubeconfig_context_for_providers : ""
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = <<-EOT
      set -euo pipefail
      export KUBECONFIG="${local.kubeconfig_path_for_providers}"
      KUBE_CONTEXT="${local.kubeconfig_context_for_providers != null ? local.kubeconfig_context_for_providers : ""}"
      KUBECTL_ARGS=""
      if [[ -n "$${KUBE_CONTEXT}" ]]; then
        KUBECTL_ARGS="--context $${KUBE_CONTEXT}"
      fi

      for crd in ${join(" ", local.gateway_bootstrap_crd_names)}; do
        kubectl $${KUBECTL_ARGS} wait --for=condition=Established --timeout=180s "crd/$${crd}"
      done
    EOT
  }

  depends_on = [
    kubectl_manifest.gateway_bootstrap_crds,
  ]
}

resource "kubectl_manifest" "namespace_platform_gateway" {
  count = var.enable_gateway_tls ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: v1
kind: Namespace
metadata:
  name: platform-gateway
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = true

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}

resource "kubernetes_service_v1" "platform_gateway_nginx_internal" {
  count = var.enable_sso ? 1 : 0

  metadata {
    name      = "platform-gateway-nginx-internal"
    namespace = "platform-gateway"
  }

  spec {
    type = "ClusterIP"

    selector = {
      "app.kubernetes.io/instance"             = "nginx-gateway"
      "app.kubernetes.io/managed-by"           = "nginx-gateway-nginx"
      "app.kubernetes.io/name"                 = "platform-gateway-nginx"
      "gateway.networking.k8s.io/gateway-name" = "platform-gateway"
    }

    port {
      name        = "https"
      port        = 443
      target_port = 443
      protocol    = "TCP"
    }

    dynamic "port" {
      for_each = var.gateway_https_host_port == 443 ? [] : [var.gateway_https_host_port]

      content {
        name        = "https-host-port"
        port        = port.value
        target_port = 443
        protocol    = "TCP"
      }
    }
  }

  depends_on = [
    kubectl_manifest.namespace_platform_gateway,
  ]
}
