# Existing-cluster profile for the Lima-backed k3s environment.

provision_kind_cluster        = false
enable_image_preload          = false
preload_image_list_path       = "../../kubernetes/lima/preload-images.txt"
enable_apps_dir_mount         = false
enable_docker_socket_mount    = false
enable_actions_runner         = false
enable_cilium_wireguard       = false
enable_cilium_node_encryption = false

argocd_image_repository = "quay.io/argoproj/argocd"
argocd_image_tag        = "v3.3.2"

hardened_image_registry       = "dhi.io"
prefer_external_workload_images = true
llm_gateway_mode              = "direct"
llm_gateway_external_name     = "host.lima.internal"
llm_gateway_external_cidr     = "192.168.104.2/32"

external_workload_image_refs = {
  sentiment-api                         = "host.lima.internal:5002/platform/sentiment-api:latest"
  sentiment-auth-ui                     = "host.lima.internal:5002/platform/sentiment-auth-ui:latest"
  subnetcalc-api-fastapi-container-app = "host.lima.internal:5002/platform/subnetcalc-api-fastapi-container-app:latest"
  subnetcalc-apim-simulator            = "host.lima.internal:5002/platform/subnetcalc-apim-simulator:latest"
  subnetcalc-frontend-react            = "host.lima.internal:5002/platform/subnetcalc-frontend-react:latest"
  subnetcalc-frontend-typescript-vite  = "host.lima.internal:5002/platform/subnetcalc-frontend-typescript-vite:latest"
}
