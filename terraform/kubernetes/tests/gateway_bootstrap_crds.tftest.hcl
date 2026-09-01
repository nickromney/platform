# The gateway bootstrap applies the Gateway API bundle and then waits for each
# name in gateway_bootstrap_crd_names via `kubectl get crd`. The upstream bundle
# is not all CRDs: since v1.5 it also ships a ValidatingAdmissionPolicy and its
# Binding, both named safe-upgrades.gateway.networking.k8s.io. Feeding those
# names to a CRD wait costs the wait its full timeout on every apply -- observed
# as a 17-minute stall -- while looking like a slow cluster rather than a bug.

variables {
  cni_provider  = "cilium"
  enable_hubble = false

  # enable_gateway_tls_requires_argocd_and_gitea rejects the gateway without
  # these, and this file exercises the gateway bootstrap, so they cannot be
  # switched off to keep the plan small.
  enable_argocd         = true
  enable_gitea          = true
  gitea_admin_pwd       = "test-admin-password"
  gitea_member_user_pwd = "test-member-password"
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

  # The experimental channel ships three CRDs in the gateway.networking.x-k8s.io
  # group. They are real CRDs and must still be waited for, so this guards the
  # opposite failure from the one above: a filter tightened until it drops them.
  # An earlier version of this assertion checked endswith(name, ".k8s.io"), which
  # was both wrong -- ".x-k8s.io" does not match it -- and weak, since the
  # safe-upgrades policy name would have satisfied it.
  assert {
    condition = alltrue([
      for name in [
        "xbackends.gateway.networking.x-k8s.io",
        "xbackendtrafficpolicies.gateway.networking.x-k8s.io",
        "xmeshes.gateway.networking.x-k8s.io",
      ] : contains(local.gateway_bootstrap_crd_names, name)
    ])
    error_message = "Expected the experimental x-k8s.io CRDs to remain in the wait list"
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
