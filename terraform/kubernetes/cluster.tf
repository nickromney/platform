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

  content = trimspace(join("\n", compact([
    "server = \"${var.gitea_registry_scheme}://${var.gitea_registry_host}\"",
    "",
    "[host.\"${var.gitea_registry_scheme}://${local.gitea_registry_node_host_effective}\"]",
    "  capabilities = [\"pull\", \"resolve\"]",
    var.gitea_registry_scheme == "http" ? "  skip_verify = true" : "",
  ])))
}

resource "local_file" "containerd_hosts_host_local_registry" {
  count = var.provision_kind_cluster && local.host_local_registry_enabled ? 1 : 0

  filename             = "${local.containerd_certs_dir}/${local.host_local_registry_host_effective}/hosts.toml"
  directory_permission = "0755"
  file_permission      = "0644"

  content = trimspace(join("\n", compact([
    "server = \"${local.host_local_registry_scheme_effective}://${local.host_local_registry_host_effective}\"",
    "",
    "[host.\"${local.host_local_registry_scheme_effective}://${local.host_local_registry_host_effective}\"]",
    "  capabilities = [\"pull\", \"resolve\"]",
    local.host_local_registry_scheme_effective == "http" ? "  skip_verify = true" : "",
  ])))
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
    local_file.containerd_hosts_host_local_registry,
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
    cluster_id            = kind_cluster.local[0].id
    preload_script        = filesha256("${path.module}/scripts/preload-images.sh")
    preload_image_set     = filesha256(local.preload_image_list_path_effective)
    preload_image_list    = local.preload_image_list_path_effective
    enable_signoz         = tostring(var.enable_signoz)
    enable_prometheus     = tostring(var.enable_prometheus)
    enable_grafana        = tostring(var.enable_grafana)
    enable_loki           = tostring(var.enable_loki)
    enable_victoria_logs  = tostring(var.enable_victoria_logs)
    enable_tempo          = tostring(var.enable_tempo)
    enable_headlamp       = tostring(var.enable_headlamp)
    enable_sso            = tostring(var.enable_sso)
    enable_actions_runner = tostring(var.enable_actions_runner)
    preload_parallelism   = tostring(var.image_preload_parallelism)
  }

  provisioner "local-exec" {
    command = "${path.module}/scripts/preload-images.sh --cluster ${var.cluster_name} --parallelism ${var.image_preload_parallelism} --image-list \"$PRELOAD_IMAGE_LIST\""
    environment = {
      PRELOAD_IMAGE_LIST            = local.preload_image_list_path_effective
      PRELOAD_ENABLE_SIGNOZ         = tostring(var.enable_signoz)
      PRELOAD_ENABLE_PROMETHEUS     = tostring(var.enable_prometheus)
      PRELOAD_ENABLE_GRAFANA        = tostring(var.enable_grafana)
      PRELOAD_ENABLE_LOKI           = tostring(var.enable_loki)
      PRELOAD_ENABLE_VICTORIA_LOGS  = tostring(var.enable_victoria_logs)
      PRELOAD_ENABLE_TEMPO          = tostring(var.enable_tempo)
      PRELOAD_ENABLE_HEADLAMP       = tostring(var.enable_headlamp)
      PRELOAD_ENABLE_SSO            = tostring(var.enable_sso)
      PRELOAD_ENABLE_ACTIONS_RUNNER = tostring(var.enable_actions_runner)
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
    null_resource.kind_restart_containerd_on_registry_config_change,
  ]
}

resource "null_resource" "kind_restart_containerd_on_registry_config_change" {
  count = var.provision_kind_cluster ? 1 : 0

  triggers = {
    cluster_id                 = kind_cluster.local[0].id
    dockerio_hosts_toml_sha    = sha256(local_file.containerd_hosts_dockerio[0].content)
    gitea_registry_host        = var.gitea_registry_host
    gitea_registry_node_host   = local.gitea_registry_node_host_effective
    gitea_hosts_toml_sha       = sha256(local_file.containerd_hosts_gitea[0].content)
    host_local_registry_host   = local.host_local_registry_host_effective
    host_local_registry_scheme = local.host_local_registry_scheme_effective
    host_local_registry_sha    = local.host_local_registry_enabled ? sha256(local_file.containerd_hosts_host_local_registry[0].content) : ""
  }

  provisioner "local-exec" {
    command = <<-EOT
      set -eu
      kind get nodes --name "${var.cluster_name}" | while IFS= read -r node; do
        [ -n "$${node}" ] || continue
        echo "Restarting containerd on $${node}..."
        timeout 60 docker exec "$${node}" sh -lc 'set -eu; systemctl restart containerd; systemctl is-active containerd >/dev/null'
      done
      if [ "$${KIND_DISABLE_DEFAULT_CNI}" = "true" ]; then
        echo "Default CNI disabled; waiting for kind nodes to register before CNI install..."
        timeout 120 sh -eu -c '
          while :; do
            node_count="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d " ")"
            if [ "$${node_count}" -ge "$${EXPECTED_KIND_NODE_COUNT}" ]; then
              exit 0
            fi
            sleep 2
          done
        '
      else
        echo "Waiting for nodes to become Ready..."
        timeout 240 kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
      fi
    EOT
    environment = {
      EXPECTED_KIND_NODE_COUNT = tostring(var.worker_count + 1)
      KIND_DISABLE_DEFAULT_CNI = tostring(local.kind_disable_default_cni)
      KUBECONFIG               = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    kind_cluster.local,
    local_sensitive_file.kubeconfig,
    local_file.containerd_hosts_dockerio,
    local_file.containerd_hosts_gitea,
    local_file.containerd_hosts_host_local_registry,
  ]
}
