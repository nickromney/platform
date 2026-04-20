run "argocd_health_customizations_present" {
  command = plan

  variables {
    cni_provider  = "none"
    enable_hubble = false
    enable_argocd = true
    enable_gitea  = false
    enable_signoz = false
  }

  assert {
    condition     = strcontains(local.argocd_values.configs.cm["resource.customizations.health.apps_Deployment"], "Deployment rollout complete")
    error_message = "Expected Argo CD to define a Deployment health customization"
  }

  assert {
    condition = alltrue([
      strcontains(local.argocd_values.configs.cm["resource.customizations.health.gateway.networking.k8s.io_HTTPRoute"], "Accepted"),
      strcontains(local.argocd_values.configs.cm["resource.customizations.health.gateway.networking.k8s.io_HTTPRoute"], "ResolvedRefs"),
    ])
    error_message = "Expected Argo CD to define HTTPRoute health based on Accepted and ResolvedRefs conditions"
  }

  assert {
    condition     = strcontains(local.argocd_values.configs.cm["resource.customizations.health.gateway.networking.k8s.io_ReferenceGrant"], "ReferenceGrant applied")
    error_message = "Expected Argo CD to define ReferenceGrant health"
  }

  assert {
    condition     = strcontains(local.argocd_values.configs.cm["resource.customizations.health.gateway.nginx.org_ObservabilityPolicy"], "ObservabilityPolicy applied")
    error_message = "Expected Argo CD to define ObservabilityPolicy health"
  }

  assert {
    condition     = strcontains(local.argocd_values.configs.cm["resource.customizations.health.gateway.nginx.org_SnippetsFilter"], "SnippetsFilter applied")
    error_message = "Expected Argo CD to define SnippetsFilter health"
  }
}
