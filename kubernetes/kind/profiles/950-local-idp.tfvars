# Resource-conscious post-900 local IDP target.
#
# This file is layered on top of stages/900-sso.tfvars and targets/kind.tfvars.
# It keeps the cumulative kind stage workflow while trimming optional services.

enable_argocd       = true
enable_gitea        = true
enable_gateway_tls  = true
enable_cert_manager = true
enable_sso          = true
sso_provider        = "keycloak"
enable_argocd_oidc  = true

# IDP portal/API are enabled by enable_sso + enable_argocd through apps/idp and
# the two oauth2-proxy IDP Applications.
enable_app_of_apps = false

# Keep the GitOps path, but avoid optional Argo CD controllers for this profile.
argocd_applicationset_enabled = false
argocd_notifications_enabled  = false

# Keep one sample workload for the IDP catalog/deployment surfaces.
enable_app_repo_sentiment  = true
enable_app_repo_subnetcalc = false

# Use host-built images through the kind host-local registry instead of the
# in-cluster Actions runner and repo mounts.
enable_host_local_registry      = true
host_local_registry_host        = "host.docker.internal:5002"
prefer_external_platform_images = true
prefer_external_workload_images = true
enable_actions_runner           = false
enable_apps_dir_mount           = false
enable_docker_socket_mount      = false

external_platform_image_refs = {
  backstage   = "host.docker.internal:5002/platform/backstage:latest"
  "idp-core"   = "host.docker.internal:5002/platform/idp-core:latest"
}

external_workload_image_refs = {
  sentiment-api     = "host.docker.internal:5002/platform/sentiment-api:latest"
  sentiment-auth-ui = "host.docker.internal:5002/platform/sentiment-auth-ui:latest"
}

# Disable heavyweight and optional observability surfaces.
enable_signoz              = false
enable_prometheus          = false
enable_grafana             = false
enable_loki                = false
enable_victoria_logs       = false
enable_tempo               = false
enable_observability_agent = false
enable_headlamp            = false
