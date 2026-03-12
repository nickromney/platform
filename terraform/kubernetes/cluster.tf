resource "local_file" "containerd_hosts_dockerio" {
  count = var.provision_kind_cluster ? 1 : 0

  filename             = "${local.containerd_certs_dir}/docker.io/hosts.toml"
  directory_permission = "0755"
  file_permission      = "0644"

  # Use Google's Docker Hub mirror (mirror.gcr.io) as primary to avoid rate limits.
  # Falls back to registry-1.docker.io if the mirror doesn't have the image.
  content = trimspace(join("\n", [
    "server = \"https://registry-1.docker.io\"",
    "",
    "# Google's Docker Hub mirror - no rate limits for public images",
    "[host.\"https://mirror.gcr.io\"]",
    "  capabilities = [\"pull\", \"resolve\"]",
    "",
    "# Fallback to Docker Hub directly",
    "[host.\"https://registry-1.docker.io\"]",
    "  capabilities = [\"pull\", \"resolve\"]",
  ]))
}

resource "local_file" "containerd_hosts_gitea" {
  count = var.provision_kind_cluster ? 1 : 0

  filename             = "${local.containerd_certs_dir}/${var.gitea_registry_host}/hosts.toml"
  directory_permission = "0755"
  file_permission      = "0644"

  content = trimspace(join("\n", [
    "server = \"${var.gitea_registry_scheme}://${var.gitea_registry_host}\"",
    "",
    "[host.\"${var.gitea_registry_scheme}://${var.gitea_registry_host}\"]",
    "  capabilities = [\"pull\", \"resolve\"]",
  ]))
}

resource "local_file" "kind_config" {
  count = var.provision_kind_cluster ? 1 : 0

  filename = local.kind_config_path_expanded

  content = templatefile("${path.module}/templates/kind-config.yaml.tpl", {
    workers         = local.kind_workers
    ports           = local.extra_port_mappings
    extra_mounts    = local.kind_extra_mounts
    api_server_port = var.kind_api_server_port
  })
}

resource "kind_cluster" "local" {
  count = var.provision_kind_cluster ? 1 : 0

  name            = var.cluster_name
  wait_for_ready  = false
  kubeconfig_path = local.kubeconfig_path_expanded
  node_image      = var.node_image

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    networking {
      api_server_address  = "127.0.0.1"
      api_server_port     = var.kind_api_server_port
      disable_default_cni = local.kind_disable_default_cni
      kube_proxy_mode     = "iptables"
    }

    node {
      role = "control-plane"

      dynamic "extra_port_mappings" {
        for_each = local.extra_port_mappings
        content {
          container_port = extra_port_mappings.value.container_port
          host_port      = extra_port_mappings.value.host_port
          listen_address = extra_port_mappings.value.listen_address
          protocol       = extra_port_mappings.value.protocol
        }
      }

      dynamic "extra_mounts" {
        for_each = local.kind_extra_mounts
        content {
          host_path      = extra_mounts.value.host_path
          container_path = extra_mounts.value.container_path
          read_only      = extra_mounts.value.read_only
        }
      }
    }

    dynamic "node" {
      for_each = local.kind_workers
      content {
        role = "worker"

        dynamic "extra_mounts" {
          for_each = local.kind_extra_mounts
          content {
            host_path      = extra_mounts.value.host_path
            container_path = extra_mounts.value.container_path
            read_only      = extra_mounts.value.read_only
          }
        }
      }
    }
  }

  depends_on = [
    local_file.containerd_hosts_dockerio,
    local_file.containerd_hosts_gitea,
    local_file.kind_config,
  ]
}

resource "local_sensitive_file" "kubeconfig" {
  count                = var.provision_kind_cluster ? 1 : 0
  content              = kind_cluster.local[0].kubeconfig
  filename             = local.kubeconfig_path_expanded
  file_permission      = "0600"
  directory_permission = "0700"
  depends_on           = [kind_cluster.local]
}

resource "null_resource" "preload_images" {
  count = var.enable_image_preload && var.provision_kind_cluster ? 1 : 0

  triggers = {
    cluster_id        = kind_cluster.local[0].id
    preload_script    = filesha256("${path.module}/scripts/preload-images.sh")
    preload_image_set = filesha256("${path.module}/scripts/preload-images.txt")
    enable_signoz         = tostring(var.enable_signoz)
    enable_prometheus     = tostring(var.enable_prometheus)
    enable_grafana        = tostring(var.enable_grafana)
    enable_loki           = tostring(var.enable_loki)
    enable_tempo          = tostring(var.enable_tempo)
    enable_headlamp       = tostring(var.enable_headlamp)
    enable_sso            = tostring(var.enable_sso)
    enable_actions_runner = tostring(var.enable_actions_runner)
    preload_parallelism   = tostring(var.image_preload_parallelism)
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/preload-images.sh --cluster ${var.cluster_name} --parallelism ${var.image_preload_parallelism}"
    environment = {
      PRELOAD_ENABLE_SIGNOZ         = tostring(var.enable_signoz)
      PRELOAD_ENABLE_PROMETHEUS     = tostring(var.enable_prometheus)
      PRELOAD_ENABLE_GRAFANA        = tostring(var.enable_grafana)
      PRELOAD_ENABLE_LOKI           = tostring(var.enable_loki)
      PRELOAD_ENABLE_TEMPO          = tostring(var.enable_tempo)
      PRELOAD_ENABLE_HEADLAMP       = tostring(var.enable_headlamp)
      PRELOAD_ENABLE_SSO            = tostring(var.enable_sso)
      PRELOAD_ENABLE_ACTIONS_RUNNER = tostring(var.enable_actions_runner)
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
  ]
}
