# The gateway bootstrap applies the Gateway API bundle and then waits for each
# name in gateway_bootstrap_crd_names via `kubectl get crd`. The upstream bundle
# is not all CRDs: since v1.5 it also ships a ValidatingAdmissionPolicy and its
# Binding, both named safe-upgrades.gateway.networking.k8s.io. Feeding those
# names to a CRD wait costs the wait its full timeout on every apply -- observed
# as a 17-minute stall -- while looking like a slow cluster rather than a bug.

variables {
  cni_provider  = "cilium"
  enable_hubble = false
  enable_argocd = false
  enable_gitea  = false
}

run "crd_wait_list_excludes_non_crd_documents" {
  command = plan

  variables {
    enable_gateway_tls = true
  }

  # Named explicitly: this is the document that caused the stall, and a future
  # bundle bump must not be able to reintroduce it silently.
  assert {
    condition     = !contains(local.gateway_bootstrap_crd_names, "safe-upgrades.gateway.networking.k8s.io")
    error_message = "The CRD wait list must not include the safe-upgrades ValidatingAdmissionPolicy"
  }

  assert {
    condition = alltrue([
      for name in local.gateway_bootstrap_crd_names : endswith(name, ".k8s.io")
    ])
    error_message = "Expected every waited name to be a CRD name"
  }

  # The bundle's CRDs are still expected to be waited for; the filter must not
  # have emptied the list.
  assert {
    condition     = contains(local.gateway_bootstrap_crd_names, "gatewayclasses.gateway.networking.k8s.io")
    error_message = "Expected the Gateway API CRDs to remain in the wait list"
  }

  assert {
    condition     = contains(local.gateway_bootstrap_crd_names, "tlsroutes.gateway.networking.k8s.io")
    error_message = "Expected tlsroutes, which Cilium requires at v1, to remain in the wait list"
  }
}
