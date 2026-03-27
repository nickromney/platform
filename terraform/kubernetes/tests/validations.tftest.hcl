run "headlamp_requires_argocd" {
  command = plan

  variables {
    enable_argocd   = false
    enable_headlamp = true
  }

  expect_failures = [check.enable_headlamp_requires_enable_argocd]
}

run "actions_runner_requires_gitea_and_argocd" {
  command = plan

  variables {
    cni_provider          = "none"
    enable_hubble         = false
    enable_gitea          = false
    enable_argocd         = true
    enable_actions_runner = true
  }

  expect_failures = [check.enable_actions_runner_requires_gitea_and_argocd]
}

run "policies_requires_argocd_gitea_cilium" {
  command = plan

  variables {
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    gitea_admin_pwd       = "test-admin-password"
    gitea_member_user_pwd = "test-member-password"
    cni_provider          = "none"
    enable_policies       = true
  }

  expect_failures = [check.enable_policies_requires_argocd_gitea_cilium]
}

run "cilium_policy_audit_mode_requires_cilium" {
  command = plan

  variables {
    cni_provider                     = "none"
    enable_hubble                    = false
    enable_argocd                    = false
    enable_cilium_policy_audit_mode  = true
  }

  expect_failures = [check.enable_cilium_policy_audit_mode_requires_cilium_provider]
}

run "observability_agent_requires_signoz_and_argocd" {
  command = plan

  variables {
    cni_provider               = "none"
    enable_hubble              = false
    enable_argocd              = true
    enable_signoz              = false
    enable_observability_agent = true
  }

  expect_failures = [check.enable_observability_agent_requires_signoz_and_argocd]
}

run "victoria_logs_requires_argocd" {
  command = plan

  variables {
    enable_argocd        = false
    enable_victoria_logs = true
  }

  expect_failures = [check.enable_victoria_logs_requires_argocd]
}

run "sso_requires_gateway_tls_argocd_gitea" {
  command = plan

  variables {
    cni_provider          = "none"
    enable_hubble         = false
    enable_gateway_tls    = false
    enable_argocd         = true
    enable_gitea          = true
    gitea_admin_pwd       = "test-admin-password"
    gitea_member_user_pwd = "test-member-password"
    enable_sso            = true
  }

  expect_failures = [check.enable_sso_requires_gateway_tls_argocd_gitea]
}

run "app_repo_sentiment_requires_gitea_and_actions_runner" {
  command = plan

  variables {
    cni_provider              = "none"
    enable_hubble             = false
    enable_gitea              = true
    gitea_admin_pwd           = "test-admin-password"
    gitea_member_user_pwd     = "test-member-password"
    enable_actions_runner     = false
    enable_app_repo_sentiment = true
  }

  expect_failures = [check.enable_app_repo_sentiment_requires_gitea_and_actions_runner]
}

run "app_repo_subnetcalc_requires_gitea_and_actions_runner" {
  command = plan

  variables {
    cni_provider                      = "none"
    enable_hubble                     = false
    enable_gitea                      = true
    gitea_admin_pwd                   = "test-admin-password"
    gitea_member_user_pwd             = "test-member-password"
    enable_actions_runner             = false
    enable_app_repo_subnet_calculator = true
  }

  expect_failures = [check.enable_app_repo_subnet_calculator_requires_gitea_and_actions_runner]
}

run "app_repo_sentiment_allows_external_images_without_runner" {
  command = plan

  variables {
    cni_provider                    = "none"
    enable_hubble                   = false
    enable_gitea                    = true
    gitea_admin_pwd                 = "test-admin-password"
    gitea_member_user_pwd           = "test-member-password"
    enable_host_local_registry      = true
    host_local_registry_host        = "host.lima.internal:5002"
    enable_actions_runner           = false
    enable_app_repo_sentiment       = true
    prefer_external_workload_images = true
    external_workload_image_refs = {
      "sentiment-api"     = "host.lima.internal:5002/platform/sentiment-api:latest"
      "sentiment-auth-ui" = "host.lima.internal:5002/platform/sentiment-auth-ui:latest"
    }
  }
}

run "app_repo_subnetcalc_allows_external_images_without_runner" {
  command = plan

  variables {
    cni_provider                      = "none"
    enable_hubble                     = false
    enable_gitea                      = true
    gitea_admin_pwd                   = "test-admin-password"
    gitea_member_user_pwd             = "test-member-password"
    enable_host_local_registry        = true
    host_local_registry_host          = "host.lima.internal:5002"
    enable_actions_runner             = false
    enable_app_repo_subnet_calculator = true
    prefer_external_workload_images   = true
    external_workload_image_refs = {
      "subnetcalc-api-fastapi-container-app" = "host.lima.internal:5002/platform/subnetcalc-api-fastapi-container-app:latest"
      "subnetcalc-apim-simulator"            = "host.lima.internal:5002/platform/subnetcalc-apim-simulator:latest"
      "subnetcalc-frontend-react"            = "host.lima.internal:5002/platform/subnetcalc-frontend-react:latest"
    }
  }
}
