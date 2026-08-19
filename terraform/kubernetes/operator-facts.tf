locals {
  operator_facts = {
    schema_version                         = "0.1"
    cni_provider                           = var.cni_provider
    enable_cilium                          = local.enable_cilium_effective
    provision_kind_cluster                 = var.provision_kind_cluster
    enable_cilium_wireguard                = var.enable_cilium_wireguard
    enable_hubble                          = var.enable_hubble
    enable_argocd                          = var.enable_argocd
    enable_gitea                           = var.enable_gitea
    enable_policies                        = var.enable_policies
    enable_cilium_policies                 = var.enable_cilium_policies
    enable_app_of_apps                     = var.enable_app_of_apps
    enable_cilium_policy_audit_mode        = var.enable_cilium_policy_audit_mode
    enable_victoria_logs                   = var.enable_victoria_logs
    enable_headlamp                        = var.enable_headlamp
    enable_gateway_tls                     = var.enable_gateway_tls
    enable_sso                             = var.enable_sso
    sso_provider                           = var.sso_provider
    enable_prometheus                      = var.enable_prometheus
    enable_metrics_server                  = var.enable_metrics_server
    enable_external_secrets                = var.enable_external_secrets
    enable_progressive_delivery            = var.enable_progressive_delivery
    enable_grafana                         = var.enable_grafana
    enable_actions_runner                  = var.enable_actions_runner
    enable_apim_simulator                  = var.enable_apim_simulator
    enable_agentgateway_ai_gateway         = var.enable_agentgateway_ai_gateway
    enable_app_repo_subnetcalc             = var.enable_app_repo_subnetcalc
    enable_app_repo_sentiment              = var.enable_app_repo_sentiment
    enable_langfuse                        = var.enable_langfuse
    enable_langfuse_demos                  = var.enable_langfuse_demos
    prefer_external_workload_images        = var.prefer_external_workload_images
    enable_gitops_repo                     = local.enable_gitops_repo
    cluster_name                           = var.cluster_name
    argocd_namespace                       = var.argocd_namespace
    gateway_https_host_port                = var.gateway_https_host_port
    platform_base_domain                   = var.platform_base_domain
    platform_admin_base_domain             = var.platform_admin_base_domain
    keycloak_realm                         = var.keycloak_realm
  }
}

resource "local_file" "operator_facts" {
  filename             = "${local.run_dir}/operator-facts.json"
  content              = jsonencode(local.operator_facts)
  file_permission      = "0644"
  directory_permission = "0700"
}
