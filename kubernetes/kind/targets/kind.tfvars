# Backend profile: Kind-managed local cluster

provision_kind_cluster     = true
preload_image_list_path    = "../../kubernetes/kind/preload-images.txt"
gitea_local_access_mode    = "nodeport"
runtime_artifact_scope     = "kind"
enable_host_local_registry = true

hardened_image_registry         = "dhi.io"
prefer_external_platform_images = true
keycloak_image = "host.docker.internal:5002/platform/keycloak:26.6.1"

external_platform_image_refs = {
  backstage      = "host.docker.internal:5002/platform/backstage:1.0.0"
  grafana         = "host.docker.internal:5002/platform/grafana-victorialogs:12.3.1-v0.26.3"
  "idp-core"      = "host.docker.internal:5002/platform/idp-core:0.1.0"
  "platform-mcp" = "host.docker.internal:5002/platform/platform-mcp:0.1.0"
  "chatgpt-sim"  = "host.docker.internal:5002/platform/chatgpt-sim:0.1.0"
}
