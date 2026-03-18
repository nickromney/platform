# Stage 500 - Re-enable full Argo CD controllers and deploy Gitea

cluster_name         = "kind-local"
kubeconfig_path      = "~/.kube/config"
kubeconfig_context   = "kind-kind-local"
kind_config_path     = "./kind-config.yaml"
kind_api_server_port = 6443
worker_count         = 1
node_image           = "kindest/node:v1.35.0"

enable_image_preload       = true
cni_provider               = "cilium"
enable_hubble              = true
enable_argocd              = true
enable_gitea               = true
enable_policies            = false
enable_signoz              = false
enable_observability_agent = false
enable_headlamp            = false
enable_gateway_tls         = false
enable_sso                 = false

enable_apps_dir_mount             = true
enable_actions_runner             = false
enable_app_repo_sentiment         = false
enable_app_repo_subnet_calculator = false

argocd_namespace        = "argocd"
gitea_admin_username    = "gitea-admin"
gitea_ssh_username      = "git"
gitea_repo_owner        = "platform"
gitea_repo_owner_is_org = true
gitea_org_full_name     = "Platform"
gitea_org_visibility    = "private"

argocd_applicationset_enabled = true
argocd_notifications_enabled  = true

argocd_server_node_port = 30080
hubble_ui_node_port     = 31235
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022
signoz_ui_node_port     = 30301
signoz_ui_host_port     = 3301
gateway_https_node_port = 30070
gateway_https_host_port = 443
