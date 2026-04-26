run "headlamp_enabled" {
  command = plan

  variables {
    cni_provider    = "none"
    enable_hubble   = false
    enable_argocd   = true
    enable_gitea    = false
    enable_signoz   = false
    enable_sso      = false
    enable_headlamp = true
    sso_provider    = "keycloak"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.headlamp) == 1
    error_message = "Expected kubernetes_namespace_v1.headlamp to exist when enable_headlamp=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_headlamp) == 1
    error_message = "Expected kubectl_manifest.argocd_app_headlamp to exist when enable_headlamp=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_headlamp[0].yaml_body, "repoURL: ${local.policies_repo_url_cluster}")
    error_message = "Expected Headlamp ArgoCD Application YAML to load from the policies repo"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_headlamp[0].yaml_body, "targetRevision: main") && strcontains(kubectl_manifest.argocd_app_headlamp[0].yaml_body, "path: ${local.vendored_chart_paths.headlamp}")
    error_message = "Expected Headlamp ArgoCD Application YAML to track the vendored chart on main"
  }
}

run "headlamp_sso_uses_selected_oidc_provider" {
  command = plan

  variables {
    cni_provider          = "none"
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    enable_signoz         = false
    enable_gateway_tls    = true
    enable_sso            = true
    enable_headlamp       = true
    sso_provider          = "keycloak"
    gitea_admin_pwd       = "test-admin-password"
    gitea_member_user_pwd = "test-demo-password"
  }

  assert {
    condition     = local.headlamp_config.oidc.issuerURL == "https://keycloak.127.0.0.1.sslip.io/realms/platform"
    error_message = "Expected Headlamp OIDC issuerURL to follow the selected Keycloak provider"
  }

  assert {
    condition     = contains(local.headlamp_config.extraArgs, "-oidc-ca-file=/headlamp-ca/ca.crt")
    error_message = "Expected Headlamp to trust the mkcert CA for local OIDC"
  }
}
