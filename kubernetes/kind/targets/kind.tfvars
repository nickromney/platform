# Backend profile: Kind-managed local cluster

provision_kind_cluster     = true
preload_image_list_path    = "../../kubernetes/kind/preload-images.txt"
gitea_local_access_mode    = "nodeport"
enable_host_local_registry = true

hardened_image_registry         = "dhi.io"
prefer_external_platform_images = true

external_platform_image_refs = {
  grafana = "host.docker.internal:5002/platform/grafana-victorialogs:latest"
}
