# Stage 800 - Add observability, Headlamp, and HTTPS platform routes

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
enable_prometheus             = true
enable_grafana                = true
enable_loki                   = true
enable_tempo                  = false
enable_signoz                 = false
enable_observability_agent    = false
enable_headlamp               = true
enable_gateway_tls            = true
enable_cert_manager           = true
enable_sso                    = false

enable_apps_dir_mount             = false
enable_docker_socket_mount        = false
enable_actions_runner             = false
enable_app_repo_subnet_calculator = true
enable_app_repo_sentiment         = true
prefer_external_workload_images   = true
llm_gateway_mode                  = "disabled"
llm_gateway_external_name         = "host.lima.internal"

cilium_version             = "1.19.1"
argocd_chart_version       = "9.4.7"
argocd_namespace           = "argocd"
gitea_admin_username       = "gitea-admin"
gitea_ssh_username         = "git"
gitea_repo_owner           = "platform"
gitea_repo_owner_is_org    = true
gitea_org_full_name        = "Platform"
gitea_org_visibility       = "private"
gitea_chart_version        = "12.5.0"
signoz_chart_version       = "0.114.1"
headlamp_chart_version     = "0.40.0"
kyverno_chart_version      = "3.7.1"
cert_manager_chart_version = "v1.19.4"

argocd_server_node_port = 30080
hubble_ui_node_port     = 31235
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022
signoz_ui_node_port     = 30301
signoz_ui_host_port     = 3301
gateway_https_node_port = 30070
gateway_https_host_port = 443
