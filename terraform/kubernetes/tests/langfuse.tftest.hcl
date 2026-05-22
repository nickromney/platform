variables {
  gitea_admin_pwd       = "test-admin-password"
  gitea_member_user_pwd = "test-member-password"
}

run "langfuse_enabled_creates_gitops_app" {
  command = plan

  variables {
    cni_provider       = "none"
    enable_hubble      = false
    enable_argocd      = true
    enable_gitea       = true
    enable_gateway_tls = true
    enable_sso         = true
    enable_app_of_apps = false
    enable_langfuse    = true
  }

  assert {
    condition     = length(kubernetes_namespace_v1.langfuse) == 1
    error_message = "Expected Langfuse namespace when enable_langfuse=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_langfuse) == 1
    error_message = "Expected direct Langfuse Argo CD Application when app-of-apps is disabled"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_langfuse[0].yaml_body, "name: langfuse") && strcontains(kubectl_manifest.argocd_app_langfuse[0].yaml_body, "path: apps/langfuse")
    error_message = "Expected Langfuse Application YAML to sync apps/langfuse"
  }

  assert {
    condition = (
      strcontains(kubectl_manifest.argocd_app_langfuse[0].yaml_body, "ignoreDifferences:") &&
      strcontains(kubectl_manifest.argocd_app_langfuse[0].yaml_body, "kind: StatefulSet") &&
      strcontains(kubectl_manifest.argocd_app_langfuse[0].yaml_body, ".spec.volumeClaimTemplates[].status") &&
      strcontains(kubectl_manifest.argocd_app_langfuse[0].yaml_body, "RespectIgnoreDifferences=true")
    )
    error_message = "Expected Langfuse Application YAML to ignore Kubernetes-injected StatefulSet volumeClaimTemplate fields"
  }

  assert {
    condition     = contains(local.argocd_gitops_repo_app_names, "langfuse")
    error_message = "Expected langfuse in the Git-backed Argo refresh list when enable_langfuse=true"
  }

  assert {
    condition     = local.policies_repo_render_contract.enable_langfuse == true && local.policies_repo_render_contract.langfuse_public_host == local.langfuse_public_host
    error_message = "Expected GitOps render contract to carry Langfuse route inputs"
  }

  assert {
    condition     = contains(local.sso_oauth2_proxy_redirect_uris, "${local.langfuse_public_url}/oauth2/callback")
    error_message = "Expected Keycloak OAuth2 proxy client redirects to include Langfuse"
  }

  assert {
    condition     = strcontains(file("${path.module}/sso.tf"), "clientId                  = \"langfuse\"")
    error_message = "Expected Keycloak realm to include a native Langfuse OIDC client"
  }

  assert {
    condition = (
      local.langfuse_keycloak_redirect_uri == "${local.langfuse_public_url}/api/auth/callback/keycloak" &&
      strcontains(file("${path.module}/sso.tf"), "redirectUris              = [local.langfuse_keycloak_redirect_uri]")
    )
    error_message = "Expected native Langfuse OIDC client to allow the Keycloak callback URL"
  }

  assert {
    condition     = length(kubernetes_secret_v1.langfuse_keycloak_oidc) == 1
    error_message = "Expected Langfuse to receive a native Keycloak client secret"
  }

  assert {
    condition = (
      strcontains(file("${path.module}/apps/langfuse/all.yaml"), "AUTH_KEYCLOAK_CLIENT_ID: langfuse") &&
      strcontains(file("${path.module}/apps/langfuse/all.yaml"), "AUTH_KEYCLOAK_ISSUER: https://keycloak.127.0.0.1.sslip.io/realms/platform") &&
      strcontains(file("${path.module}/apps/langfuse/all.yaml"), "AUTH_KEYCLOAK_CLIENT_SECRET") &&
      strcontains(file("${path.module}/apps/langfuse/all.yaml"), "langfuse-keycloak-oidc") &&
      strcontains(file("${path.module}/apps/langfuse/all.yaml"), "NODE_TLS_REJECT_UNAUTHORIZED")
    )
    error_message = "Expected Langfuse manifest to configure native Keycloak SSO against the public issuer"
  }

  assert {
    condition = (
      length(kubectl_manifest.langfuse_web_hostaliases) == 1 &&
      strcontains(file("${path.module}/hostaliases.tf"), "resource \"kubectl_manifest\" \"langfuse_web_hostaliases\"") &&
      strcontains(file("${path.module}/hostaliases.tf"), "hostAliases:") &&
      strcontains(file("${path.module}/hostaliases.tf"), "local.sso_public_host")
    )
    error_message = "Expected Langfuse web pods to resolve the public Keycloak host through the internal gateway"
  }

  assert {
    condition     = contains(keys(kubectl_manifest.argocd_app_oauth2_proxy_idp), "langfuse")
    error_message = "Expected oauth2-proxy Langfuse Argo CD app when Langfuse is enabled"
  }

  assert {
    condition = (
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_idp["langfuse"].yaml_body, "name: oauth2-proxy-langfuse") &&
      strcontains(kubectl_manifest.argocd_app_oauth2_proxy_idp["langfuse"].yaml_body, "upstream: http://langfuse-web.langfuse.svc.cluster.local:3000")
    )
    error_message = "Expected Langfuse oauth2-proxy app to protect the Langfuse web service"
  }

  assert {
    condition = contains(
      compact(flatten([
        for rule in yamldecode(file("${path.module}/cluster-policies/cilium/shared/sso-hardened.yaml")).spec.egress : [
          for target in try(rule.toEndpoints, []) : try(target.matchLabels["k8s:io.kubernetes.pod.namespace"], "")
        ]
      ])),
      "langfuse",
    )
    error_message = "Expected sso-hardened to allow oauth2-proxy egress to Langfuse so browser sessions do not fail with 502 after login"
  }

  assert {
    condition     = kubectl_manifest.argocd_app_oauth2_proxy_idp["langfuse"].server_side_apply == true
    error_message = "Expected OAuth2 proxy Argo Applications to use server-side apply so existing Application CRs can be updated"
  }
}

