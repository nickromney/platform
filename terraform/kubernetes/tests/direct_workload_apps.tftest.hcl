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
}
