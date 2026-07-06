# Resource-conscious stage-900 local IDP target for 16GB machines.
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

# Portal API/status surfaces are enabled by enable_sso + enable_argocd through
# apps/idp and the oauth2-proxy IDP Application. Backstage stays off.
enable_app_of_apps = false
enable_backstage   = false

# Keep the GitOps path, but avoid optional Argo CD controllers for this profile.
argocd_applicationset_enabled = false
argocd_notifications_enabled  = false

# Keep one direct sample workload for the IDP catalog/deployment surfaces.
enable_app_repo_sentiment      = false
enable_app_repo_subnetcalc     = true
enable_subnetcalc_apim_gateway = false
enable_apim_simulator          = false
enable_agentgateway_ai_gateway = false
enable_langfuse                = false
enable_langfuse_demos          = false

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
  "idp-core"     = "host.docker.internal:5002/platform/idp-core:0.1.0"
  "platform-mcp" = "host.docker.internal:5002/platform/platform-mcp:0.1.0"
}

external_workload_image_refs = {
  subnetcalc-api      = "host.docker.internal:5002/platform/subnetcalc-api:0.1.0"
  subnetcalc-frontend = "host.docker.internal:5002/platform/subnetcalc-frontend:0.1.0"
}

# Disable heavyweight and optional observability surfaces.
enable_hubble              = false
enable_signoz              = false
enable_prometheus          = false
enable_grafana             = false
enable_loki                = false
enable_victoria_logs       = false
enable_tempo               = false
enable_observability_agent = false
enable_headlamp            = false
