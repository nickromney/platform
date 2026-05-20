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
      length(setsubtract(
        toset(concat(
          [
            "${local.argocd_public_url}/oauth2/callback",
            "${local.gitea_public_url}/oauth2/callback",
            "${local.hubble_public_url}/oauth2/callback",
            "${local.grafana_public_url}/oauth2/callback",
            "${local.signoz_public_url}/oauth2/callback",
            "${local.sentiment_dev_public_url}/oauth2/callback",
            "${local.sentiment_uat_public_url}/oauth2/callback",
            "${local.subnetcalc_dev_public_url}/oauth2/callback",
            "${local.subnetcalc_uat_public_url}/oauth2/callback",
          ],
          [for app in values(local.sso_idp_proxy_apps) : "${app.public_url}/oauth2/callback"],
          [for app in values(local.sso_mcp_console_proxy_apps) : "${app.public_url}/oauth2/callback"],
          [for app in values(local.sso_chatgpt_sim_proxy_apps) : "${app.public_url}/oauth2/callback"],
        )),
        toset(local.sso_oauth2_proxy_redirect_uris),
      )) == 0,
      contains(local.sso_oauth2_proxy_redirect_uris, "${local.chatgpt_sim_public_url}/oauth2/callback"),
      contains(local.sso_oauth2_proxy_redirect_uris, "${local.mcp_console_public_url}/oauth2/callback"),
      strcontains(file("${path.module}/sso.tf"), "redirectUris              = local.sso_oauth2_proxy_redirect_uris"),
      strcontains(file("${path.module}/sso.tf"), "local.sso_oauth2_proxy_redirect_uris : \"- $${uri}\""),
    ])
    error_message = "Expected every oauth2-proxy callback URL, including future map-backed endpoints, to be present in the Keycloak oauth2-proxy client redirectUris"
  }

  assert {
    condition = length(setsubtract(
      toset(distinct([
        for app in concat(
          values(local.sso_idp_proxy_apps),
          values(local.sso_mcp_console_proxy_apps),
          values(local.sso_chatgpt_sim_proxy_apps),
        ) : split(".", split("://", app.upstream)[1])[1]
      ])),
      toset(compact(flatten([
        for rule in yamldecode(file("${path.module}/cluster-policies/cilium/shared/sso-hardened.yaml")).spec.egress : [
          for target in try(rule.toEndpoints, []) : try(target.matchLabels["k8s:io.kubernetes.pod.namespace"], "")
        ]
      ]))),
    )) == 0
    error_message = "Expected sso-hardened egress to allow every map-backed oauth2-proxy upstream namespace so authenticated apps do not fail with 502s"
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
    condition = alltrue([
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_argocd[0].yaml_body, "cookieName: kind-v2-sso-admin"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_gitea[0].yaml_body, "cookieName: kind-v2-sso-admin"),
      !strcontains(kubectl_manifest.argocd_app_oauth2_proxy_gitea[0].yaml_body, "prompt: login"),
    ])
    error_message = "Expected admin oauth2-proxy apps to share the admin SSO cookie without forcing a fresh login prompt"
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
    condition     = local.argocd_values.dex.enabled == false
    error_message = "Expected Argo CD's bundled Dex deployment to be disabled when the platform uses Keycloak OIDC"
  }

  assert {
    condition     = length(null_resource.reconcile_keycloak_realm) == 1
    error_message = "Expected an imperative Keycloak realm reconcile step so existing Postgres-backed realms receive client/group changes"
  }

  assert {
    condition     = strcontains(file("${path.module}/sso.tf"), "    null_resource.wait_for_platform_gateway_tls,\n    null_resource.reconcile_keycloak_realm,\n    kubectl_manifest.argocd_app_dex,")
    error_message = "Expected kind apiserver OIDC configuration to wait for Keycloak realm reconciliation before restarting the apiserver"
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

run "app_sso_cookies_are_environment_scoped" {
  command = plan

  variables {
    cni_provider                    = "none"
    enable_hubble                   = false
    enable_argocd                   = true
    enable_gitea                    = true
    enable_signoz                   = false
    enable_gateway_tls              = true
    enable_sso                      = true
    enable_argocd_oidc              = false
    sso_provider                    = "keycloak"
    enable_headlamp                 = false
    enable_app_repo_sentiment       = true
    enable_app_repo_subnetcalc      = true
    enable_apim_simulator           = true
    enable_host_local_registry      = true
    prefer_external_workload_images = true
    external_workload_image_refs = {
      "sentiment-api"       = "host.docker.internal:5002/platform/sentiment-api:test"
      "sentiment-auth-ui"   = "host.docker.internal:5002/platform/sentiment-auth-ui:test"
      "subnetcalc-api"      = "host.docker.internal:5002/platform/subnetcalc-api:test"
      "subnetcalc-frontend" = "host.docker.internal:5002/platform/subnetcalc-frontend:test"
    }
    gitea_admin_pwd       = "test-admin-password"
    gitea_member_user_pwd = "test-demo-password"
  }

  assert {
    condition = alltrue([
      length(kubectl_manifest.argocd_app_oauth2_proxy_sentiment) == 1,
      length(kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc) == 1,
      length(kubectl_manifest.argocd_app_oauth2_proxy_idp) > 0,
    ])
    error_message = "Expected dev app oauth2-proxy Applications to render when dev apps and MCP are enabled"
  }

  assert {
    condition = alltrue([
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_sentiment[0].yaml_body, "cookieName: kind-v2-sso-dev"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc[0].yaml_body, "cookieName: kind-v2-sso-dev"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_idp["chatgpt"].yaml_body, "cookieName: kind-v2-sso-dev"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_idp["chatgpt"].yaml_body, "skip-auth-regex: ^/(signed-out\\.html|style\\.css|favicon\\.svg)$"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_sentiment_uat[0].yaml_body, "cookieName: kind-v2-sso-uat"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat[0].yaml_body, "cookieName: kind-v2-sso-uat"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_idp["api"].yaml_body, "cookieName: kind-v2-sso-portal"),
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_idp["console"].yaml_body, "cookieName: kind-v2-sso-portal"),
    ])
    error_message = "Expected oauth2-proxy app sessions to share one cookie per cookie domain so SSO carries across matching apps without a fresh Keycloak redirect"
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
      length(regexall("--allowed-group=app-subnetcalc-dev", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc[0].yaml_body)) > 0,
      length(regexall("--allowed-group=platform-admins", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc[0].yaml_body)) > 0,
      length(regexall("--allowed-group=app-subnetcalc-uat", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat[0].yaml_body)) > 0,
      length(regexall("--allowed-group=platform-admins", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat[0].yaml_body)) > 0,
      length(regexall("email-domain: \\\"(dev|uat)\\.test\\\"", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc[0].yaml_body)) == 0,
      length(regexall("email-domain: \\\"(dev|uat)\\.test\\\"", kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat[0].yaml_body)) == 0,
    ])
    error_message = "Expected subnetcalc oauth2-proxy to enforce app/environment groups plus platform-admins break-glass access instead of dev/uat email domains"
  }
}
