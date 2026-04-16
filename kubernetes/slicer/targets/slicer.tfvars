# Existing-cluster profile for the Slicer-backed k3s environment.

provision_kind_cluster        = false
enable_image_preload          = false
preload_image_list_path       = "../../kubernetes/slicer/preload-images.txt"
runtime_artifact_scope        = "slicer"
enable_apps_dir_mount         = false
enable_docker_socket_mount    = false
enable_actions_runner         = false
enable_cilium_wireguard       = false
enable_cilium_node_encryption = false
gitea_local_access_mode       = "port-forward"
gateway_https_host_port       = 443

hardened_image_registry         = "dhi.io"
prefer_external_platform_images = true
prefer_external_workload_images = true

external_platform_image_refs = {
  grafana = "192.168.64.1:5002/platform/grafana-victorialogs:latest"
}

external_workload_image_refs = {
  sentiment-api                        = "192.168.64.1:5002/platform/sentiment-api:latest"
  sentiment-auth-ui                    = "192.168.64.1:5002/platform/sentiment-auth-ui:latest"
  subnetcalc-api-fastapi-container-app = "192.168.64.1:5002/platform/subnetcalc-api-fastapi-container-app:latest"
  subnetcalc-apim-simulator            = "192.168.64.1:5002/platform/subnetcalc-apim-simulator:latest"
  subnetcalc-frontend-react            = "192.168.64.1:5002/platform/subnetcalc-frontend-react:latest"
  subnetcalc-frontend-typescript-vite  = "192.168.64.1:5002/platform/subnetcalc-frontend-typescript-vite:latest"
}
