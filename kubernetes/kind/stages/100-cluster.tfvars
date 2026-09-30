# Stage 100 - Create the kind cluster (no addons)
#
# Cilium Gateway and kube-proxy replacement are pinned here because both rewrite
# kind config (host 443 -> container 443, kubeProxyMode=none). Changing them
# later recreates the cluster. NGINX Gateway Fabric is not a kind operator path.

cluster_name         = "kind-local"
kubeconfig_path      = "~/.kube/config"
kubeconfig_context   = "" # Stage 100 creates the cluster, so the context may not exist yet.
kind_api_server_port = 6443
worker_count                      = 0
cilium_kube_proxy_replacement     = true
node_image           = "kindest/node:v1.37.0@sha256:a1ed56cfb0e7b93589bdf97c8cd566405a265939e3620fc4f5de89adff580ae5"

enable_image_preload            = true
cni_provider                    = "none"
kind_disable_default_cni        = true # match cilium stages so cluster is not recreated on upgrade
enable_hubble                   = false
enable_argocd                   = false
enable_gitea                    = false
enable_policies                 = false
enable_cilium_policy_audit_mode = false
enable_observability_agent      = false
enable_headlamp                 = false
enable_gateway_tls              = false
enable_sso                      = false

enable_apps_dir_mount      = true
enable_docker_socket_mount = true
docker_socket_path         = "/var/run/docker.sock"
enable_actions_runner      = false
enable_app_repo_sentiment  = false
enable_app_repo_subnetcalc = false

argocd_namespace     = "argocd"
gitea_admin_username = "gitea-admin"
gitea_ssh_username   = "git"

argocd_server_node_port = 30080
hubble_ui_node_port     = 31235
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022
gateway_https_node_port = 30070
gateway_https_host_port = 443
