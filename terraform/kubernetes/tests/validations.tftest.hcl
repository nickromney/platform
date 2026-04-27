run "kind_stack_dir_anchors_generated_files" {
  command = plan

  variables {
    provision_kind_cluster = false
    cni_provider           = "none"
    enable_hubble          = false
    enable_argocd          = false
    enable_gitea           = false
    enable_signoz          = false
    kind_stack_dir         = "/tmp/platform-stack"
    kind_config_path       = "/tmp/platform-stack/kind-config.yaml"
  }

  assert {
    condition     = local.stack_dir == "/tmp/platform-stack"
    error_message = "Expected local.stack_dir to follow the explicit kind_stack_dir input"
  }

  assert {
    condition     = local.run_dir == "/tmp/platform-stack/.run"
    error_message = "Expected local.run_dir to stay anchored under local.stack_dir"
  }

  assert {
    condition     = local.kind_config_path_expanded == "/tmp/platform-stack/kind-config.yaml"
    error_message = "Expected kind_config_path to follow the explicit input"
  }
}

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
    cni_provider                    = "none"
    enable_hubble                   = false
    enable_argocd                   = false
    enable_cilium_policy_audit_mode = true
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
    cni_provider               = "none"
    enable_hubble              = false
    enable_gitea               = true
    gitea_admin_pwd            = "test-admin-password"
    gitea_member_user_pwd      = "test-member-password"
    enable_actions_runner      = false
    enable_app_repo_subnetcalc = true
  }

  expect_failures = [check.enable_app_repo_subnetcalc_requires_gitea_and_actions_runner]
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
    cni_provider                    = "none"
    enable_hubble                   = false
    enable_gitea                    = true
    gitea_admin_pwd                 = "test-admin-password"
    gitea_member_user_pwd           = "test-member-password"
    enable_host_local_registry      = true
    host_local_registry_host        = "host.lima.internal:5002"
    enable_actions_runner           = false
    enable_app_repo_subnetcalc      = true
    prefer_external_workload_images = true
    external_workload_image_refs = {
      "subnetcalc-api-fastapi-container-app" = "host.lima.internal:5002/platform/subnetcalc-api-fastapi-container-app:latest"
      "subnetcalc-apim-simulator"            = "host.lima.internal:5002/platform/subnetcalc-apim-simulator:latest"
      "subnetcalc-frontend-typescript-vite"  = "host.lima.internal:5002/platform/subnetcalc-frontend-typescript-vite:latest"
    }
  }
}

run "external_platform_images_accepts_idp_refs" {
  command = plan

  variables {
    cni_provider                    = "none"
    enable_hubble                   = false
    enable_argocd                   = false
    provision_kind_cluster          = true
    enable_host_local_registry      = true
    host_local_registry_host        = "host.docker.internal:5002"
    prefer_external_platform_images = true
    external_platform_image_refs = {
      backstage   = "host.docker.internal:5002/platform/backstage:latest"
      grafana      = "host.docker.internal:5002/platform/grafana-victorialogs:latest"
      "idp-core"   = "host.docker.internal:5002/platform/idp-core:latest"
    }
  }

  assert {
    condition     = local.external_platform_idp_core == "host.docker.internal:5002/platform/idp-core:latest"
    error_message = "Expected idp-core external platform image ref to be accepted and exposed through locals"
  }

  assert {
    condition     = local.external_platform_backstage == "host.docker.internal:5002/platform/backstage:latest"
    error_message = "Expected backstage external platform image ref to be accepted and exposed through locals"
  }
}
