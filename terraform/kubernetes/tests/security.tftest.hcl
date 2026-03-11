run "wireguard_enabled" {
  command = plan

  variables {
    cni_provider            = "cilium"
    enable_cilium_wireguard = true
    enable_hubble           = false
    enable_argocd           = false
    enable_gitea            = false
    enable_signoz           = false
  }

  assert {
    condition     = length(helm_release.cilium) == 1
    error_message = "Expected helm_release.cilium to exist when enable_cilium_wireguard=true"
  }

  assert {
    condition     = length(regexall("\"enabled\":true", jsonencode(yamldecode(helm_release.cilium[0].values[0])))) > 0
    error_message = "Expected Cilium Helm values to contain encryption.enabled=true"
  }

  assert {
    condition     = length(regexall("\"type\":\"wireguard\"", jsonencode(yamldecode(helm_release.cilium[0].values[0])))) > 0
    error_message = "Expected Cilium Helm values to contain encryption.type=wireguard"
  }
}

run "wireguard_disabled_by_default" {
  command = plan

  variables {
    cni_provider  = "cilium"
    enable_hubble = false
    enable_argocd = false
    enable_gitea  = false
    enable_signoz = false
  }

  assert {
    condition     = length(helm_release.cilium) == 1
    error_message = "Expected helm_release.cilium to exist"
  }

  assert {
    condition     = length(regexall("\"encryption\"", jsonencode(yamldecode(helm_release.cilium[0].values[0])))) == 0
    error_message = "Expected Cilium Helm values to NOT contain encryption block when wireguard is disabled"
  }
}

run "wireguard_requires_cilium" {
  command = plan

  variables {
    cni_provider            = "none"
    enable_hubble           = false
    enable_cilium_wireguard = true
    enable_argocd           = false
  }

  expect_failures = [check.enable_cilium_wireguard_requires_cilium_provider]
}

run "node_encryption_requires_wireguard" {
  command = plan

  variables {
    cni_provider                  = "cilium"
    enable_hubble                 = false
    enable_cilium_wireguard       = false
    enable_cilium_node_encryption = true
    enable_argocd                 = false
  }

  expect_failures = [check.enable_cilium_node_encryption_requires_wireguard]
}

run "uat_namespace_has_isolate_label" {
  command = plan

  variables {
    cni_provider                  = "cilium"
    enable_hubble                 = true
    enable_argocd                 = true
    enable_gitea                  = true
    enable_policies               = true
    enable_actions_runner         = true
    enable_app_repo_sentiment_llm = true
    enable_signoz                 = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.uat) == 1
    error_message = "Expected kubernetes_namespace_v1.uat to exist"
  }

  assert {
    condition     = kubernetes_namespace_v1.uat[0].metadata[0].labels["kyverno.io/isolate"] == "true"
    error_message = "Expected uat namespace to have kyverno.io/isolate=true label"
  }

  assert {
    condition     = kubernetes_namespace_v1.uat[0].metadata[0].labels["security-tier"] == "strict"
    error_message = "Expected uat namespace to have security-tier=strict label"
  }
}

run "dev_namespace_has_isolate_label" {
  command = plan

  variables {
    cni_provider                  = "cilium"
    enable_hubble                 = true
    enable_argocd                 = true
    enable_gitea                  = true
    enable_policies               = true
    enable_actions_runner         = true
    enable_app_repo_sentiment_llm = true
    enable_signoz                 = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.dev) == 1
    error_message = "Expected kubernetes_namespace_v1.dev to exist"
  }

  assert {
    condition     = kubernetes_namespace_v1.dev[0].metadata[0].labels["kyverno.io/isolate"] == "true"
    error_message = "Expected dev namespace to have kyverno.io/isolate=true label"
  }
}

run "sso_namespace_has_security_labels" {
  command = plan

  variables {
    cni_provider       = "cilium"
    enable_hubble      = true
    enable_argocd      = true
    enable_gitea       = true
    enable_gateway_tls = true
    enable_sso         = true
    enable_signoz      = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.sso) == 1
    error_message = "Expected kubernetes_namespace_v1.sso to exist"
  }

  assert {
    condition     = kubernetes_namespace_v1.sso[0].metadata[0].labels["kyverno.io/isolate"] == "true"
    error_message = "Expected sso namespace to have kyverno.io/isolate=true label"
  }

  assert {
    condition     = kubernetes_namespace_v1.sso[0].metadata[0].labels["security-tier"] == "critical"
    error_message = "Expected sso namespace to have security-tier=critical label"
  }
}
