variables {
  gitea_admin_pwd       = "test-admin-password"
  gitea_member_user_pwd = "test-member-password"
}

run "actions_runner_enabled" {
  command = plan

  variables {
    cni_provider          = "none"
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    enable_signoz         = false
    enable_sso            = false
    enable_actions_runner = true
  }

  assert {
    condition     = length(kubernetes_namespace_v1.gitea_runner) == 1
    error_message = "Expected kubernetes_namespace_v1.gitea_runner to exist when enable_actions_runner=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_gitea_actions_runner) == 1
    error_message = "Expected kubectl_manifest.argocd_app_gitea_actions_runner to exist when enable_actions_runner=true"
  }

  assert {
    condition     = length(regexall("name: gitea-actions-runner", kubectl_manifest.argocd_app_gitea_actions_runner[0].yaml_body)) > 0
    error_message = "Expected Actions runner ArgoCD Application YAML to include the expected name"
  }

  assert {
    condition     = length(kubernetes_secret_v1.argocd_repo_creds_gitea_ssh) == 1
    error_message = "Expected ArgoCD repo-creds secret for Gitea SSH to exist when enable_actions_runner=true"
  }
}

run "policies_enabled" {
  command = plan

  variables {
    cni_provider    = "cilium"
    enable_hubble   = false
    enable_argocd   = true
    enable_gitea    = true
    enable_signoz   = false
    enable_sso      = false
    enable_policies = true
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_kyverno) == 1
    error_message = "Expected kubectl_manifest.argocd_app_kyverno to exist when enable_policies=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_kyverno_policies) == 1
    error_message = "Expected kubectl_manifest.argocd_app_kyverno_policies to exist when enable_policies=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_cilium_policies) == 1
    error_message = "Expected kubectl_manifest.argocd_app_cilium_policies to exist when enable_policies=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_policy_reporter) == 1
    error_message = "Expected kubectl_manifest.argocd_app_policy_reporter to exist when enable_policies=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_kyverno[0].yaml_body, "repoURL: ${local.policies_repo_url_cluster}")
    error_message = "Expected Kyverno ArgoCD Application YAML to load from the policies repo"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_kyverno[0].yaml_body, "targetRevision: main") && strcontains(kubectl_manifest.argocd_app_kyverno[0].yaml_body, "path: ${local.vendored_chart_paths.kyverno}")
    error_message = "Expected Kyverno ArgoCD Application YAML to track the vendored chart on main"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_kyverno[0].yaml_body, "            image:\n              registry: ${local.hardened_image_registry_effective}\n              repository: kyverno\n              tag: 1.17.2-debian13")
    error_message = "Expected Kyverno admission controller image to use the hardened image value path consumed by the chart"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_kyverno[0].yaml_body, "            securityContext:\n              runAsNonRoot: true\n              runAsUser: 65534\n              runAsGroup: 65534")
    error_message = "Expected Kyverno admission controller container security context to pin a numeric non-root user for hardened images"
  }

  assert {
    condition     = contains(local.argocd_gitops_repo_app_names, "kyverno")
    error_message = "Expected kyverno to be included in the Git-backed Argo refresh list when enable_policies=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_policy_reporter[0].yaml_body, "repoURL: ${local.policies_repo_url_cluster}")
    error_message = "Expected Policy Reporter ArgoCD Application YAML to load from the policies repo"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_policy_reporter[0].yaml_body, "targetRevision: main") && strcontains(kubectl_manifest.argocd_app_policy_reporter[0].yaml_body, "path: ${local.vendored_chart_paths.policy_reporter}")
    error_message = "Expected Policy Reporter ArgoCD Application YAML to track the vendored chart on main"
  }

  assert {
    condition     = length(kubernetes_secret_v1.argocd_repo_creds_gitea_ssh) == 1
    error_message = "Expected ArgoCD repo-creds secret for Gitea SSH to exist when enable_policies=true"
  }
}

