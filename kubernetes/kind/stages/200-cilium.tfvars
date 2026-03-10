# Stage 200 - Install Cilium (no Hubble UI)

cluster_name         = "kind-local"
kubeconfig_path      = "~/.kube/config"
kubeconfig_context   = "kind-kind-local"
kind_config_path     = "./kind-config.yaml"
kind_api_server_port = 6443
worker_count         = 1
node_image           = "kindest/node:v1.35.0"

enable_image_preload       = true
cni_provider               = "cilium"
enable_hubble              = false
enable_argocd              = false
enable_gitea               = false
enable_policies            = false
enable_signoz              = false
enable_observability_agent = false
enable_headlamp            = false
enable_gateway_tls         = false
enable_sso                 = false

enable_apps_dir_mount             = true
enable_docker_socket_mount        = true
docker_socket_path                = "/var/run/docker.sock"
enable_actions_runner             = false
enable_app_repo_sentiment_llm     = false
enable_app_repo_subnet_calculator = false

cilium_version             = "1.19.1"
argocd_chart_version       = "9.4.7"
argocd_namespace           = "argocd"
gitea_admin_username       = "gitea-admin"
gitea_ssh_username         = "git"
gitea_chart_version        = "12.5.0"
signoz_chart_version       = "0.114.1"
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
