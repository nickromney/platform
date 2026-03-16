# Stage 400 - Install Argo CD (core only)
# ApplicationSet and Notifications controllers are intentionally disabled here
# to limit the pod scheduling burst during initial installation.
# Both are re-enabled at stage 500.

cluster_name       = "slicer-k3s"
kubeconfig_path    = "~/.kube/slicer-k3s.yaml"
kubeconfig_context = "slicer-k3s"

enable_image_preload       = false
cni_provider               = "cilium"
enable_hubble              = true
enable_argocd              = true
enable_gitea               = false
enable_policies            = false
enable_signoz              = false
enable_observability_agent = false
enable_headlamp            = false
enable_gateway_tls         = false
enable_sso                 = false

enable_apps_dir_mount             = false
enable_docker_socket_mount        = false
enable_actions_runner             = false
enable_app_repo_sentiment         = false
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

argocd_applicationset_enabled = false
argocd_notifications_enabled  = false

argocd_server_node_port = 30080
hubble_ui_node_port     = 31235
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022
signoz_ui_node_port     = 30301
signoz_ui_host_port     = 3301
gateway_https_node_port = 30070
gateway_https_host_port = 443
