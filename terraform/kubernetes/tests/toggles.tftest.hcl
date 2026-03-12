run "cilium_enabled" {
  command = plan

  variables {
    cni_provider  = "cilium"
    enable_hubble = false
    enable_argocd = false
    enable_gitea  = false
    enable_signoz = false

    cilium_version = "1.19.1"
  }

  assert {
    condition     = length(helm_release.cilium) == 1
    error_message = "Expected helm_release.cilium to exist when enable_cilium=true"
  }

  assert {
    condition     = helm_release.cilium[0].version == var.cilium_version
    error_message = "Expected helm_release.cilium version to match var.cilium_version"
  }
}

run "argocd_enabled" {
  command = plan

  variables {
    cni_provider  = "cilium"
    enable_hubble = true
    enable_argocd = true
    enable_gitea  = false
    enable_signoz = false

    argocd_chart_version    = "9.4.1"
    argocd_namespace        = "argocd"
    argocd_server_node_port = 30080
  }

  assert {
    condition     = length(kubernetes_namespace_v1.argocd) == 1
    error_message = "Expected kubernetes_namespace_v1.argocd to exist when enable_argocd=true"
  }

  assert {
    condition     = length(helm_release.argocd) == 1
    error_message = "Expected helm_release.argocd to exist when enable_argocd=true"
  }

  assert {
    condition     = helm_release.argocd[0].version == var.argocd_chart_version
    error_message = "Expected helm_release.argocd version to match var.argocd_chart_version"
  }
}

run "gitea_enabled" {
  command = plan

  variables {
    cni_provider  = "cilium"
    enable_hubble = true
    enable_argocd = true
    enable_gitea  = true
    enable_signoz = false

    gitea_chart_version  = "12.5.0"
    gitea_http_node_port = 30090
    gitea_ssh_node_port  = 30022
  }

  assert {
    condition     = length(kubernetes_namespace_v1.gitea) == 1
    error_message = "Expected kubernetes_namespace_v1.gitea to exist when enable_gitea=true"
  }

  assert {
    condition     = length(kubernetes_secret_v1.gitea_admin) == 1
    error_message = "Expected kubernetes_secret_v1.gitea_admin to exist when enable_gitea=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_gitea) == 1
    error_message = "Expected kubectl_manifest.argocd_app_gitea to exist when enable_gitea=true"
  }

  assert {
    condition     = length(regexall("targetRevision: ${var.gitea_chart_version}", kubectl_manifest.argocd_app_gitea[0].yaml_body)) > 0
    error_message = "Expected Gitea ArgoCD Application YAML to include targetRevision matching var.gitea_chart_version"
  }
}

run "signoz_enabled" {
  command = plan

  variables {
    cni_provider        = "cilium"
    enable_hubble       = true
    enable_argocd       = true
    enable_gitea        = true
    enable_signoz       = true
    signoz_ui_node_port = 30301
  }

  assert {
    condition     = length(kubernetes_namespace_v1.observability) == 1
    error_message = "Expected kubernetes_namespace_v1.observability to exist when enable_signoz=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_signoz) == 1
    error_message = "Expected kubectl_manifest.argocd_app_signoz to exist when enable_signoz=true"
  }

  assert {
    condition     = length(kubectl_manifest.signoz_ui_nodeport) == 1
    error_message = "Expected kubectl_manifest.signoz_ui_nodeport to exist when enable_signoz=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_signoz[0].yaml_body, "repoURL: ${local.policies_repo_url_cluster}")
    error_message = "Expected SigNoz ArgoCD Application YAML to load from the policies repo"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_signoz[0].yaml_body, "targetRevision: main") && strcontains(kubectl_manifest.argocd_app_signoz[0].yaml_body, "path: ${local.vendored_chart_paths.signoz}")
    error_message = "Expected SigNoz ArgoCD Application YAML to track the vendored chart on main"
  }
}

run "sso_enabled" {
  command = plan

  variables {
    cni_provider       = "cilium"
    enable_hubble      = true
    enable_argocd      = true
    enable_gitea       = true
    enable_signoz      = true
    enable_gateway_tls = true
    enable_sso         = true

    dex_chart_version          = "0.24.0"
    oauth2_proxy_chart_version = "10.1.4"

    platform_gateway_routes_path = "apps/platform-gateway-routes-sso"
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
    condition     = length(kubectl_manifest.argocd_app_dex) == 1
    error_message = "Expected kubectl_manifest.argocd_app_dex to exist when enable_sso=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_oauth2_proxy_argocd) == 1
    error_message = "Expected kubectl_manifest.argocd_app_oauth2_proxy_argocd to exist when enable_sso=true"
  }

  assert {
    condition     = length(regexall("path: ${var.platform_gateway_routes_path}", kubectl_manifest.argocd_app_platform_gateway_routes[0].yaml_body)) > 0
    error_message = "Expected platform-gateway-routes Application YAML to include path matching var.platform_gateway_routes_path"
  }

  assert {
    condition     = length(kubectl_manifest.gateway_bootstrap_crds) > 0
    error_message = "Expected Terraform to bootstrap gateway CRDs when enable_gateway_tls=true"
  }

  assert {
    condition     = !contains(local.argocd_gitops_repo_app_names, "nginx-gateway-fabric-crds")
    error_message = "Did not expect nginx-gateway-fabric-crds in the direct GitOps app list after moving CRD ownership to Terraform"
  }
}
