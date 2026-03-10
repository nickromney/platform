run "sso_enabled_argocd_oidc_disabled" {
  command = plan

  variables {
    cni_provider       = "none"
    enable_hubble      = false
    enable_argocd      = true
    enable_gitea       = true
    enable_signoz      = false
    enable_gateway_tls = true
    enable_sso         = true
    enable_argocd_oidc = false
    enable_headlamp    = false
  }

  assert {
    condition     = length(kubernetes_namespace.sso) == 1
    error_message = "Expected kubernetes_namespace.sso to exist when enable_sso=true"
  }

  assert {
    condition     = length(kubernetes_secret.oauth2_proxy_oidc) == 1
    error_message = "Expected kubernetes_secret.oauth2_proxy_oidc to exist when enable_sso=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_dex) == 1
    error_message = "Expected kubectl_manifest.argocd_app_dex to exist when enable_sso=true"
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
    cni_provider       = "none"
    enable_hubble      = false
    enable_argocd      = true
    enable_gitea       = true
    enable_signoz      = false
    enable_gateway_tls = true
    enable_sso         = true
    enable_argocd_oidc = true
    enable_headlamp    = false
  }

  assert {
    condition     = local.argocd_values.configs.params["server.disable.auth"] == "false"
    error_message = "Expected ArgoCD server.disable.auth to be false when enable_sso=true and enable_argocd_oidc=true"
  }

  assert {
    condition = alltrue([
      length(regexall("clientID: argocd", local.argocd_values.configs.cm["oidc.config"])) > 0,
      length(regexall("clientSecret: \\$oidc\\.dex\\.clientSecret", local.argocd_values.configs.cm["oidc.config"])) > 0,
    ])
    error_message = "Expected ArgoCD oidc.config to include clientID argocd and clientSecret $oidc.dex.clientSecret when enable_argocd_oidc=true"
  }

  assert {
    condition     = length(regexall("issuer: https://dex\\.127\\.0\\.0\\.1\\.sslip\\.io/dex", local.argocd_values.configs.cm["oidc.config"])) > 0
    error_message = "Expected ArgoCD oidc.config to reference the Dex issuer when enable_argocd_oidc=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_dex) == 1
    error_message = "Expected Dex application to be present when enable_sso=true and enable_argocd_oidc=true"
  }
}

run "sso_with_subnetcalc_apps" {
  command = plan

  variables {
    cni_provider                      = "none"
    enable_hubble                     = false
    enable_argocd                     = true
    enable_gitea                      = true
    enable_signoz                     = false
    enable_gateway_tls                = true
    enable_sso                        = true
    enable_actions_runner             = true
    enable_app_repo_subnet_calculator = true
  }

  assert {
    condition     = length(kubernetes_namespace.apim) == 1
    error_message = "Expected kubernetes_namespace.apim to exist when enable_app_repo_subnet_calculator=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc) == 1
    error_message = "Expected kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc to exist when enable_sso=true and enable_app_repo_subnet_calculator=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat) == 1
    error_message = "Expected kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat to exist when enable_sso=true and enable_app_repo_subnet_calculator=true"
  }

  assert {
    condition     = length(regexall("email-domain: \\\"uat\\.test\\\"", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat[0].yaml_body)) > 0
    error_message = "Expected subnetcalc UAT oauth2-proxy to restrict logins to uat.test"
  }
}
