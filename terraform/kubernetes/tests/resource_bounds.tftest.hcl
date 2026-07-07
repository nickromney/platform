run "metrics_server_enabled" {
  command = plan

  variables {
    cni_provider          = "none"
    enable_hubble         = false
    enable_argocd         = true
    enable_gitea          = true
    enable_sso            = false
    enable_metrics_server = true
  }

  assert {
    condition     = length(kubernetes_namespace_v1.metrics_server) == 1
    error_message = "Expected metrics-server namespace when enable_metrics_server=true"
  }

  assert {
    condition     = length(kubectl_manifest.argocd_app_metrics_server) == 1
    error_message = "Expected metrics-server Argo CD app when enable_metrics_server=true"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_metrics_server[0].yaml_body, "path: ${local.vendored_chart_paths.metrics_server}")
    error_message = "Expected metrics-server Argo CD app to use the vendored chart path"
  }

  assert {
    condition     = strcontains(kubectl_manifest.argocd_app_metrics_server[0].yaml_body, "--kubelet-insecure-tls")
    error_message = "Expected metrics-server to include the kind kubelet insecure TLS argument"
  }
}

run "application_namespace_resource_bounds_enabled" {
  command = plan

  variables {
    cni_provider                     = "none"
    enable_hubble                    = false
    enable_argocd                    = true
    enable_gitea                     = false
    enable_sso                       = false
    enable_app_repo_sentiment        = true
    enable_namespace_resource_bounds = true
  }

  assert {
    condition = (
      length(kubernetes_limit_range_v1.dev_application_defaults) == 1 &&
      length(kubernetes_resource_quota_v1.dev_application_quota) == 1 &&
      length(kubernetes_limit_range_v1.sit_application_defaults) == 1 &&
      length(kubernetes_resource_quota_v1.sit_application_quota) == 1 &&
      length(kubernetes_limit_range_v1.uat_application_defaults) == 1 &&
      length(kubernetes_resource_quota_v1.uat_application_quota) == 1
    )
    error_message = "Expected dev/sit/uat namespace resource bounds when the flag is enabled and namespaces exist"
  }

  assert {
    condition = (
      kubernetes_limit_range_v1.dev_application_defaults[0].spec[0].limit[0].default_request.memory == "64Mi" &&
      kubernetes_limit_range_v1.dev_application_defaults[0].spec[0].limit[0].default.memory == "256Mi"
    )
    error_message = "Expected application LimitRange to set default memory request and limit"
  }

  assert {
    condition = (
      kubernetes_resource_quota_v1.dev_application_quota[0].spec[0].hard["requests.memory"] == "6Gi" &&
      kubernetes_resource_quota_v1.dev_application_quota[0].spec[0].hard["limits.memory"] == "12Gi"
    )
    error_message = "Expected application ResourceQuota memory bounds"
  }
}
