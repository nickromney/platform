locals {
  kind_workers                      = range(var.worker_count)
  kind_control_plane_container_name = "${var.cluster_name}-control-plane"
  kind_config_path_expanded         = abspath(pathexpand(var.kind_config_path))
  kubeconfig_path_expanded          = abspath(pathexpand(var.kubeconfig_path))
  preload_image_list_path_effective = trimspace(var.preload_image_list_path) != "" ? abspath(pathexpand(var.preload_image_list_path)) : abspath("${path.module}/../../kubernetes/kind/preload-images.txt")

  repo_root         = abspath("${path.module}/../..")
  monorepo_apps_dir = abspath("${local.repo_root}/apps")

  run_dir = abspath("${path.module}/.run")

  gitea_http_host_local             = "127.0.0.1"
  gitea_ssh_host_local              = "127.0.0.1"
  gitea_local_access_mode_effective = lower(var.gitea_local_access_mode)
  gitea_registry_host_parts         = split(":", var.gitea_registry_host)
  gitea_registry_host_name          = lower(trimspace(local.gitea_registry_host_parts[0]))
  gitea_registry_port               = length(local.gitea_registry_host_parts) > 1 ? local.gitea_registry_host_parts[length(local.gitea_registry_host_parts) - 1] : ""
  gitea_registry_node_host_effective = contains(["localhost", "127.0.0.1"], local.gitea_registry_host_name) ? (
    local.gitea_registry_port != "" ? "${local.kind_control_plane_container_name}:${local.gitea_registry_port}" : local.kind_control_plane_container_name
  ) : var.gitea_registry_host

  gitea_ssh_host_cluster                = "gitea-ssh.gitea.svc.cluster.local"
  gitea_ssh_port_cluster                = 22
  gitea_repo_owner                      = var.gitea_repo_owner != "" ? var.gitea_repo_owner : var.gitea_admin_username
  gitea_repo_owner_is_org               = var.gitea_repo_owner_is_org
  gitea_repo_owner_fallback             = var.gitea_repo_owner_is_org ? var.gitea_admin_username : ""
  argocd_oidc_enabled                   = var.enable_sso && var.enable_argocd_oidc
  cni_provider_effective                = lower(var.cni_provider)
  enable_cilium_effective               = local.cni_provider_effective == "cilium"
  platform_base_domain_effective        = lower(trimspace(var.platform_base_domain))
  platform_admin_base_domain_effective  = trimspace(var.platform_admin_base_domain) != "" ? lower(trimspace(var.platform_admin_base_domain)) : local.platform_base_domain_effective
  separate_admin_domain_enabled         = trimspace(var.platform_admin_base_domain) != ""
  admin_cookie_domain                   = ".${local.platform_admin_base_domain_effective}"
  admin_whitelist_domains               = var.gateway_https_host_port == 443 ? local.admin_cookie_domain : "${local.admin_cookie_domain},${local.admin_cookie_domain}:${var.gateway_https_host_port}"
  dev_cookie_domain                     = ".dev.${local.platform_base_domain_effective}"
  dev_whitelist_domains                 = var.gateway_https_host_port == 443 ? local.dev_cookie_domain : "${local.dev_cookie_domain},${local.dev_cookie_domain}:${var.gateway_https_host_port}"
  uat_cookie_domain                     = ".uat.${local.platform_base_domain_effective}"
  uat_whitelist_domains                 = var.gateway_https_host_port == 443 ? local.uat_cookie_domain : "${local.uat_cookie_domain},${local.uat_cookie_domain}:${var.gateway_https_host_port}"
  gateway_https_host_port_suffix        = var.gateway_https_host_port == 443 ? "" : ":${var.gateway_https_host_port}"
  argocd_public_host                    = local.separate_admin_domain_enabled ? "argocd.${local.platform_admin_base_domain_effective}" : "argocd.admin.${local.platform_base_domain_effective}"
  argocd_public_url                     = "https://${local.argocd_public_host}${local.gateway_https_host_port_suffix}"
  dex_public_host                       = "dex.${local.platform_admin_base_domain_effective}"
  dex_public_url                        = "https://${local.dex_public_host}${local.gateway_https_host_port_suffix}/dex"
  gitea_public_host                     = local.separate_admin_domain_enabled ? "gitea.${local.platform_admin_base_domain_effective}" : "gitea.admin.${local.platform_base_domain_effective}"
  gitea_public_url                      = "https://${local.gitea_public_host}${local.gateway_https_host_port_suffix}"
  grafana_public_host                   = local.separate_admin_domain_enabled ? "grafana.${local.platform_admin_base_domain_effective}" : "grafana.admin.${local.platform_base_domain_effective}"
  grafana_public_url                    = "https://${local.grafana_public_host}${local.gateway_https_host_port_suffix}"
  headlamp_public_host                  = local.separate_admin_domain_enabled ? "headlamp.${local.platform_admin_base_domain_effective}" : "headlamp.admin.${local.platform_base_domain_effective}"
  headlamp_public_url                   = "https://${local.headlamp_public_host}${local.gateway_https_host_port_suffix}"
  hubble_public_host                    = local.separate_admin_domain_enabled ? "hubble.${local.platform_admin_base_domain_effective}" : "hubble.admin.${local.platform_base_domain_effective}"
  hubble_public_url                     = "https://${local.hubble_public_host}${local.gateway_https_host_port_suffix}"
  kyverno_public_host                   = local.separate_admin_domain_enabled ? "kyverno.${local.platform_admin_base_domain_effective}" : "kyverno.admin.${local.platform_base_domain_effective}"
  kyverno_public_url                    = "https://${local.kyverno_public_host}${local.gateway_https_host_port_suffix}"
  signoz_public_host                    = local.separate_admin_domain_enabled ? "signoz.${local.platform_admin_base_domain_effective}" : "signoz.admin.${local.platform_base_domain_effective}"
  signoz_public_url                     = "https://${local.signoz_public_host}${local.gateway_https_host_port_suffix}"
  sentiment_dev_public_host             = "sentiment.dev.${local.platform_base_domain_effective}"
  sentiment_dev_public_url              = "https://${local.sentiment_dev_public_host}${local.gateway_https_host_port_suffix}"
  sentiment_uat_public_host             = "sentiment.uat.${local.platform_base_domain_effective}"
  sentiment_uat_public_url              = "https://${local.sentiment_uat_public_host}${local.gateway_https_host_port_suffix}"
  subnetcalc_dev_public_host            = "subnetcalc.dev.${local.platform_base_domain_effective}"
  subnetcalc_dev_public_url             = "https://${local.subnetcalc_dev_public_host}${local.gateway_https_host_port_suffix}"
  subnetcalc_uat_public_host            = "subnetcalc.uat.${local.platform_base_domain_effective}"
  subnetcalc_uat_public_url             = "https://${local.subnetcalc_uat_public_host}${local.gateway_https_host_port_suffix}"
  admin_route_allowlist_cidrs_effective = [for cidr in var.admin_route_allowlist_cidrs : trimspace(cidr) if trimspace(cidr) != ""]
  admin_route_allowlist_enabled         = length(local.admin_route_allowlist_cidrs_effective) > 0
  gateway_trusted_proxy_cidrs_effective = [for cidr in var.gateway_trusted_proxy_cidrs : trimspace(cidr) if trimspace(cidr) != ""]
  admin_service_type                    = var.expose_admin_nodeports ? "NodePort" : "ClusterIP"
  kind_disable_default_cni              = var.kind_disable_default_cni != null ? var.kind_disable_default_cni : local.enable_cilium_effective
  enable_prometheus_effective           = var.enable_prometheus
  enable_grafana_effective              = var.enable_grafana
  enable_loki_effective                 = var.enable_loki
  enable_victoria_logs_effective        = var.enable_victoria_logs
  enable_tempo_effective                = var.enable_tempo
  enable_otel_gateway_effective         = var.enable_otel_gateway || local.enable_prometheus_effective || local.enable_grafana_effective || local.enable_loki_effective || local.enable_victoria_logs_effective || local.enable_tempo_effective || var.enable_signoz
  enable_observability_effective        = local.enable_otel_gateway_effective || var.enable_observability_agent
  gitea_admin_promote_users_effective = var.enable_gitea ? distinct(compact(concat(
    [var.gitea_admin_username],
    var.gitea_admin_promote_users,
  ))) : []
  host_local_registry_enabled          = trimspace(var.host_local_registry_host) != "" && var.enable_host_local_registry
  host_local_registry_host_effective   = trimspace(var.host_local_registry_host)
  host_local_registry_scheme_effective = trimspace(var.host_local_registry_scheme) != "" ? trimspace(var.host_local_registry_scheme) : "http"
  host_local_registry_mirror_registries = local.host_local_registry_enabled ? toset([
    "dhi.io",
    "ghcr.io",
    "public.ecr.aws",
    "quay.io",
  ]) : toset([])
  external_platform_grafana_image      = trimspace(lookup(var.external_platform_image_refs, "grafana", ""))
  external_platform_hardened_registry  = trimspace(lookup(var.external_platform_image_refs, "hardened-registry", ""))
  external_platform_signoz_auth_proxy  = trimspace(lookup(var.external_platform_image_refs, "signoz-auth-proxy", ""))
  external_platform_grafana_ref_parts  = length(regexall("^(.+):([^:/]+)$", local.external_platform_grafana_image)) > 0 ? regex("^(.+):([^:/]+)$", local.external_platform_grafana_image) : []
  external_platform_grafana_repo       = length(local.external_platform_grafana_ref_parts) == 2 ? local.external_platform_grafana_ref_parts[0] : ""
  external_platform_grafana_tag        = length(local.external_platform_grafana_ref_parts) == 2 ? local.external_platform_grafana_ref_parts[1] : ""
  external_platform_grafana_segments   = local.external_platform_grafana_repo != "" ? split("/", local.external_platform_grafana_repo) : []
  external_platform_grafana_registry   = length(local.external_platform_grafana_segments) > 1 ? local.external_platform_grafana_segments[0] : ""
  external_platform_grafana_repository = length(local.external_platform_grafana_segments) > 1 ? join("/", slice(local.external_platform_grafana_segments, 1, length(local.external_platform_grafana_segments))) : ""
  default_signoz_auth_proxy_image      = "ghcr.io/scolastico-dev/s.containers/signoz-auth-proxy:latest"
  use_external_platform_grafana = (
    var.prefer_external_platform_images &&
    local.external_platform_grafana_registry != "" &&
    local.external_platform_grafana_repository != "" &&
    local.external_platform_grafana_tag != ""
  )
  hardened_image_registry_effective          = var.prefer_external_platform_images && local.external_platform_hardened_registry != "" ? local.external_platform_hardened_registry : var.hardened_image_registry
  grafana_image_registry_effective           = local.use_external_platform_grafana ? local.external_platform_grafana_registry : var.grafana_image_registry
  grafana_image_repository_effective         = local.use_external_platform_grafana ? local.external_platform_grafana_repository : var.grafana_image_repository
  grafana_image_tag_effective                = local.use_external_platform_grafana ? local.external_platform_grafana_tag : var.grafana_image_tag
  grafana_victoria_logs_plugin_url_effective = local.use_external_platform_grafana ? "" : trimspace(var.grafana_victoria_logs_plugin_url)
  grafana_plugins_values_yaml = local.grafana_victoria_logs_plugin_url_effective != "" ? join("\n", [
    "        plugins:",
    "          - ${local.grafana_victoria_logs_plugin_url_effective}",
  ]) : "        plugins: []"
  signoz_auth_proxy_image_effective = var.prefer_external_platform_images && local.external_platform_signoz_auth_proxy != "" ? local.external_platform_signoz_auth_proxy : local.default_signoz_auth_proxy_image

  containerd_certs_dir = abspath("${path.module}/.run/containerd-certs.d")
  kind_node_kubectl_wrapper_mount = [
    {
      host_path      = abspath("${path.module}/scripts/kind-node-kubectl-wrapper.sh")
      container_path = "/usr/local/bin/kubectl"
      read_only      = true
    }
  ]
  docker_socket_mount = var.enable_docker_socket_mount ? [
    {
      host_path      = var.docker_socket_path
      container_path = "/var/run/docker.sock"
      read_only      = false
    }
  ] : []

  apps_dir_host_path_effective = var.apps_dir_host_path != "" ? abspath(pathexpand(var.apps_dir_host_path)) : local.monorepo_apps_dir
  apps_dir_mount = var.enable_apps_dir_mount ? [
    {
      host_path      = local.apps_dir_host_path_effective
      container_path = var.apps_dir_container_path
      read_only      = var.apps_dir_read_only
    }
  ] : []

  kind_extra_mounts = concat(
    [
      {
        host_path      = local.containerd_certs_dir
        container_path = "/etc/containerd/certs.d"
        read_only      = true
      }
    ],
    local.kind_node_kubectl_wrapper_mount,
    local.docker_socket_mount,
    local.apps_dir_mount
  )

  sentiment_repo_name            = "sentiment"
  subnet_calculator_repo_name    = "subnet-calculator"
  sentiment_source_dir           = var.sentiment_source_dir != "" ? abspath(pathexpand(var.sentiment_source_dir)) : abspath("${local.monorepo_apps_dir}/sentiment")
  subnet_calculator_source_dir   = var.subnet_calculator_source_dir != "" ? abspath(pathexpand(var.subnet_calculator_source_dir)) : abspath("${local.monorepo_apps_dir}/${local.subnet_calculator_repo_name}")
  sentiment_content_hash         = var.enable_app_repo_sentiment ? try(sha1(join("", [for f in sort(fileset(local.sentiment_source_dir, "**")) : filesha256("${local.sentiment_source_dir}/${f}")])), "") : ""
  subnet_calculator_content_hash = var.enable_app_repo_subnet_calculator ? try(sha1(join("", [for f in sort(fileset(local.subnet_calculator_source_dir, "**")) : filesha256("${local.subnet_calculator_source_dir}/${f}")])), "") : ""
  enable_sentiment_external_images = (
    var.prefer_external_workload_images &&
    lookup(var.external_workload_image_refs, "sentiment-api", "") != "" &&
    lookup(var.external_workload_image_refs, "sentiment-auth-ui", "") != ""
  )
  enable_subnetcalc_external_images = (
    var.prefer_external_workload_images &&
    lookup(var.external_workload_image_refs, "subnetcalc-api-fastapi-container-app", "") != "" &&
    lookup(var.external_workload_image_refs, "subnetcalc-apim-simulator", "") != "" &&
    lookup(var.external_workload_image_refs, "subnetcalc-frontend-react", "") != ""
  )
  # External image refs choose where workload images come from, but they should
  # not advance the teaching-stage rollout on their own. Stage files remain the
  # source of truth for when these workloads are introduced.
  enable_sentiment_workloads_effective  = var.enable_app_repo_sentiment
  enable_subnetcalc_workloads_effective = var.enable_app_repo_subnet_calculator

  policies_repo_name        = "policies"
  policies_repo_url_cluster = "ssh://${var.gitea_ssh_username}@${local.gitea_ssh_host_cluster}:${local.gitea_ssh_port_cluster}/${local.gitea_repo_owner}/${local.policies_repo_name}.git"
  vendored_chart_paths = {
    cert_manager            = "apps/vendor/charts/cert-manager"
    dex                     = "apps/vendor/charts/dex"
    grafana                 = "apps/vendor/charts/grafana"
    headlamp                = "apps/vendor/charts/headlamp"
    kyverno                 = "apps/vendor/charts/kyverno"
    loki                    = "apps/vendor/charts/loki"
    oauth2_proxy            = "apps/vendor/charts/oauth2-proxy"
    opentelemetry_collector = "apps/vendor/charts/opentelemetry-collector"
    policy_reporter         = "apps/vendor/charts/policy-reporter"
    prometheus              = "apps/vendor/charts/prometheus"
    signoz                  = "apps/vendor/charts/signoz"
    tempo                   = "apps/vendor/charts/tempo"
    victoria_logs           = "apps/vendor/charts/victoria-logs-single"
  }

  policies_repo_private_key_path = "${local.run_dir}/policies-repo.id_ed25519"
  gitea_known_hosts_cluster_path = "${local.run_dir}/gitea_known_hosts_cluster"

  enable_gitops_repo_requested = (
    var.enable_policies ||
    var.enable_cert_manager ||
    var.enable_gateway_tls ||
    var.enable_actions_runner ||
    local.enable_sentiment_workloads_effective ||
    local.enable_subnetcalc_workloads_effective ||
    local.enable_prometheus_effective ||
    local.enable_grafana_effective ||
    local.enable_loki_effective ||
    local.enable_victoria_logs_effective ||
    local.enable_tempo_effective ||
    var.enable_signoz ||
    var.enable_headlamp ||
    var.enable_sso ||
    var.enable_app_of_apps
  )
  enable_gitops_repo = var.enable_gitea && var.enable_argocd && local.enable_gitops_repo_requested
  argocd_gitops_repo_app_names = compact(concat(
    var.enable_app_of_apps && local.enable_gitops_repo ? ["app-of-apps"] : [],
    var.enable_policies && var.enable_argocd && !var.enable_app_of_apps ? ["kyverno", "kyverno-policies", "cilium-policies"] : [],
    var.enable_policies && var.enable_argocd && !var.enable_app_of_apps ? ["policy-reporter"] : [],
    var.enable_cert_manager && var.enable_argocd && !var.enable_app_of_apps ? ["cert-manager"] : [],
    var.enable_gateway_tls && var.enable_argocd && !var.enable_app_of_apps ? ["cert-manager-config", "nginx-gateway-fabric", "platform-gateway", "platform-gateway-routes"] : [],
    var.enable_actions_runner && var.enable_gitea && var.enable_argocd && !var.enable_app_of_apps ? ["gitea-actions-runner"] : [],
    local.enable_prometheus_effective && var.enable_argocd && !var.enable_app_of_apps ? ["prometheus"] : [],
    local.enable_grafana_effective && var.enable_argocd && !var.enable_app_of_apps ? ["grafana"] : [],
    local.enable_loki_effective && var.enable_argocd && !var.enable_app_of_apps ? ["loki"] : [],
    local.enable_victoria_logs_effective && var.enable_argocd && !var.enable_app_of_apps ? ["victoria-logs"] : [],
    local.enable_otel_gateway_effective && var.enable_argocd && !var.enable_app_of_apps ? ["otel-collector-prometheus"] : [],
    local.enable_subnetcalc_workloads_effective && var.enable_argocd && !var.enable_app_of_apps ? ["apim"] : [],
    (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective) && var.enable_argocd && !var.enable_app_of_apps ? ["dev", "uat"] : [],
    var.enable_headlamp && var.enable_argocd && !var.enable_app_of_apps ? ["headlamp"] : [],
    var.enable_sso && var.enable_argocd && !var.enable_app_of_apps ? ["dex", "oauth2-proxy-argocd", "oauth2-proxy-gitea"] : [],
    var.enable_sso && var.enable_hubble && var.enable_argocd && !var.enable_app_of_apps ? ["oauth2-proxy-hubble"] : [],
    var.enable_sso && var.enable_argocd && var.enable_grafana && !var.enable_app_of_apps ? ["oauth2-proxy-grafana"] : [],
    var.enable_sso && var.enable_argocd && var.enable_signoz && !var.enable_app_of_apps ? ["oauth2-proxy-signoz"] : [],
    var.enable_sso && local.enable_sentiment_workloads_effective && var.enable_argocd && !var.enable_app_of_apps ? ["oauth2-proxy-sentiment-dev", "oauth2-proxy-sentiment-uat"] : [],
    var.enable_sso && local.enable_subnetcalc_workloads_effective && var.enable_argocd && !var.enable_app_of_apps ? ["oauth2-proxy-subnetcalc-dev", "oauth2-proxy-subnetcalc-uat"] : [],
  ))

  registry_secret_namespaces_effective = toset(distinct(concat(
    var.registry_secret_namespaces,
    (var.enable_argocd && (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective)) ? ["dev"] : [],
    (var.enable_argocd && (local.enable_sentiment_workloads_effective || local.enable_subnetcalc_workloads_effective)) ? ["uat"] : [],
    (var.enable_argocd && local.enable_subnetcalc_workloads_effective) ? ["apim"] : [],
  )))

  policies_repo_content_hash = sha1(join("", concat(
    [for f in sort(fileset(path.module, "apps/**")) : filesha256("${path.module}/${f}")],
    [for f in sort(fileset(path.module, "cluster-policies/**")) : filesha256("${path.module}/${f}")],
    [for f in sort(fileset(path.module, "templates/otel-gateway/**")) : filesha256("${path.module}/${f}")]
  )))
  policies_repo_render_hash = sha1(jsonencode({
    content_hash                           = local.policies_repo_content_hash
    repo_owner                             = local.gitea_repo_owner
    repo_is_org                            = local.gitea_repo_owner_is_org
    platform_base_domain                   = local.platform_base_domain_effective
    platform_admin_base_domain             = local.platform_admin_base_domain_effective
    enable_hubble                          = var.enable_hubble
    enable_policies                        = var.enable_policies
    enable_gateway_tls                     = var.enable_gateway_tls
    gateway_https_host_port                = var.gateway_https_host_port
    admin_route_allowlist_cidrs            = local.admin_route_allowlist_cidrs_effective
    gateway_trusted_proxy_cidrs            = local.gateway_trusted_proxy_cidrs_effective
    enable_cert_manager                    = var.enable_cert_manager
    enable_actions_runner                  = var.enable_actions_runner
    enable_app_repo_sentiment              = var.enable_app_repo_sentiment
    enable_app_repo_subnetcalc             = var.enable_app_repo_subnet_calculator
    enable_prometheus                      = var.enable_prometheus
    enable_grafana                         = var.enable_grafana
    enable_loki                            = var.enable_loki
    enable_victoria_logs                   = var.enable_victoria_logs
    enable_tempo                           = var.enable_tempo
    enable_signoz                          = var.enable_signoz
    enable_otel_gateway                    = var.enable_otel_gateway
    enable_headlamp                        = var.enable_headlamp
    enable_observability_agent             = var.enable_observability_agent
    prefer_external_images                 = var.prefer_external_workload_images
    external_sentiment_api                 = lookup(var.external_workload_image_refs, "sentiment-api", "")
    external_sentiment_ui                  = lookup(var.external_workload_image_refs, "sentiment-auth-ui", "")
    external_subnetcalc_api                = lookup(var.external_workload_image_refs, "subnetcalc-api-fastapi-container-app", "")
    external_subnetcalc_apim               = lookup(var.external_workload_image_refs, "subnetcalc-apim-simulator", "")
    external_subnetcalc_fe                 = lookup(var.external_workload_image_refs, "subnetcalc-frontend-react", "")
    external_subnetcalc_fe_ts              = lookup(var.external_workload_image_refs, "subnetcalc-frontend-typescript-vite", "")
    prefer_external_platform               = var.prefer_external_platform_images
    host_local_registry_enabled            = local.host_local_registry_enabled
    host_local_registry_host               = local.host_local_registry_host_effective
    external_platform_grafana              = local.external_platform_grafana_image
    hardened_image_registry                = local.hardened_image_registry_effective
    external_platform_hardened             = local.external_platform_hardened_registry
    external_platform_signoz_auth          = local.external_platform_signoz_auth_proxy
    cert_manager_chart_version             = var.cert_manager_chart_version
    dex_chart_version                      = var.dex_chart_version
    grafana_chart_version                  = var.grafana_chart_version
    grafana_image_registry                 = local.grafana_image_registry_effective
    grafana_image_repository               = local.grafana_image_repository_effective
    grafana_image_tag                      = local.grafana_image_tag_effective
    grafana_sidecar_image_registry         = var.grafana_sidecar_image_registry
    grafana_sidecar_image_repository       = var.grafana_sidecar_image_repository
    grafana_sidecar_image_tag              = var.grafana_sidecar_image_tag
    grafana_victoria_logs_plugin_url       = local.grafana_victoria_logs_plugin_url_effective
    grafana_liveness_initial_delay_seconds = var.grafana_liveness_initial_delay_seconds
    headlamp_chart_version                 = var.headlamp_chart_version
    kyverno_chart_version                  = var.kyverno_chart_version
    loki_chart_version                     = var.loki_chart_version
    oauth2_proxy_chart_version             = var.oauth2_proxy_chart_version
    otel_chart_version                     = var.opentelemetry_collector_chart_version
    policy_reporter_chart_version          = var.policy_reporter_chart_version
    prometheus_chart_version               = var.prometheus_chart_version
    signoz_chart_version                   = var.signoz_chart_version
    tempo_chart_version                    = var.tempo_chart_version
    victoria_logs_chart_version            = var.victoria_logs_chart_version
    signoz_auth_proxy_image                = local.signoz_auth_proxy_image_effective
  }))

  # The Kubernetes/Helm/kubectl providers validate config_path eagerly.
  # Stage 100 may run on machines without an existing kubeconfig file, so fall back
  # to a committed, syntactically-valid empty kubeconfig.
  kubeconfig_path_for_providers = fileexists(local.kubeconfig_path_expanded) ? local.kubeconfig_path_expanded : "${path.module}/templates/empty-kubeconfig.yaml"
  kubeconfig_raw_for_providers  = file(local.kubeconfig_path_for_providers)
  kubeconfig_context_names_for_providers = [
    for ctx in try(yamldecode(local.kubeconfig_raw_for_providers).contexts, []) : tostring(try(ctx.name, ""))
    if tostring(try(ctx.name, "")) != ""
  ]
  kubeconfig_context_for_providers = (
    length(trimspace(var.kubeconfig_context)) > 0 &&
    contains(local.kubeconfig_context_names_for_providers, trimspace(var.kubeconfig_context))
  ) ? trimspace(var.kubeconfig_context) : null

  extra_port_mappings = concat(
    [
      {
        name           = "gateway-https"
        container_port = var.gateway_https_node_port
        host_port      = var.gateway_https_host_port
        listen_address = trimspace(var.gateway_https_listen_address)
        protocol       = "TCP"
      }
    ],
    var.expose_admin_nodeports ? [
      {
        name           = "argocd"
        container_port = var.argocd_server_node_port
        host_port      = var.argocd_server_node_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      },
      {
        name           = "hubble-ui"
        container_port = var.hubble_ui_node_port
        host_port      = var.hubble_ui_node_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      },
      {
        name           = "gitea-http"
        container_port = var.gitea_http_node_port
        host_port      = var.gitea_http_node_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      },
      {
        name           = "gitea-ssh"
        container_port = var.gitea_ssh_node_port
        host_port      = var.gitea_ssh_node_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      },
      {
        name           = "grafana-ui"
        container_port = var.grafana_ui_node_port
        host_port      = var.grafana_ui_host_port
        listen_address = "127.0.0.1"
        protocol       = "TCP"
      },
    ] : []
  )

  cilium_values = merge(
    {
      cluster = {
        name = var.cluster_name
        id   = 0
      }

      kubeProxyReplacement  = false
      routingMode           = "native"
      autoDirectNodeRoutes  = true
      ipv4NativeRoutingCIDR = var.cilium_native_routing_cidr

      ipam = {
        mode = "kubernetes"
      }

      operator = {
        replicas = 1
        resources = {
          limits = {
            cpu    = "200m"
            memory = "256Mi"
          }
          requests = {
            cpu    = "50m"
            memory = "128Mi"
          }
        }
      }

      prometheus = {
        enabled = true
      }
    },
    var.enable_cilium_wireguard ? {
      encryption = {
        enabled        = true
        type           = "wireguard"
        nodeEncryption = var.enable_cilium_node_encryption
        strictMode = {
          enabled                   = true
          cidr                      = var.cilium_native_routing_cidr
          allowRemoteNodeIdentities = true
        }
      }
    } : {},
    var.enable_hubble ? {
      hubble = {
        enabled = true
        metrics = {
          enabled = [
            "dns",
            "drop",
            "tcp",
            "flow",
            "icmp",
            "httpV2:exemplars=true;labelsContext=source_ip,source_namespace,source_workload,destination_ip,destination_namespace,destination_workload,traffic_direction",
            "policy:sourceContext=app;destinationContext=app",
          ]
          enableOpenMetrics = true
          serviceMonitor = {
            enabled = false
          }
        }
        relay = {
          enabled     = true
          servicePort = 4245
          resources = {
            limits   = { cpu = "100m", memory = "128Mi" }
            requests = { cpu = "50m", memory = "64Mi" }
          }
        }
        ui = {
          enabled = true
          resources = {
            limits   = { cpu = "100m", memory = "128Mi" }
            requests = { cpu = "50m", memory = "64Mi" }
          }
          service = merge(
            {
              type = local.admin_service_type
            },
            var.expose_admin_nodeports ? {
              nodePort = var.hubble_ui_node_port
            } : {}
          )
        }
      }
    } : {}
  )

  argocd_values = {
    global = {
      image = {
        repository = var.argocd_image_repository
        tag        = var.argocd_image_tag
      }
    }

    configs = {
      params = {
        "server.insecure"                   = true
        "server.disable.auth"               = local.argocd_oidc_enabled ? "false" : (var.enable_sso ? "true" : "false")
        "reposerver.metrics.listen.address" = "0.0.0.0"
      }
      rbac = {
        "policy.csv"       = ""
        "policy.default"   = "role:admin"
        "policy.matchMode" = "glob"
        "scopes"           = "[groups]"
      }

      cm = tomap(merge(
        {
          # Altinity ClickHouse operator can leave CHI status at InProgress even
          # when the cluster is fully up; avoid perma-Progressing Argo apps.
          "resource.customizations.health.clickhouse.altinity.com_ClickHouseInstallation" = trimspace(<<-EOT
            hs = {}
            if obj.status == nil then
              hs.status = "Progressing"
              hs.message = "Waiting for ClickHouseInstallation status"
              return hs
            end

            local st = obj.status.status or ""
            local endpoint = obj.status.endpoint or ""
            local pods = obj.status.pods or {}

            if st == "Completed" then
              hs.status = "Healthy"
              hs.message = "ClickHouseInstallation is completed"
              return hs
            end

            if st == "InProgress" and endpoint ~= "" and #pods > 0 then
              hs.status = "Healthy"
              hs.message = "ClickHouseInstallation has endpoint and running pods"
              return hs
            end

            if st == "InProgress" or st == "Terminating" then
              hs.status = "Progressing"
              hs.message = obj.status.action or ("ClickHouseInstallation status: " .. st)
              return hs
            end

            hs.status = "Degraded"
            hs.message = obj.status.action or ("ClickHouseInstallation status: " .. st)
            return hs
          EOT
          )
        },
        var.enable_sso ? merge({
          url = local.argocd_public_url
          }, local.argocd_oidc_enabled ? {
          "oidc.config" = trimspace(<<-EOT
            name: Dex
            issuer: ${local.dex_public_url}
            clientID: argocd
            clientSecret: $oidc.dex.clientSecret
            requestedScopes:
              - openid
              - profile
              - email
          EOT
          )

          # Dev-only: mkcert certs aren't trusted inside the cluster by default.
          "oidc.tls.insecure.skip.verify" = "true"
        } : {}) : {}
      ))

      secret = {
        extra = local.argocd_oidc_enabled ? tomap({
          "oidc.dex.clientSecret" = random_password.dex_argocd_client_secret[0].result
        }) : tomap({})
      }
    }

    controller = {
      args = {
        statusProcessors    = "10"
        operationProcessors = "5"
      }
      metrics = {
        enabled = var.enable_observability_agent
      }
      resources = {
        limits   = { cpu = "750m", memory = "1536Mi" }
        requests = { cpu = "250m", memory = "512Mi" }
      }
    }

    repoServer = {
      readinessProbe = {
        timeoutSeconds = 5
      }
      livenessProbe = {
        timeoutSeconds      = 5
        initialDelaySeconds = 30
      }
      metrics = {
        enabled = var.enable_observability_agent
      }
      resources = {
        limits   = { cpu = "300m", memory = "512Mi" }
        requests = { cpu = "75m", memory = "128Mi" }
      }
    }

    applicationSet = {
      enabled = var.argocd_applicationset_enabled
      metrics = {
        enabled = var.enable_observability_agent
      }
      resources = {
        limits   = { cpu = "100m", memory = "128Mi" }
        requests = { cpu = "25m", memory = "64Mi" }
      }
    }

    notifications = {
      enabled = var.argocd_notifications_enabled
    }

    server = {
      hostAliases = var.enable_sso ? [
        {
          ip        = kubernetes_service_v1.platform_gateway_nginx_internal[0].spec[0].cluster_ip
          hostnames = [local.dex_public_host]
        }
      ] : []

      readinessProbe = {
        timeoutSeconds = 5
      }

      livenessProbe = {
        timeoutSeconds = 5
      }

      metrics = {
        enabled = var.enable_observability_agent
      }

      resources = {
        limits   = { cpu = "100m", memory = "128Mi" }
        requests = { cpu = "25m", memory = "64Mi" }
      }

      service = merge(
        {
          type             = local.admin_service_type
          servicePortHttp  = 8080
          servicePortHttps = 8443
        },
        var.expose_admin_nodeports ? {
          nodePort = var.argocd_server_node_port
        } : {}
      )
    }
  }

  headlamp_config = merge(
    {
      watchPlugins = true
      sessionTTL   = 0
    },
    var.enable_sso ? {
      oidc = {
        clientID     = "headlamp"
        clientSecret = random_password.dex_headlamp_client_secret[0].result
        issuerURL    = local.dex_public_url
        scopes       = "openid profile email groups"
        callbackURL  = "${local.headlamp_public_url}/oidc-callback"
      }
    } : {},
    # Pass -oidc-ca-file to trust the mkcert CA for OIDC connections to Dex.
    var.enable_sso ? {
      extraArgs = compact([
        "-oidc-ca-file=/headlamp-ca/ca.crt",
        var.headlamp_oidc_skip_tls_verify ? "-oidc-skip-tls-verify" : "",
      ])
    } : {}
  )

  headlamp_values = {
    service = {
      port = 4466
    }
    clusterRoleBinding = {
      create = var.headlamp_cluster_role_binding_create
    }
    config = local.headlamp_config
    env = var.enable_sso ? [
      {
        name  = "SSL_CERT_FILE"
        value = "/headlamp-ca/ca.crt"
      },
      {
        name  = "HEADLAMP_OIDC_CONFIG_HASH"
        value = sha256(jsonencode(local.headlamp_config))
      }
    ] : []
    volumeMounts = var.enable_sso ? [
      {
        name      = "headlamp-ca"
        mountPath = "/headlamp-ca"
        readOnly  = true
      }
    ] : []
    volumes = var.enable_sso ? [
      {
        name = "headlamp-ca"
        secret = {
          secretName = "mkcert-ca"
          items = [
            {
              key  = "ca.crt"
              path = "ca.crt"
            }
          ]
        }
      }
    ] : []
  }
}
