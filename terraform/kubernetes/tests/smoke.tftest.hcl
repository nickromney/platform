run "smoke_plan" {
  command = plan

  variables {
    cni_provider  = "none"
    enable_hubble = false
    enable_argocd = false
    enable_gitea  = false
    enable_signoz = false
  }

  assert {
    condition     = length(kind_cluster.local) == 1 && kind_cluster.local[0].name == var.cluster_name
    error_message = "Expected exactly one kind cluster and its name to match var.cluster_name"
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
