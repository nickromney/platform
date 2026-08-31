data "kubectl_file_documents" "gateway_api_crds" {
  count = var.enable_gateway_tls || var.enable_agentgateway_ai_gateway ? 1 : 0

  content = file("${local.stack_dir}/apps/nginx-gateway-fabric-crds/gateway-api-crds.yaml")
}

data "kubectl_file_documents" "nginx_gateway_fabric_crds" {
  count = var.enable_gateway_tls ? 1 : 0

  content = file("${local.stack_dir}/apps/nginx-gateway-fabric-crds/crds.yaml")
}

locals {
  gateway_bootstrap_crd_manifests = var.enable_gateway_tls || var.enable_agentgateway_ai_gateway ? merge(
    data.kubectl_file_documents.gateway_api_crds[0].manifests,
    var.enable_gateway_tls ? data.kubectl_file_documents.nginx_gateway_fabric_crds[0].manifests : {},
  ) : {}

  # Only CustomResourceDefinitions, because the readiness wait below polls
  # `kubectl get crd <name>`. The upstream Gateway API bundle also ships a
  # ValidatingAdmissionPolicy and its Binding, both named
  # safe-upgrades.gateway.networking.k8s.io. Taking every document's name waits
  # for a CRD that will never exist, which costs the wait its full timeout on
  # every apply.
  gateway_bootstrap_crd_names = var.enable_gateway_tls || var.enable_agentgateway_ai_gateway ? sort(distinct(concat(
    [for doc in data.kubectl_file_documents.gateway_api_crds[0].documents : yamldecode(doc).metadata.name if yamldecode(doc).kind == "CustomResourceDefinition"],
    var.enable_gateway_tls ? [for doc in data.kubectl_file_documents.nginx_gateway_fabric_crds[0].documents : yamldecode(doc).metadata.name if yamldecode(doc).kind == "CustomResourceDefinition"] : [],
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
    null_resource.ensure_kind_kubeconfig,
  ]
}

resource "null_resource" "wait_for_gateway_bootstrap_crds" {
  count = var.enable_gateway_tls || var.enable_agentgateway_ai_gateway ? 1 : 0

  triggers = {
    crd_names          = join(",", local.gateway_bootstrap_crd_names)
    kubeconfig_path    = local.kubeconfig_path_for_providers
    kubeconfig_context = local.kubeconfig_context_for_providers != null ? local.kubeconfig_context_for_providers : ""
    script_sha         = filesha256("${local.stack_dir}/scripts/wait-for-gateway-crds.sh")
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-lc"]
    command     = "bash \"${local.stack_dir}/scripts/wait-for-gateway-crds.sh\" --execute"
    environment = {
      KUBECONFIG   = local.kubeconfig_path_for_providers
      KUBE_CONTEXT = local.kubeconfig_context_for_providers != null ? local.kubeconfig_context_for_providers : ""
      CRD_NAMES    = join(" ", local.gateway_bootstrap_crd_names)
    }
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
    null_resource.ensure_kind_kubeconfig,
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
