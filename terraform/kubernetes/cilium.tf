resource "null_resource" "hubble_ui_service_legacy_cleanup" {
  count = local.enable_cilium_effective && var.enable_hubble ? 1 : 0

  triggers = {
    node_port = var.hubble_ui_node_port
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      if ! kubectl get service hubble-ui -n kube-system >/dev/null 2>&1; then
        exit 0
      fi
      # Older runs rewrote hubble-ui to port 8080. Normalize back to chart-native
      # port 80 before Helm upgrades to avoid duplicate nodePort patch failures.
      kubectl patch service hubble-ui -n kube-system --type=json \
        -p '[{"op":"replace","path":"/spec/ports","value":[{"name":"http","port":80,"protocol":"TCP","targetPort":8081,"nodePort":${var.hubble_ui_node_port}}]}]'
    EOT
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = local.kubeconfig_path_expanded
    }
  }
}

resource "helm_release" "cilium" {
  count = local.enable_cilium_effective ? 1 : 0

  name       = "cilium"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version
  namespace  = "kube-system"

  wait            = true
  wait_for_jobs   = true
  atomic          = true
  cleanup_on_fail = true
  timeout         = 1800

  values = [yamlencode(local.cilium_values)]

  depends_on = [
    kind_cluster.local,
    null_resource.ensure_kind_kubeconfig,
    null_resource.preload_images,
    null_resource.hubble_ui_service_legacy_cleanup,
  ]
}

resource "null_resource" "hubble_ui_backend_relay_port_patch" {
  count = local.enable_cilium_effective && var.enable_hubble ? 1 : 0

  triggers = {
    chart_version      = var.cilium_version
    relay_service_port = tostring(try(local.cilium_values.hubble.relay.servicePort, 4245))
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      if ! kubectl get deployment hubble-ui -n kube-system >/dev/null 2>&1; then
        exit 0
      fi
      # The Cilium chart exposes the relay Service port, but it hardcodes the
      # UI backend's FLOWS_API_ADDR to hubble-relay:80. Patch the deployment so
      # the shipped UI follows the relay Service we expose locally.
      kubectl patch deployment hubble-ui -n kube-system --type=strategic \
        -p '{"spec":{"template":{"spec":{"containers":[{"name":"backend","env":[{"name":"FLOWS_API_ADDR","value":"hubble-relay:${try(local.cilium_values.hubble.relay.servicePort, 4245)}"}]}]}}}}'
      kubectl -n kube-system rollout status deployment/hubble-ui --timeout=300s
    EOT
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    helm_release.cilium,
  ]
}

resource "null_resource" "cilium_restart_on_config_change" {
  count = local.enable_cilium_effective ? 1 : 0

  triggers = {
    chart_version = var.cilium_version
    values_sha    = sha256(yamlencode(local.cilium_values))
  }

  provisioner "local-exec" {
    command     = <<-EOT
      set -euo pipefail
      # Several Cilium features, including WireGuard encryption, are sourced from
      # the rendered ConfigMap but do not take effect until the agent DaemonSet restarts.
      kubectl -n kube-system get daemonset cilium >/dev/null 2>&1 || exit 0
      kubectl -n kube-system rollout restart daemonset/cilium
      kubectl -n kube-system rollout status daemonset/cilium --timeout=300s
    EOT
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    helm_release.cilium,
    null_resource.hubble_ui_backend_relay_port_patch,
  ]
}
