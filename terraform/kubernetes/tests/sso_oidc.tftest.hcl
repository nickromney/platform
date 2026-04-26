run "sso_enabled_argocd_oidc_disabled" {
  command = plan

  variables {
    cni_provider          = "none"
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    enable_signoz         = false
    enable_gateway_tls    = true
    enable_sso            = true
    enable_argocd_oidc    = false
    sso_provider          = "keycloak"
    enable_headlamp       = false
    gitea_admin_pwd       = "test-admin-password"
    gitea_member_user_pwd = "test-demo-password"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.sso) == 1
    error_message = "Expected kubernetes_namespace_v1.sso to exist when enable_sso=true"
  }

  assert {
    condition     = length(kubernetes_secret_v1.oauth2_proxy_oidc) == 1
    error_message = "Expected kubernetes_secret_v1.oauth2_proxy_oidc to exist when enable_sso=true"
  }

  assert {
    condition     = length(kubectl_manifest.keycloak) == 1
    error_message = "Expected kubectl_manifest.keycloak to exist when enable_sso=true and sso_provider=keycloak"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_oauth2_proxy_argocd) == 1
    error_message = "Expected kubectl_manifest.argocd_app_oauth2_proxy_argocd to exist when enable_sso=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_oauth2_proxy_gitea) == 1
    error_message = "Expected kubectl_manifest.argocd_app_oauth2_proxy_gitea to exist when enable_sso=true"
  }

  assert {
    condition     = local.argocd_values.configs.params["server.disable.auth"] == "true"
    error_message = "Expected ArgoCD server.disable.auth to be true when enable_sso=true and enable_argocd_oidc=false"
  }

  assert {
    condition     = try(local.argocd_values.configs.cm["oidc.config"], null) == null
    error_message = "Did not expect ArgoCD oidc.config when enable_argocd_oidc=false"
  }
}

run "sso_enabled_argocd_oidc_enabled" {
  command = plan

  variables {
    cni_provider          = "none"
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    enable_signoz         = false
    enable_gateway_tls    = true
    enable_sso            = true
    enable_argocd_oidc    = true
    sso_provider          = "keycloak"
    enable_headlamp       = false
    gitea_admin_pwd       = "test-admin-password"
    gitea_member_user_pwd = "test-demo-password"
  }

  assert {
    condition     = local.argocd_values.configs.params["server.disable.auth"] == "false"
    error_message = "Expected ArgoCD server.disable.auth to be false when enable_sso=true and enable_argocd_oidc=true"
  }

  assert {
    condition = alltrue([
      length(regexall("clientID: argocd", local.argocd_values.configs.cm["oidc.config"])) > 0,
      length(regexall("clientSecret: \\$oidc\\.platform\\.clientSecret", local.argocd_values.configs.cm["oidc.config"])) > 0,
    ])
    error_message = "Expected ArgoCD oidc.config to include clientID argocd and clientSecret $oidc.platform.clientSecret when enable_argocd_oidc=true"
  }

  assert {
    condition     = length(regexall("issuer: https://keycloak\\.127\\.0\\.0\\.1\\.sslip\\.io/realms/platform", local.argocd_values.configs.cm["oidc.config"])) > 0
    error_message = "Expected ArgoCD oidc.config to reference the Keycloak issuer when enable_argocd_oidc=true"
  }

  assert {
    condition     = length(kubectl_manifest.keycloak) == 1 && length(kubectl_manifest.argocd_app_dex) == 0
    error_message = "Expected Keycloak to be present and Dex Argo CD app to be absent when sso_provider=keycloak"
  }
}

run "sso_with_subnetcalc_apps" {
  command = plan

  variables {
    cni_provider               = "none"
    enable_hubble              = false
    enable_argocd              = true
    enable_gitea               = true
    enable_signoz              = false
    enable_gateway_tls         = true
    enable_sso                 = true
    sso_provider               = "keycloak"
    enable_actions_runner      = true
    enable_app_repo_subnetcalc = true
    gitea_admin_pwd            = "test-admin-password"
    gitea_member_user_pwd      = "test-demo-password"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.apim) == 1
    error_message = "Expected kubernetes_namespace_v1.apim to exist when enable_app_repo_subnetcalc=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc) == 1
    error_message = "Expected kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc to exist when enable_sso=true and enable_app_repo_subnetcalc=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat) == 1
    error_message = "Expected kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat to exist when enable_sso=true and enable_app_repo_subnetcalc=true"
  }

  assert {
    condition     = length(regexall("email-domain: \\\"uat\\.test\\\"", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat[0].yaml_body)) > 0
    error_message = "Expected subnetcalc UAT oauth2-proxy to restrict logins to uat.test"
  }
}
