# kind bakes extraPortMappings at cluster creation and cannot gain one later, so
# the host 443 mapping has to name the right container port up front.
#
# NGINX Gateway Fabric is reached through a NodePort, but Cilium's Gateway
# listener binds 443 directly on the node's host network and has no NodePort at
# all. Aiming host 443 at the NodePort under Cilium publishes a port nothing
# listens on: the gateway is healthy inside the cluster and every route is dead
# from the host. These pin which container port each mode publishes.

variables {
  cni_provider  = "cilium"
  enable_hubble = false
  enable_argocd = false
  enable_gitea  = false
}

run "nginx_mode_publishes_the_gateway_nodeport" {
  command = plan

  variables {
    cilium_gateway_api = false
  }

  assert {
    condition     = local.gateway_https_container_port == var.gateway_https_node_port
    error_message = "Expected the NGINX path to publish host 443 from the gateway NodePort"
  }

  assert {
    condition = anytrue([
      for m in local.extra_port_mappings :
      m.name == "gateway-https" && m.container_port == var.gateway_https_node_port && m.host_port == var.gateway_https_host_port
    ])
    error_message = "Expected a gateway-https mapping from the NodePort to the gateway host port"
  }
}

run "cilium_mode_publishes_the_host_network_listener" {
  command = plan

  variables {
    cilium_gateway_api            = true
    cilium_kube_proxy_replacement = true
  }

  assert {
    condition     = local.gateway_https_container_port == 443
    error_message = "Expected Cilium mode to publish host 443 from container 443, not the NodePort"
  }

  assert {
    condition = anytrue([
      for m in local.extra_port_mappings :
      m.name == "gateway-https" && m.container_port == 443 && m.host_port == var.gateway_https_host_port
    ])
    error_message = "Expected the gateway-https mapping to target Cilium's host-network listener"
  }

  # Only one mapping may claim the gateway host port; two would fail at cluster
  # creation, which is how the earlier parallel-listener design broke.
  assert {
    condition = length([
      for m in local.extra_port_mappings : m if m.host_port == var.gateway_https_host_port
    ]) == 1
    error_message = "Expected exactly one mapping to claim the gateway host port"
  }
}
