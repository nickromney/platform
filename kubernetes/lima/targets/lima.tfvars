# Existing-cluster profile for the Lima-backed k3s environment.

provision_kind_cluster        = false
enable_image_preload          = false
preload_image_list_path       = "../../kubernetes/lima/preload-images.txt"
runtime_artifact_scope        = "lima"
enable_apps_dir_mount         = false
enable_docker_socket_mount    = false
enable_actions_runner         = false
enable_cilium_wireguard       = false
enable_cilium_node_encryption = false
gitea_local_access_mode       = "port-forward"

hardened_image_registry         = "dhi.io"
prefer_external_platform_images = true
prefer_external_workload_images = true
keycloak_image                  = "host.lima.internal:5002/platform/keycloak:26.6.1"

external_platform_image_refs = {
  backstage      = "host.lima.internal:5002/platform/backstage:1.0.0"
  "chatgpt-sim"  = "host.lima.internal:5002/platform/chatgpt-sim:0.1.0"
  grafana        = "host.lima.internal:5002/platform/grafana-victorialogs:12.3.1-v0.26.3"
  "idp-core"     = "host.lima.internal:5002/platform/idp-core:0.1.0"
  "platform-mcp" = "host.lima.internal:5002/platform/platform-mcp:0.1.0"
}

external_workload_image_refs = {
  sentiment-api             = "host.lima.internal:5002/platform/sentiment-api:0.1.0"
  sentiment-auth-ui         = "host.lima.internal:5002/platform/sentiment-auth-ui:0.1.0"
  subnetcalc-api            = "host.lima.internal:5002/platform/subnetcalc-api:1.0.0"
  subnetcalc-apim-simulator = "host.lima.internal:5002/platform/subnetcalc-apim-simulator:0.4.0"
  subnetcalc-frontend-react = "host.lima.internal:5002/platform/subnetcalc-frontend-react:0.0.0"
  subnetcalc-frontend       = "host.lima.internal:5002/platform/subnetcalc-frontend:1.0.0"
}
