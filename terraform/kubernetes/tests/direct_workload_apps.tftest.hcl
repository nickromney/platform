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
