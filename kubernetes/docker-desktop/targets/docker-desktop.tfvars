# Existing-cluster profile for the Docker Desktop managed environment.

provision_kind_cluster        = false
enable_image_preload          = false
preload_image_list_path       = "../../kubernetes/docker-desktop/preload-images.txt"
enable_apps_dir_mount         = false
enable_docker_socket_mount    = false
enable_actions_runner         = false
enable_cilium_wireguard       = false
enable_cilium_node_encryption = false
gitea_local_access_mode       = "port-forward"

argocd_image_repository = "quay.io/argoproj/argocd"
argocd_image_tag        = "v3.3.6"

hardened_image_registry         = "dhi.io"
prefer_external_workload_images = true

external_workload_image_refs = {
  sentiment-api                        = "host.docker.internal:5002/platform/sentiment-api:latest"
  sentiment-auth-ui                    = "host.docker.internal:5002/platform/sentiment-auth-ui:latest"
  subnetcalc-api-fastapi-container-app = "host.docker.internal:5002/platform/subnetcalc-api-fastapi-container-app:latest"
  subnetcalc-apim-simulator            = "host.docker.internal:5002/platform/subnetcalc-apim-simulator:latest"
  subnetcalc-frontend-react            = "host.docker.internal:5002/platform/subnetcalc-frontend-react:latest"
  subnetcalc-frontend-typescript-vite  = "host.docker.internal:5002/platform/subnetcalc-frontend-typescript-vite:latest"
}
