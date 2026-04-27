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
    condition = alltrue([
      length(kubectl_manifest.oauth2_proxy_session_store_deployment) == 1,
      length(kubectl_manifest.oauth2_proxy_session_store_service) == 1,
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_argocd[0].yaml_body, "session-store-type: redis"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_argocd[0].yaml_body, "redis-connection-url: ${local.oauth2_proxy_redis_url}"),
    ])
    error_message = "Expected oauth2-proxy to use an internal Redis session store for Keycloak token sessions"
  }

  assert {
    condition     = length(kubectl_manifest.keycloak) == 1
    error_message = "Expected kubectl_manifest.keycloak to exist when enable_sso=true and sso_provider=keycloak"
  }

  assert {
    condition = alltrue([
      length(kubernetes_secret_v1.keycloak_bootstrap_admin) == 1,
      length(kubernetes_secret_v1.keycloak_admin) == 1,
      kubernetes_secret_v1.keycloak_bootstrap_admin[0].data.username == "keycloak-bootstrap-admin",
      kubernetes_secret_v1.keycloak_admin[0].data.username == "keycloak-admin",
      strcontains(kubectl_manifest.keycloak[0].yaml_body, "name: keycloak-bootstrap-admin"),
    ])
    error_message = "Expected Keycloak to separate the temporary bootstrap admin from the permanent console admin"
  }

  assert {
    condition = alltrue([
      strcontains(file("${path.module}/sso.tf"), "email         = \"demo@admin.test\""),
      strcontains(file("${path.module}/sso.tf"), "email         = \"demo@dev.test\""),
      strcontains(file("${path.module}/sso.tf"), "email         = \"demo@uat.test\""),
      strcontains(file("${path.module}/sso.tf"), "emailVerified = true"),
    ])
    error_message = "Expected all rendered platform realm demo users to have verified email addresses"
  }

  assert {
    condition = alltrue([
      strcontains(file("${path.module}/scripts/reconcile-keycloak-realm.sh"), "KEYCLOAK_PERMANENT_ADMIN_EMAIL:-keycloak-admin@platform.local"),
      strcontains(file("${path.module}/scripts/reconcile-keycloak-realm.sh"), "ensure_group_client_role \"platform-admins\" \"realm-management\" \"realm-admin\""),
      strcontains(file("${path.module}/scripts/reconcile-keycloak-realm.sh"), "delete_bootstrap_admins_from_master"),
      strcontains(file("${path.module}/scripts/reconcile-keycloak-realm.sh"), "reconcile_client_scope_attachments"),
      strcontains(file("${path.module}/scripts/reconcile-keycloak-realm.sh"), "detach_client_scope_attachment"),
    ])
    error_message = "Expected Keycloak reconcile to give platform-admins realm admin rights, email the break-glass admin, delete bootstrap admins, and prune oversized client scopes"
  }

  assert {
    condition = alltrue([
      length(regexall("fullScopeAllowed\\s*=\\s*false", file("${path.module}/sso.tf"))) >= 3,
      length(regexall("defaultClientScopes\\s*=\\s*\\[\"web-origins\", \"acr\", \"profile\", \"basic\", \"email\"\\]", file("${path.module}/sso.tf"))) >= 3,
      length(regexall("defaultClientScopes\\s*=\\s*\\[[^\\]]*\"roles\"", file("${path.module}/sso.tf"))) == 0,
    ])
    error_message = "Expected Keycloak app clients to expose groups without inheriting role-heavy default scopes"
  }

  assert {
    condition = alltrue([
      strcontains(file("${path.module}/locals.tf"), "sso_apim_audience                    = \"apim-simulator\""),
      strcontains(file("${path.module}/sso.tf"), "clientId                  = local.sso_apim_audience"),
      strcontains(file("${path.module}/sso.tf"), "\"included.client.audience\" = local.sso_apim_audience"),
      strcontains(file("${path.module}/apps/apim/all.yaml"), "\"audience\": \"apim-simulator\""),
      strcontains(file("${path.module}/scripts/check-sso.sh"), "EXPECTED_APIM_AUDIENCE"),
    ])
    error_message = "Expected APIM to use a dedicated Keycloak resource audience rather than the oauth2-proxy browser client"
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
    condition = alltrue([
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_argocd[0].yaml_body, "allowed-group: platform-viewers"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_gitea[0].yaml_body, "allowed-group: platform-admins"),
      !strcontains(kubectl_manifest.argocd_app_oauth2_proxy_argocd[0].yaml_body, "email-domain: \"admin.test\""),
      !strcontains(kubectl_manifest.argocd_app_oauth2_proxy_gitea[0].yaml_body, "email-domain: \"admin.test\""),
    ])
    error_message = "Expected admin SSO proxies to use Keycloak org groups rather than admin email-domain shortcuts"
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

  assert {
    condition     = length(null_resource.reconcile_keycloak_realm) == 1
    error_message = "Expected an imperative Keycloak realm reconcile step so existing Postgres-backed realms receive client/group changes"
  }

  assert {
    condition = alltrue([
      strcontains(file("${path.module}/scripts/check-rbac.sh"), "keycloak_id_token"),
      strcontains(file("${path.module}/scripts/check-rbac.sh"), ".id_token // empty"),
      strcontains(file("${path.module}/scripts/check-rbac.sh"), "real OIDC token kubectl auth can-i"),
      strcontains(file("${path.module}/scripts/check-rbac.sh"), "KUBECONFIG=/dev/null"),
      strcontains(file("${path.module}/scripts/check-sso.sh"), "EXPECTED_CLUSTER_NAME=\"$${KUBECONFIG_CONTEXT#kind-}\""),
    ])
    error_message = "Expected SSO/RBAC checkers to exercise isolated real tokens and resolve kind context names to kind cluster names"
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
    condition = alltrue([
      length(regexall("allowed-group: app-subnetcalc-dev", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc[0].yaml_body)) > 0,
      length(regexall("allowed-group: app-subnetcalc-uat", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat[0].yaml_body)) > 0,
      length(regexall("email-domain: \\\"(dev|uat)\\.test\\\"", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc[0].yaml_body)) == 0,
      length(regexall("email-domain: \\\"(dev|uat)\\.test\\\"", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat[0].yaml_body)) == 0,
    ])
    error_message = "Expected subnetcalc oauth2-proxy to enforce app/environment groups instead of dev/uat email domains"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_oauth2_proxy_hello_platform) == 2
    error_message = "Expected hello-platform dev and UAT oauth2-proxy Argo CD applications to exist"
  }

  assert {
    condition = alltrue([
      length([for app in kubectl_manifest.argocd_app_oauth2_proxy_hello_platform : app if length(regexall("allowed-group: app-hello-platform-dev", app.yaml_body)) > 0]) == 1,
      length([for app in kubectl_manifest.argocd_app_oauth2_proxy_hello_platform : app if length(regexall("allowed-group: app-hello-platform-uat", app.yaml_body)) > 0]) == 1,
      alltrue([for app in kubectl_manifest.argocd_app_oauth2_proxy_hello_platform : length(regexall("email-domain: \\\"(dev|uat)\\.test\\\"", app.yaml_body)) == 0]),
    ])
    error_message = "Expected hello-platform oauth2-proxy apps to enforce app/environment groups instead of dev/uat email domains"
  }
}
