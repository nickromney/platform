locals {
  kind_workers                      = range(var.worker_count)
  kind_config_path_expanded         = abspath(pathexpand(var.kind_config_path))
  kubeconfig_path_expanded          = abspath(pathexpand(var.kubeconfig_path))
  preload_image_list_path_effective = trimspace(var.preload_image_list_path) != "" ? abspath(pathexpand(var.preload_image_list_path)) : abspath("${path.module}/../../kubernetes/kind/preload-images.txt")

  repo_root         = abspath("${path.module}/../..")
  monorepo_apps_dir = abspath("${local.repo_root}/apps")

  run_dir = abspath("${path.module}/.run")

  gitea_http_host_local             = "127.0.0.1"
  gitea_ssh_host_local              = "127.0.0.1"
  gitea_local_access_mode_effective = lower(var.gitea_local_access_mode)

  gitea_ssh_host_cluster         = "gitea-ssh.gitea.svc.cluster.local"
  gitea_ssh_port_cluster         = 22
  gitea_repo_owner               = var.gitea_repo_owner != "" ? var.gitea_repo_owner : var.gitea_admin_username
  gitea_repo_owner_is_org        = var.gitea_repo_owner_is_org
  gitea_repo_owner_fallback      = var.gitea_repo_owner_is_org ? var.gitea_admin_username : ""
  argocd_oidc_enabled            = var.enable_sso && var.enable_argocd_oidc
  cni_provider_effective         = lower(var.cni_provider)
  enable_cilium_effective        = local.cni_provider_effective == "cilium"
  admin_cookie_domain            = ".127.0.0.1.sslip.io"
  admin_whitelist_domains        = var.gateway_https_host_port == 443 ? local.admin_cookie_domain : "${local.admin_cookie_domain},${local.admin_cookie_domain}:${var.gateway_https_host_port}"
  dev_cookie_domain              = ".dev.127.0.0.1.sslip.io"
  dev_whitelist_domains          = var.gateway_https_host_port == 443 ? local.dev_cookie_domain : "${local.dev_cookie_domain},${local.dev_cookie_domain}:${var.gateway_https_host_port}"
  uat_cookie_domain              = ".uat.127.0.0.1.sslip.io"
  uat_whitelist_domains          = var.gateway_https_host_port == 443 ? local.uat_cookie_domain : "${local.uat_cookie_domain},${local.uat_cookie_domain}:${var.gateway_https_host_port}"
  gateway_https_host_port_suffix = var.gateway_https_host_port == 443 ? "" : ":${var.gateway_https_host_port}"
  argocd_public_url              = "https://argocd.admin.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  dex_public_host                = "dex.127.0.0.1.sslip.io"
  dex_public_url                 = "https://${local.dex_public_host}${local.gateway_https_host_port_suffix}/dex"
  gitea_public_url               = "https://gitea.admin.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  grafana_public_url             = "https://grafana.admin.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  headlamp_public_url            = "https://headlamp.admin.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  hubble_public_url              = "https://hubble.admin.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  kyverno_public_url             = "https://kyverno.admin.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  signoz_public_url              = "https://signoz.admin.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  sentiment_dev_public_url       = "https://sentiment.dev.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  sentiment_uat_public_url       = "https://sentiment.uat.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  subnetcalc_dev_public_url      = "https://subnetcalc.dev.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  subnetcalc_uat_public_url      = "https://subnetcalc.uat.127.0.0.1.sslip.io${local.gateway_https_host_port_suffix}"
  kind_disable_default_cni       = var.kind_disable_default_cni != null ? var.kind_disable_default_cni : local.enable_cilium_effective
  enable_prometheus_effective    = var.enable_prometheus
  enable_grafana_effective       = var.enable_grafana
  enable_loki_effective          = var.enable_loki
  enable_tempo_effective         = var.enable_tempo
  enable_otel_gateway_effective  = var.enable_otel_gateway || local.enable_prometheus_effective || local.enable_grafana_effective || local.enable_loki_effective || local.enable_tempo_effective || var.enable_signoz
  enable_observability_effective = local.enable_otel_gateway_effective || var.enable_observability_agent
  gitea_admin_promote_users_effective = var.enable_gitea ? distinct(compact(concat(
    [var.gitea_admin_username],
    var.gitea_admin_promote_users,
  ))) : []

  containerd_certs_dir = abspath("${path.module}/.run/containerd-certs.d")
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
    local.docker_socket_mount,
    local.apps_dir_mount
  )

  sentiment_llm_repo_name        = "sentiment-llm"
  subnet_calculator_repo_name    = "subnet-calculator"
  sentiment_llm_source_dir       = var.sentiment_llm_source_dir != "" ? abspath(pathexpand(var.sentiment_llm_source_dir)) : abspath("${local.monorepo_apps_dir}/${local.sentiment_llm_repo_name}")
  subnet_calculator_source_dir   = var.subnet_calculator_source_dir != "" ? abspath(pathexpand(var.subnet_calculator_source_dir)) : abspath("${local.monorepo_apps_dir}/${local.subnet_calculator_repo_name}")
  sentiment_llm_content_hash     = var.enable_app_repo_sentiment_llm ? try(sha1(join("", [for f in sort(fileset(local.sentiment_llm_source_dir, "**")) : filesha256("${local.sentiment_llm_source_dir}/${f}")])), "") : ""
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
  enable_sentiment_workloads_effective  = var.enable_app_repo_sentiment_llm
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
    local.enable_tempo_effective ||
    var.enable_signoz ||
    var.enable_headlamp ||
    var.enable_sso ||
    var.enable_app_of_apps
  )
  enable_gitops_repo = var.enable_gitea && var.enable_argocd && local.enable_gitops_repo_requested
  argocd_gitops_repo_app_names = compact(concat(
    var.enable_app_of_apps && local.enable_gitops_repo ? ["app-of-apps"] : [],
    var.enable_policies && var.enable_argocd && !var.enable_app_of_apps ? ["kyverno-policies", "cilium-policies"] : [],
    var.enable_cert_manager && var.enable_argocd && !var.enable_app_of_apps ? ["cert-manager"] : [],
    var.enable_gateway_tls && var.enable_argocd && !var.enable_app_of_apps ? ["cert-manager-config", "nginx-gateway-fabric", "platform-gateway", "platform-gateway-routes"] : [],
    var.enable_actions_runner && var.enable_gitea && var.enable_argocd && !var.enable_app_of_apps ? ["gitea-actions-runner"] : [],
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
    content_hash                  = local.policies_repo_content_hash
    repo_owner                    = local.gitea_repo_owner
    repo_is_org                   = local.gitea_repo_owner_is_org
    enable_hubble                 = var.enable_hubble
    enable_policies               = var.enable_policies
    enable_gateway_tls            = var.enable_gateway_tls
    gateway_https_host_port       = var.gateway_https_host_port
    enable_cert_manager           = var.enable_cert_manager
    enable_actions_runner         = var.enable_actions_runner
    enable_app_repo_sentiment     = var.enable_app_repo_sentiment_llm
    enable_app_repo_subnetcalc    = var.enable_app_repo_subnet_calculator
    enable_prometheus             = var.enable_prometheus
    enable_grafana                = var.enable_grafana
    enable_loki                   = var.enable_loki
    enable_tempo                  = var.enable_tempo
    enable_signoz                 = var.enable_signoz
    enable_otel_gateway           = var.enable_otel_gateway
    enable_headlamp               = var.enable_headlamp
    enable_observability_agent    = var.enable_observability_agent
    prefer_external_images        = var.prefer_external_workload_images
    external_sentiment_api        = lookup(var.external_workload_image_refs, "sentiment-api", "")
    external_sentiment_ui         = lookup(var.external_workload_image_refs, "sentiment-auth-ui", "")
    external_subnetcalc_api       = lookup(var.external_workload_image_refs, "subnetcalc-api-fastapi-container-app", "")
    external_subnetcalc_apim      = lookup(var.external_workload_image_refs, "subnetcalc-apim-simulator", "")
    external_subnetcalc_fe        = lookup(var.external_workload_image_refs, "subnetcalc-frontend-react", "")
    external_subnetcalc_fe_ts     = lookup(var.external_workload_image_refs, "subnetcalc-frontend-typescript-vite", "")
    hardened_image_registry       = var.hardened_image_registry
    cert_manager_chart_version    = var.cert_manager_chart_version
    dex_chart_version             = var.dex_chart_version
    grafana_chart_version         = var.grafana_chart_version
    headlamp_chart_version        = var.headlamp_chart_version
    kyverno_chart_version         = var.kyverno_chart_version
    loki_chart_version            = var.loki_chart_version
    oauth2_proxy_chart_version    = var.oauth2_proxy_chart_version
    otel_chart_version            = var.opentelemetry_collector_chart_version
    policy_reporter_chart_version = var.policy_reporter_chart_version
    prometheus_chart_version      = var.prometheus_chart_version
    signoz_chart_version          = var.signoz_chart_version
    tempo_chart_version           = var.tempo_chart_version
    llm_gateway_mode              = var.llm_gateway_mode
    llm_gateway_external_name     = var.llm_gateway_external_name
    llm_gateway_external_cidr     = var.llm_gateway_external_cidr
    llama_cpp_image               = var.llama_cpp_image
    llama_cpp_hf_repo             = var.llama_cpp_hf_repo
    llama_cpp_hf_file             = var.llama_cpp_hf_file
    llama_cpp_model_alias         = var.llama_cpp_model_alias
    llama_cpp_ctx_size            = var.llama_cpp_ctx_size
    litellm_upstream_model        = var.litellm_upstream_model
    litellm_upstream_api_base     = var.litellm_upstream_api_base
    litellm_upstream_api_key      = nonsensitive(var.litellm_upstream_api_key)
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

  extra_port_mappings = [
    {
      name           = "gateway-https"
      container_port = var.gateway_https_node_port
      host_port      = var.gateway_https_host_port
      listen_address = "127.0.0.1"
      protocol       = "TCP"
    },
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
  ]

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
          enabled = true
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
          service = {
            type     = "NodePort"
            nodePort = var.hubble_ui_node_port
          }
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
          hostnames = ["dex.127.0.0.1.sslip.io"]
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

      service = {
        type             = "NodePort"
        nodePort         = var.argocd_server_node_port
        servicePortHttp  = 8080
        servicePortHttps = 8443
      }
    }
  }

  headlamp_config = merge(
    {
      watchPlugins = true
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
    # Pass -oidc-ca-file to trust the mkcert CA for OIDC connections to Dex
    # Also add -oidc-skip-tls-verify temporarily to debug TLS issues
    var.enable_sso ? { extraArgs = ["-oidc-ca-file=/headlamp-ca/ca.crt", "-oidc-skip-tls-verify"] } : {}
  )

  headlamp_values = {
    service = {
      port = 4466
    }
    clusterRoleBinding = {
      create = true
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
