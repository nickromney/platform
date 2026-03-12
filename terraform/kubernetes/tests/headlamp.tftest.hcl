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
