run "registry_secret_namespaces_explicit" {
  command = plan

  variables {
    enable_gitea = true

    registry_secret_namespaces = ["team-a", "team-b"]
    gitea_registry_host        = "localhost:30090"
    gitea_admin_username       = "gitea-admin"
    gitea_admin_pwd            = "ChangeMe123!"
  }

  assert {
    condition     = length(kubernetes_secret.gitea_registry_creds) == 2
    error_message = "Expected 2 gitea_registry_creds secrets when registry_secret_namespaces has 2 entries"
  }

  assert {
    condition     = alltrue([for ns, s in kubernetes_secret.gitea_registry_creds : s.metadata[0].namespace == ns && s.metadata[0].name == "gitea-registry-creds"])
    error_message = "Expected each gitea_registry_creds secret to be created in its corresponding namespace"
  }

  assert {
    condition = alltrue([
      for _, s in kubernetes_secret.gitea_registry_creds :
      jsondecode(s.data[".dockerconfigjson"]).auths[var.gitea_registry_host].username == var.gitea_admin_username
    ])
    error_message = "Expected each dockerconfigjson to include auths for gitea_registry_host using gitea_admin_username"
  }
}

run "registry_secret_namespaces_auto_from_app_repos" {
  command = plan

  variables {
    enable_argocd                     = true
    enable_gitea                      = true
    enable_actions_runner             = true
    enable_app_repo_sentiment_llm     = true
    enable_app_repo_subnet_calculator = true

    registry_secret_namespaces = []
  }

  assert {
    condition     = contains(keys(kubernetes_secret.gitea_registry_creds), "dev")
    error_message = "Expected gitea_registry_creds to be created for dev when app repos are enabled"
  }

  assert {
    condition     = contains(keys(kubernetes_secret.gitea_registry_creds), "uat")
    error_message = "Expected gitea_registry_creds to be created for uat when app repos are enabled"
  }

  assert {
    condition     = contains(keys(kubernetes_secret.gitea_registry_creds), "apim")
    error_message = "Expected gitea_registry_creds to be created for apim when subnetcalc repo is enabled"
  }

  assert {
    condition     = length(kubernetes_secret.gitea_registry_creds) == 3
    error_message = "Expected exactly 3 auto-created registry secrets (dev, uat, apim)"
  }
}
