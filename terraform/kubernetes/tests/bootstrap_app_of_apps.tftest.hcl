run "app_of_apps_enabled_disables_direct_apps" {
  command = plan

  variables {
    cni_provider          = "cilium"
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    enable_signoz         = false
    enable_policies       = true
    enable_gateway_tls    = true
    enable_actions_runner = true
    enable_app_of_apps    = true
  }

  assert {
    condition     = local.enable_gitops_repo
    error_message = "Expected local.enable_gitops_repo to be true when app-of-apps prerequisites are enabled"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_of_apps) == 1
    error_message = "Expected kubectl_manifest.argocd_app_of_apps to exist when enable_app_of_apps=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_kyverno) == 0
    error_message = "Did not expect direct Kyverno Application when enable_app_of_apps=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_kyverno_policies) == 0
    error_message = "Did not expect direct Kyverno policies Application when enable_app_of_apps=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_cilium_policies) == 0
    error_message = "Did not expect direct Cilium policies Application when enable_app_of_apps=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_gitea_actions_runner) == 0
    error_message = "Did not expect direct Gitea actions runner Application when enable_app_of_apps=true"
  }
}

run "image_preload_enabled_by_default" {
  command = plan

  variables {
    cni_provider  = "none"
    enable_hubble = false
    enable_argocd = false
    enable_gitea  = false
    enable_signoz = false
  }

  assert {
    condition     = length(null_resource.preload_images) == 1
    error_message = "Expected null_resource.preload_images to exist when enable_image_preload=true"
  }
}

run "image_preload_can_be_disabled" {
  command = plan

  variables {
    cni_provider         = "none"
    enable_hubble        = false
    enable_argocd        = false
    enable_gitea         = false
    enable_signoz        = false
    enable_image_preload = false
  }

  assert {
    condition     = length(null_resource.preload_images) == 0
    error_message = "Did not expect null_resource.preload_images when enable_image_preload=false"
  }
}

run "gitea_admin_promotions_always_keep_bootstrap_admin" {
  command = plan

  variables {
    cni_provider              = "none"
    enable_hubble             = false
    enable_argocd             = true
    enable_gitea              = true
    enable_signoz             = false
    gitea_admin_username      = "gitea-admin"
    gitea_admin_promote_users = ["demo-admin"]
  }

  assert {
    condition     = contains(local.gitea_admin_promote_users_effective, "gitea-admin")
    error_message = "Expected the bootstrap Gitea admin user to remain in the promoted-user set"
  }

  assert {
    condition     = contains(local.gitea_admin_promote_users_effective, "demo-admin")
    error_message = "Expected additional promoted users to remain in the promoted-user set"
  }
}