run "policies_enabled_with_cilium_policies_disabled" {
  command = plan

  variables {
    cni_provider           = "cilium"
    enable_hubble          = false
    enable_argocd          = true
    enable_gitea           = true
    enable_signoz          = false
    enable_sso             = false
    enable_policies        = true
    enable_cilium_policies = false
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_kyverno) == 1
    error_message = "Expected kubectl_manifest.argocd_app_kyverno to exist when enable_policies=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_kyverno_policies) == 1
    error_message = "Expected kubectl_manifest.argocd_app_kyverno_policies to exist when enable_policies=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_cilium_policies) == 0
    error_message = "Did not expect kubectl_manifest.argocd_app_cilium_policies when enable_cilium_policies=false"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_policy_reporter) == 1
    error_message = "Expected kubectl_manifest.argocd_app_policy_reporter to exist when enable_policies=true"
  }

  assert {
    condition     = !contains(local.argocd_gitops_repo_app_names, "cilium-policies")
    error_message = "Did not expect cilium-policies in the Git-backed Argo refresh list when enable_cilium_policies=false"
  }
}

run "gateway_tls_enabled" {
  command = plan

  variables {
    cni_provider       = "none"
    enable_hubble      = false
    enable_argocd      = true
    enable_gitea       = true
    enable_signoz      = false
    enable_sso         = false
    enable_gateway_tls = true
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_cert_manager) == 1
    error_message = "Expected kubectl_manifest.argocd_app_cert_manager to exist when enable_gateway_tls=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_cert_manager_config) == 1
    error_message = "Expected kubectl_manifest.argocd_app_cert_manager_config to exist when enable_gateway_tls=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_cert_manager_config[0].yaml_body, "retry:") && strcontains(kubectl_manifest.argocd_app_cert_manager_config[0].yaml_body, "limit: 20") && strcontains(kubectl_manifest.argocd_app_cert_manager_config[0].yaml_body, "maxDuration: 5m")
    error_message = "Expected cert-manager-config ArgoCD Application YAML to retry through cert-manager webhook startup"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_nginx_gateway_fabric) == 1
    error_message = "Expected kubectl_manifest.argocd_app_nginx_gateway_fabric to exist when enable_gateway_tls=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_platform_gateway) == 1
    error_message = "Expected kubectl_manifest.argocd_app_platform_gateway to exist when enable_gateway_tls=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_platform_gateway_routes) == 1
    error_message = "Expected kubectl_manifest.argocd_app_platform_gateway_routes to exist when enable_gateway_tls=true"
  }

  assert {
    condition     = length(regexall("DOMAIN: \\\"gitea\\.admin\\.127\\.0\\.0\\.1\\.sslip\\.io\\\"", kubectl_manifest.argocd_app_gitea[0].yaml_body)) > 0
    error_message = "Expected Gitea ArgoCD Application YAML to include a TLS host DOMAIN when enable_gateway_tls=true"
  }

  assert {
    condition     = length(kubernetes_secret_v1.argocd_repo_creds_gitea_ssh) == 1
    error_message = "Expected ArgoCD repo-creds secret for Gitea SSH to exist when enable_gateway_tls=true"
  }
}

run "gateway_tls_sso_enabled" {
  command = plan

  variables {
    cni_provider           = "none"
    enable_hubble          = false
    enable_argocd          = true
    enable_gitea           = true
    enable_signoz          = false
    enable_gateway_tls     = true
    enable_sso             = true
    provision_kind_cluster = true
  }

  assert {
    condition     = length(null_resource.wait_for_platform_gateway_tls) == 1
    error_message = "Expected null_resource.wait_for_platform_gateway_tls to exist when enable_gateway_tls=true and enable_sso=true on kind"
  }
}

