run "direct_mode_creates_workload_apps" {
  command = plan

  variables {
    cni_provider               = "cilium"
    enable_hubble              = false
    enable_argocd              = true
    enable_gitea               = true
    enable_policies            = true
    enable_gateway_tls         = true
    enable_actions_runner      = true
    enable_app_of_apps         = false
    enable_app_repo_sentiment  = true
    enable_app_repo_subnetcalc = true
    gitea_admin_pwd            = "test-gitea-admin-password"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_apim) == 1
    error_message = "Expected direct Argo CD Application for apim when app-of-apps is disabled and subnetcalc is enabled"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_dev) == 1
    error_message = "Expected direct Argo CD Application for dev when app-of-apps is disabled and workload repos are enabled"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_uat) == 1
    error_message = "Expected direct Argo CD Application for uat when app-of-apps is disabled and workload repos are enabled"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_idp) == 0
    error_message = "Did not expect IDP Application until SSO is enabled"
  }
}

run "direct_mode_creates_idp_app_when_sso_enabled" {
  command = plan

  variables {
    cni_provider          = "cilium"
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    enable_policies       = true
    enable_gateway_tls    = true
    enable_sso            = true
    enable_app_of_apps    = false
    enable_actions_runner = true
    gitea_admin_pwd       = "test-gitea-admin-password"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_idp) == 1
    error_message = "Expected direct Argo CD Application for idp when SSO is enabled"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_idp[0].yaml_body, "name: idp") && strcontains(kubectl_manifest.argocd_app_idp[0].yaml_body, "path: apps/idp")
    error_message = "Expected IDP Application YAML to sync apps/idp"
  }
}

run "direct_mode_supports_apim_simulator_without_subnetcalc_repo" {
  command = plan

  variables {
    cni_provider          = "cilium"
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    enable_policies       = true
    enable_gateway_tls    = true
    enable_actions_runner = true
    enable_app_of_apps    = false
    enable_apim_simulator = true
    gitea_admin_pwd       = "test-gitea-admin-password"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.apim) == 1 && length(kubectl_manifest.argocd_app_apim) == 1
    error_message = "Expected APIM simulator namespace and Argo CD app when enable_apim_simulator=true"
  }

  assert {
    condition     = length(null_resource.sync_gitea_app_repo_subnetcalc) == 0 && length(kubectl_manifest.argocd_app_dev) == 0 && length(kubectl_manifest.argocd_app_uat) == 0
    error_message = "Expected APIM simulator toggle not to seed subnetcalc or app environment repos by itself"
  }
}

run "direct_mode_supports_agentgateway_without_apim" {
  command = plan

  variables {
    cni_provider                   = "cilium"
    enable_hubble                  = false
    enable_argocd                  = true
    enable_gitea                   = true
    enable_policies                = true
    enable_gateway_tls             = true
    enable_sso                     = true
    enable_actions_runner          = true
    enable_app_of_apps             = false
    enable_agentgateway_ai_gateway = true
    gitea_admin_pwd                = "test-gitea-admin-password"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.apim) == 0 && length(kubectl_manifest.argocd_app_apim) == 0
    error_message = "Did not expect APIM simulator resources when only agentgateway is enabled"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.agentgateway) == 1 && length(kubectl_manifest.argocd_app_agentgateway_crds) == 1 && length(kubectl_manifest.argocd_app_agentgateway) == 1 && length(kubectl_manifest.argocd_app_agentgateway_ai_gateway) == 1
    error_message = "Expected agentgateway namespace, Argo CD chart apps, and AI gateway app when enable_agentgateway_ai_gateway=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_mcp) == 1
    error_message = "Expected MCP app to remain available for agentgateway-only AI gateway mode"
  }
}