run "langfuse_demos_enabled_creates_three_sso_apps" {
  command = plan

  variables {
    cni_provider                   = "none"
    enable_hubble                  = false
    enable_argocd                  = true
    enable_gitea                   = true
    enable_gateway_tls             = true
    enable_sso                     = true
    enable_app_of_apps             = false
    enable_agentgateway_ai_gateway = true
    enable_langfuse                = true
    enable_langfuse_demos          = true
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_langfuse_demos) == 1
    error_message = "Expected direct Langfuse demos Argo CD Application when demos are enabled and app-of-apps is disabled"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_langfuse_demos[0].yaml_body, "name: langfuse-demos") && strcontains(kubectl_manifest.argocd_app_langfuse_demos[0].yaml_body, "path: apps/langfuse-demos")
    error_message = "Expected Langfuse demos Application YAML to sync apps/langfuse-demos"
  }

  assert {
    condition = alltrue([
      contains(local.sso_oauth2_proxy_redirect_uris, "${local.langfuse_trace_chat_public_url}/oauth2/callback"),
      contains(local.sso_oauth2_proxy_redirect_uris, "${local.langfuse_tool_agent_public_url}/oauth2/callback"),
      contains(local.sso_oauth2_proxy_redirect_uris, "${local.langfuse_eval_runner_public_url}/oauth2/callback"),
      contains(keys(kubectl_manifest.argocd_app_oauth2_proxy_idp), "trace_chat"),
      contains(keys(kubectl_manifest.argocd_app_oauth2_proxy_idp), "tool_agent"),
      contains(keys(kubectl_manifest.argocd_app_oauth2_proxy_idp), "eval_runner"),
    ])
    error_message = "Expected Langfuse demo apps to have OAuth2 proxy apps and Keycloak callback redirects"
  }
}
