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
keycloak_image = "host.lima.internal:5002/platform/keycloak:latest"

external_platform_image_refs = {
  backstage   = "host.lima.internal:5002/platform/backstage:latest"
  grafana      = "host.lima.internal:5002/platform/grafana-victorialogs:latest"
  "idp-core"   = "host.lima.internal:5002/platform/idp-core:latest"
}

external_workload_image_refs = {
  sentiment-api                        = "host.lima.internal:5002/platform/sentiment-api:latest"
  sentiment-auth-ui                    = "host.lima.internal:5002/platform/sentiment-auth-ui:latest"
  subnetcalc-api-fastapi-container-app = "host.lima.internal:5002/platform/subnetcalc-api-fastapi-container-app:latest"
  subnetcalc-apim-simulator            = "host.lima.internal:5002/platform/subnetcalc-apim-simulator:latest"
  platform-mcp                         = "host.lima.internal:5002/platform/platform-mcp:latest"
  subnetcalc-frontend-react            = "host.lima.internal:5002/platform/subnetcalc-frontend-react:latest"
  subnetcalc-frontend-typescript-vite  = "host.lima.internal:5002/platform/subnetcalc-frontend-typescript-vite:latest"
}
