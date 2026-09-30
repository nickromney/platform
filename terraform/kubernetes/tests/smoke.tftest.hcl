run "smoke_plan" {
  command = plan

  variables {
    cni_provider  = "none"
    enable_hubble = false
    enable_argocd = false
    enable_gitea  = false
  }

  assert {
    condition     = length(terraform_data.kind_cluster) == 1 && terraform_data.kind_cluster[0].input.name == var.cluster_name
    error_message = "Expected exactly one kind cluster and its name to match var.cluster_name"
  }

  # `kind create cluster --config` reads the rendered file, so a config change
  # has to replace the cluster rather than leave it running on the old one.
  assert {
    condition     = terraform_data.kind_cluster[0].triggers_replace.kind_config_sha == sha256(local_file.kind_config[0].content)
    error_message = "Expected the kind cluster to be replaced whenever the rendered kind config changes"
  }

  assert {
    condition     = terraform_data.kind_cluster[0].triggers_replace.node_image == var.node_image
    error_message = "Expected the kind cluster to be replaced whenever node_image changes"
  }

  # cni_provider = "none" leaves kind_disable_default_cni unset, so the
  # rendered config has to fall back to kind's default CNI, not hardcode it off.
  assert {
    condition     = strcontains(local_file.kind_config[0].content, "disableDefaultCNI: false")
    error_message = "Expected the rendered kind config to follow local.kind_disable_default_cni"
  }

  assert {
    condition     = length(helm_release.cilium) == 0
    error_message = "Did not expect helm_release.cilium to exist when enable_cilium=false"
  }

  assert {
    condition     = length(helm_release.argocd) == 0
    error_message = "Did not expect helm_release.argocd to exist when enable_argocd=false"
  }
}
