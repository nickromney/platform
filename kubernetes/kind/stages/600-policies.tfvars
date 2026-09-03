# Stage 600 - Deploy Kyverno policies in report mode from the in-cluster Gitea repo

cluster_name         = "kind-local"
kubeconfig_path      = "~/.kube/config"
kubeconfig_context   = "kind-kind-local"
kind_api_server_port = 6443
worker_count                      = 0
cilium_kube_proxy_replacement     = true
cilium_gateway_api                = true
node_image           = "kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed"

enable_image_preload             = true
cni_provider                     = "cilium"
enable_cilium_wireguard          = true
enable_cilium_node_encryption    = false
enable_hubble                    = true
enable_argocd                    = true
enable_gitea                     = true
enable_app_of_apps               = true
enable_policies                  = true
enable_namespace_resource_bounds = true
enable_cilium_policy_audit_mode  = false
enable_observability_agent       = false
enable_headlamp                  = false
enable_gateway_tls               = false
enable_cert_manager              = true
enable_sso                       = false

enable_apps_dir_mount      = true
enable_actions_runner      = false
enable_app_repo_subnetcalc = false
enable_app_repo_sentiment  = false

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
gateway_https_node_port = 30070
gateway_https_host_port = 443