run "observability_agent_enabled" {
  command = plan

  variables {
    cni_provider               = "none"
    enable_hubble              = false
    enable_argocd              = true
    enable_gitea               = false
    enable_signoz              = true
    enable_sso                 = false
    enable_observability_agent = true
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_otel_collector_agent) == 1
    error_message = "Expected kubectl_manifest.argocd_app_otel_collector_agent to exist when enable_observability_agent=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_otel_collector_agent[0].yaml_body, "repoURL: ${local.policies_repo_url_cluster}")
    error_message = "Expected OTel agent ArgoCD Application YAML to load from the policies repo"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_otel_collector_agent[0].yaml_body, "targetRevision: main") && strcontains(kubectl_manifest.argocd_app_otel_collector_agent[0].yaml_body, "path: ${local.vendored_chart_paths.opentelemetry_collector}")
    error_message = "Expected OTel agent ArgoCD Application YAML to track the vendored chart on main"
  }
}

run "prometheus_observability_enabled" {
  command = plan

  variables {
    cni_provider      = "none"
    enable_hubble     = false
    enable_argocd     = true
    enable_gitea      = false
    enable_signoz     = false
    enable_prometheus = true
    enable_grafana    = true
    enable_sso        = false
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_prometheus) == 1
    error_message = "Expected kubectl_manifest.argocd_app_prometheus to exist when enable_prometheus=true"
  }

  assert {
    condition     = length(regexall("kube-state-metrics:\\n\\s+enabled: true", kubectl_manifest.argocd_app_prometheus[0].yaml_body)) > 0
    error_message = "Expected Prometheus ArgoCD Application YAML to enable kube-state-metrics for launchpad readiness signals"
  }

  assert {
    condition     = length(regexall("prometheus-node-exporter:\\n\\s+enabled: true", kubectl_manifest.argocd_app_prometheus[0].yaml_body)) > 0
    error_message = "Expected Prometheus ArgoCD Application YAML to enable node-exporter for the node dashboards"
  }

  assert {
    condition     = length(regexall("- job_name: argocd-metrics", kubectl_manifest.argocd_app_prometheus[0].yaml_body)) > 0
    error_message = "Expected Prometheus ArgoCD Application YAML to scrape Argo CD metrics"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_grafana) == 1
    error_message = "Expected kubectl_manifest.argocd_app_grafana to exist when enable_grafana=true"
  }

  assert {
    condition = one([
      for tile in jsondecode(file("${path.module}/config/platform-launchpad.apps.json")).tiles : tile
      if tile.title == "Keycloak"
      ]).url == "https://keycloak.127.0.0.1.sslip.io/admin/platform/console/#/platform/users" && one([
      for tile in jsondecode(file("${path.module}/config/platform-launchpad.apps.json")).tiles : tile
      if tile.title == "Keycloak"
    ]).expr == "((max(kube_deployment_status_replicas_available{namespace=\"sso\",deployment=\"keycloak\"}) > bool 0) or vector(0))"
    error_message = "Expected Grafana launchpad inventory to link to the Keycloak admin console and track Keycloak readiness"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_grafana[0].yaml_body, "https://keycloak.127.0.0.1.sslip.io/admin/platform/console/#/platform/users") && strcontains(kubectl_manifest.argocd_app_grafana[0].yaml_body, "deployment=\\\"keycloak\\\"") && !strcontains(kubectl_manifest.argocd_app_grafana[0].yaml_body, "deployment=\\\"dex\\\"")
    error_message = "Expected rendered Grafana launchpad dashboard to link to the Keycloak admin console and track Keycloak readiness"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_otel_collector_prometheus) == 1
    error_message = "Expected kubectl_manifest.argocd_app_otel_collector_prometheus to exist when enable_prometheus=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_otel_collector_prometheus[0].yaml_body, "repoURL: ${local.policies_repo_url_cluster}")
    error_message = "Expected Prometheus OTel collector ArgoCD Application YAML to load from the policies repo"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_otel_collector_prometheus[0].yaml_body, "targetRevision: main") && strcontains(kubectl_manifest.argocd_app_otel_collector_prometheus[0].yaml_body, "path: ${local.vendored_chart_paths.opentelemetry_collector}")
    error_message = "Expected Prometheus OTel collector ArgoCD Application YAML to track the vendored chart on main"
  }
}

