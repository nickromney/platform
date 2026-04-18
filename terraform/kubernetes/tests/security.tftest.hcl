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

run "policy_audit_mode_enabled" {
  command = plan

  variables {
    cni_provider                    = "cilium"
    enable_hubble                   = false
    enable_argocd                   = false
    enable_gitea                    = false
    enable_signoz                   = false
    enable_cilium_policy_audit_mode = true
  }

  assert {
    condition     = length(helm_release.cilium) == 1
    error_message = "Expected helm_release.cilium to exist when enable_cilium_policy_audit_mode=true"
  }

  assert {
    condition     = length(regexall("\"policyAuditMode\":true", jsonencode(yamldecode(helm_release.cilium[0].values[0])))) > 0
    error_message = "Expected Cilium Helm values to contain policyAuditMode=true"
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
    cni_provider              = "cilium"
    enable_hubble             = true
    enable_argocd             = true
    enable_gitea              = true
    enable_policies           = true
    enable_actions_runner     = true
    enable_app_repo_sentiment = true
    enable_signoz             = false
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
    condition     = kubernetes_namespace_v1.uat[0].metadata[0].labels["platform.publiccloudexperiments.net/namespace-role"] == "application"
    error_message = "Expected uat namespace to have platform.publiccloudexperiments.net/namespace-role=application label"
  }

  assert {
    condition     = kubernetes_namespace_v1.uat[0].metadata[0].labels["platform.publiccloudexperiments.net/environment"] == "uat"
    error_message = "Expected uat namespace to have platform.publiccloudexperiments.net/environment=uat label"
  }

  assert {
    condition     = kubernetes_namespace_v1.uat[0].metadata[0].labels["platform.publiccloudexperiments.net/sensitivity"] == "private"
    error_message = "Expected uat namespace to have platform.publiccloudexperiments.net/sensitivity=private label"
  }
}

run "dev_namespace_has_isolate_label" {
  command = plan

  variables {
    cni_provider              = "cilium"
    enable_hubble             = true
    enable_argocd             = true
    enable_gitea              = true
    enable_policies           = true
    enable_actions_runner     = true
    enable_app_repo_sentiment = true
    enable_signoz             = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.dev) == 1
    error_message = "Expected kubernetes_namespace_v1.dev to exist"
  }

  assert {
    condition     = kubernetes_namespace_v1.dev[0].metadata[0].labels["kyverno.io/isolate"] == "true"
    error_message = "Expected dev namespace to have kyverno.io/isolate=true label"
  }

  assert {
    condition     = kubernetes_namespace_v1.dev[0].metadata[0].labels["platform.publiccloudexperiments.net/namespace-role"] == "application"
    error_message = "Expected dev namespace to have platform.publiccloudexperiments.net/namespace-role=application label"
  }

  assert {
    condition     = kubernetes_namespace_v1.dev[0].metadata[0].labels["platform.publiccloudexperiments.net/environment"] == "dev"
    error_message = "Expected dev namespace to have platform.publiccloudexperiments.net/environment=dev label"
  }
}

run "sit_namespace_has_application_defaults" {
  command = plan

  variables {
    cni_provider    = "cilium"
    enable_hubble   = false
    enable_argocd   = true
    enable_gitea    = true
    enable_policies = true
    enable_signoz   = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.sit) == 1
    error_message = "Expected kubernetes_namespace_v1.sit to exist"
  }

  assert {
    condition     = kubernetes_namespace_v1.sit[0].metadata[0].labels["kyverno.io/isolate"] == "true"
    error_message = "Expected sit namespace to have kyverno.io/isolate=true label"
  }

  assert {
    condition     = kubernetes_namespace_v1.sit[0].metadata[0].labels["platform.publiccloudexperiments.net/namespace-role"] == "application"
    error_message = "Expected sit namespace to have platform.publiccloudexperiments.net/namespace-role=application label"
  }

  assert {
    condition     = kubernetes_namespace_v1.sit[0].metadata[0].labels["platform.publiccloudexperiments.net/environment"] == "sit"
    error_message = "Expected sit namespace to have platform.publiccloudexperiments.net/environment=sit label"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.dev) == 0
    error_message = "Expected kubernetes_namespace_v1.dev to be absent when no application repos are enabled"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.uat) == 0
    error_message = "Expected kubernetes_namespace_v1.uat to be absent when no application repos are enabled"
  }

  assert {
    condition     = length(kubernetes_namespace_v1.apim) == 0
    error_message = "Expected kubernetes_namespace_v1.apim to be absent when no subnet calculator app repo is enabled"
  }
}

run "sso_namespace_has_sensitivity_labels" {
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
    condition     = kubernetes_namespace_v1.sso[0].metadata[0].labels["platform.publiccloudexperiments.net/namespace-role"] == "shared"
    error_message = "Expected sso namespace to have platform.publiccloudexperiments.net/namespace-role=shared label"
  }

  assert {
    condition     = kubernetes_namespace_v1.sso[0].metadata[0].labels["platform.publiccloudexperiments.net/sensitivity"] == "restricted"
    error_message = "Expected sso namespace to have platform.publiccloudexperiments.net/sensitivity=restricted label"
  }
}

run "platform_namespaces_have_platform_role" {
  command = plan

  variables {
    cni_provider       = "cilium"
    enable_hubble      = true
    enable_argocd      = true
    enable_gateway_tls = true
    enable_policies    = true
    enable_gitea       = true
    enable_signoz      = false
  }

  assert {
    condition     = length(kubernetes_namespace_v1.argocd) == 1
    error_message = "Expected kubernetes_namespace_v1.argocd to exist"
  }

  assert {
    condition     = kubernetes_namespace_v1.argocd[0].metadata[0].labels["platform.publiccloudexperiments.net/namespace-role"] == "platform"
    error_message = "Expected argocd namespace to have platform.publiccloudexperiments.net/namespace-role=platform label"
  }

  assert {
    condition     = length(kubectl_manifest.namespace_cert_manager) == 1
    error_message = "Expected kubectl_manifest.namespace_cert_manager to exist"
  }

  assert {
    condition     = strcontains(kubectl_manifest.namespace_cert_manager[0].yaml_body, "\"platform.publiccloudexperiments.net/namespace-role\": platform")
    error_message = "Expected cert-manager namespace manifest to set platform.publiccloudexperiments.net/namespace-role=platform"
  }

  assert {
    condition     = length(kubectl_manifest.namespace_kyverno) == 1
    error_message = "Expected kubectl_manifest.namespace_kyverno to exist"
  }

  assert {
    condition     = strcontains(kubectl_manifest.namespace_kyverno[0].yaml_body, "\"platform.publiccloudexperiments.net/namespace-role\": platform")
    error_message = "Expected kyverno namespace manifest to set platform.publiccloudexperiments.net/namespace-role=platform"
  }

  assert {
    condition     = length(kubectl_manifest.namespace_policy_reporter) == 1
    error_message = "Expected kubectl_manifest.namespace_policy_reporter to exist"
  }

  assert {
    condition     = strcontains(kubectl_manifest.namespace_policy_reporter[0].yaml_body, "\"platform.publiccloudexperiments.net/namespace-role\": platform")
    error_message = "Expected policy-reporter namespace manifest to set platform.publiccloudexperiments.net/namespace-role=platform"
  }
}
