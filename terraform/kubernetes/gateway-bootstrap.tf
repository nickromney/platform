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

resource "kubernetes_service" "platform_gateway_nginx_internal" {
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
  }

  depends_on = [
    kubectl_manifest.namespace_platform_gateway,
  ]
}

