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

    headlamp_chart_version = "0.40.0"
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
    condition     = length(regexall("targetRevision: ${var.headlamp_chart_version}", kubectl_manifest.argocd_app_headlamp[0].yaml_body)) > 0
    error_message = "Expected Headlamp ArgoCD Application YAML to include targetRevision matching var.headlamp_chart_version"
  }
}
