# Stage 700 - Deploy app workloads from local images via the policies repo

cluster_name       = "limavm-k3s"
kubeconfig_path    = "~/.kube/limavm-k3s.yaml"
kubeconfig_context = "limavm-k3s"

enable_image_preload          = false
cni_provider                  = "cilium"
enable_cilium_wireguard       = false
enable_cilium_node_encryption = false
enable_hubble                 = true
enable_argocd                 = true
enable_gitea                  = true
enable_policies               = true
enable_signoz                 = false
enable_observability_agent    = false
enable_headlamp               = false
enable_gateway_tls            = false
enable_cert_manager           = true
enable_sso                    = false

enable_apps_dir_mount           = false
enable_docker_socket_mount      = false
enable_actions_runner           = false
enable_app_repo_subnetcalc      = true
enable_app_repo_sentiment       = true
prefer_external_workload_images = true

argocd_namespace        = "argocd"
gitea_admin_username    = "gitea-admin"
gitea_ssh_username      = "git"
gitea_repo_owner        = "platform"
gitea_repo_owner_is_org = true
gitea_org_full_name     = "Platform"
gitea_org_visibility    = "private"

argocd_server_node_port = 30080
hubble_ui_node_port     = 31235
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022
signoz_ui_node_port     = 30301
signoz_ui_host_port     = 3301
gateway_https_node_port = 30070
gateway_https_host_port = 443
