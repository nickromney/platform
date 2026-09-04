run "argocd_health_customizations_present" {
  command = plan

  variables {
    cni_provider  = "none"
    enable_hubble = false
    enable_argocd = true
    enable_gitea  = false
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

  # ObservabilityPolicy and SnippetsFilter health customizations went with
  # NGINX Gateway Fabric. Cilium owns Gateway API now and neither CRD is
  # installed, so a customization naming that API group would be dead config.
  assert {
    condition = length([
      for key in keys(local.argocd_values.configs.cm) : key
      if strcontains(key, "gateway.nginx.org")
    ]) == 0
    error_message = "Expected no Argo CD health customization for the retired NGINX Gateway Fabric API group"
  }
}