run "victoria_logs_enabled" {
  command = plan

  variables {
    cni_provider         = "none"
    enable_hubble        = false
    enable_argocd        = true
    enable_gitea         = true
    enable_signoz        = false
    enable_victoria_logs = true
    enable_sso           = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.observability) == 1
    error_message = "Expected kubernetes_namespace_v1.observability to exist when enable_victoria_logs=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_victoria_logs) == 1
    error_message = "Expected kubectl_manifest.argocd_app_victoria_logs to exist when enable_victoria_logs=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_victoria_logs[0].yaml_body, "path: ${local.vendored_chart_paths.victoria_logs}")
    error_message = "Expected VictoriaLogs ArgoCD Application YAML to track the vendored chart on main"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_otel_collector_prometheus) == 1
    error_message = "Expected kubectl_manifest.argocd_app_otel_collector_prometheus to exist when enable_victoria_logs=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_otel_collector_prometheus[0].yaml_body, "otlphttp/victoria-logs") && strcontains(kubectl_manifest.argocd_app_otel_collector_prometheus[0].yaml_body, "/insert/opentelemetry/v1/logs")
    error_message = "Expected the OTel gateway to fan logs out to VictoriaLogs when enable_victoria_logs=true"
  }
}

run "app_repo_sentiment_enabled" {
  command = plan

  variables {
    cni_provider              = "none"
    enable_hubble             = false
    enable_argocd             = true
    enable_gitea              = true
    enable_signoz             = false
    enable_sso                = false
    enable_actions_runner     = true
    enable_app_repo_sentiment = true
  }

  assert {
    condition     = length(kubernetes_namespace_v1.dev) == 1
    error_message = "Expected kubernetes_namespace_v1.dev to exist when enable_app_repo_sentiment=true"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.uat) == 1
    error_message = "Expected kubernetes_namespace_v1.uat to exist when enable_app_repo_sentiment=true"
  }

  assert {
    condition     = length(null_resource.sync_gitea_app_repo_sentiment) == 1
    error_message = "Expected null_resource.sync_gitea_app_repo_sentiment to exist when enable_app_repo_sentiment=true"
  }

  assert {
    condition     = length(tls_private_key.app_repo_sentiment) == 1
    error_message = "Expected tls_private_key.app_repo_sentiment to exist when enable_app_repo_sentiment=true"
  }

  assert {
    condition     = length(null_resource.wait_sentiment_images) == 1
    error_message = "Expected null_resource.wait_sentiment_images to exist when enable_app_repo_sentiment=true"
  }
}

run "app_repo_subnetcalc_enabled" {
  command = plan

  variables {
    cni_provider               = "none"
    enable_hubble              = false
    enable_argocd              = true
    enable_gitea               = true
    enable_signoz              = false
    enable_sso                 = false
    enable_actions_runner      = true
    enable_app_repo_subnetcalc = true
  }

  assert {
    condition     = length(kubernetes_namespace_v1.apim) == 1
    error_message = "Expected kubernetes_namespace_v1.apim to exist when enable_app_repo_subnetcalc=true"
  }

  assert {
    condition     = length(null_resource.sync_gitea_app_repo_subnetcalc) == 1
    error_message = "Expected null_resource.sync_gitea_app_repo_subnetcalc to exist when enable_app_repo_subnetcalc=true"
  }

  assert {
    condition     = length(tls_private_key.app_repo_subnetcalc) == 1
    error_message = "Expected tls_private_key.app_repo_subnetcalc to exist when enable_app_repo_subnetcalc=true"
  }

  assert {
    condition     = length(null_resource.wait_subnetcalc_images) == 1
    error_message = "Expected null_resource.wait_subnetcalc_images to exist when enable_app_repo_subnetcalc=true"
  }
}
