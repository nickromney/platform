resource "null_resource" "hubble_ui_service_legacy_cleanup" {
  count = local.enable_cilium_effective && var.enable_hubble ? 1 : 0

  triggers = {
    node_port  = var.hubble_ui_node_port
    script_sha = filesha256("${local.stack_dir}/scripts/normalize-hubble-ui-service.sh")
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/normalize-hubble-ui-service.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG          = local.kubeconfig_path_expanded
      HUBBLE_UI_NODE_PORT = tostring(var.hubble_ui_node_port)
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
  timeout         = local.platform_wait_seconds.helm_release

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
    script_sha         = filesha256("${local.stack_dir}/scripts/patch-hubble-ui-relay-addr.sh")
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/patch-hubble-ui-relay-addr.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG              = local.kubeconfig_path_expanded
      FLOWS_API_ADDR          = "hubble-relay:${try(local.cilium_values.hubble.relay.servicePort, 4245)}"
      ROLLOUT_TIMEOUT_SECONDS = tostring(local.platform_wait_seconds.rollout_default)
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
    script_sha    = filesha256("${local.stack_dir}/scripts/restart-cilium-daemonset.sh")
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/restart-cilium-daemonset.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG              = local.kubeconfig_path_expanded
      ROLLOUT_TIMEOUT_SECONDS = tostring(local.platform_wait_seconds.rollout_default)
    }
  }

  depends_on = [
    helm_release.cilium,
    null_resource.hubble_ui_backend_relay_port_patch,
  ]
}
