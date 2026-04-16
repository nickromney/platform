run "default_runtime_artifacts_stay_under_stack_dir" {
  command = plan

  variables {
    provision_kind_cluster = false
    cni_provider           = "none"
    enable_hubble          = false
    enable_argocd          = false
    enable_gitea           = false
    enable_signoz          = false
    kind_stack_dir         = abspath(".")
    kind_config_path       = abspath("./kind-config.yaml")
  }

  assert {
    condition     = local.stack_dir == abspath(".")
    error_message = "Expected local.stack_dir to follow the explicit kind_stack_dir input"
  }

  assert {
    condition     = local.run_dir == "${abspath(".")}/.run"
    error_message = "Expected local.run_dir to stay anchored under local.stack_dir"
  }

  assert {
    condition     = local.kind_config_path_expanded == abspath("./kind-config.yaml")
    error_message = "Expected kind_config_path to follow the explicit input"
  }
}

run "runtime_artifact_scope_namespaces_generated_files" {
  command = plan

  variables {
    provision_kind_cluster = false
    cni_provider           = "none"
    enable_hubble          = false
    enable_argocd          = false
    enable_gitea           = false
    enable_signoz          = false
    kind_stack_dir         = abspath(".")
    kind_config_path       = abspath("./kind-config.yaml")
    runtime_artifact_scope = "lima"
  }

  assert {
    condition     = local.run_dir == "${abspath(".")}/.run/lima"
    error_message = "Expected local.run_dir to be namespaced under local.stack_dir when runtime_artifact_scope is set"
  }

  assert {
    condition     = local.containerd_certs_dir == "${abspath(".")}/.run/lima/containerd-certs.d"
    error_message = "Expected local.containerd_certs_dir to follow the namespaced run_dir"
  }

  assert {
    condition     = local.policies_repo_private_key_path == "${abspath(".")}/.run/lima/policies-repo.id_ed25519"
    error_message = "Expected policies repo key path to use the namespaced run_dir"
  }

  assert {
    condition     = local.gitea_known_hosts_cluster_path == "${abspath(".")}/.run/lima/gitea_known_hosts_cluster"
    error_message = "Expected Gitea known-hosts scratch path to use the namespaced run_dir"
  }
}
