# Stage 920 - Add Langfuse on top of the SSO-protected platform

cluster_name         = "kind-local"
kubeconfig_path      = "~/.kube/config"
kubeconfig_context   = "kind-kind-local"
kind_api_server_port = 6443
worker_count         = 1
node_image           = "kindest/node:v1.36.1@sha256:3489c7674813ba5d8b1a9977baea8a6e553784dab7b84759d1014dbd78f7ebd5"

enable_image_preload            = true
cni_provider                    = "cilium"
enable_cilium_wireguard         = true
enable_cilium_node_encryption   = false
enable_hubble                   = true
enable_argocd                   = true
enable_gitea                    = true
enable_policies                 = true
enable_cilium_policies          = true
enable_cilium_policy_audit_mode = false
enable_signoz                   = false
enable_prometheus               = true
enable_alertmanager             = true
enable_grafana                  = true
enable_loki                     = false
enable_victoria_logs            = true
enable_tempo                    = false
enable_observability_agent      = false
enable_headlamp                 = true
enable_gateway_tls              = true
enable_cert_manager             = true
enable_sso                      = true
sso_provider                    = "keycloak"
enable_argocd_oidc              = true
enable_app_of_apps              = true

enable_apps_dir_mount          = true
enable_docker_socket_mount     = true
docker_socket_path             = "/var/run/docker.sock"
enable_actions_runner          = true
enable_apim_simulator          = true
enable_agentgateway_ai_gateway = true
enable_app_repo_subnetcalc     = true
enable_app_repo_sentiment      = true
enable_langfuse                = true
enable_langfuse_demos          = true

argocd_namespace          = "argocd"
gitea_admin_username      = "gitea-admin"
gitea_ssh_username        = "git"
gitea_admin_promote_users = ["demo-admin", "CiQwYTFmMGU3Zi03NWZhLTQwY2MtOTBiYy05ZTg3NmMwOTE5ZGMSBWxvY2Fs"]
gitea_repo_owner          = "platform"
gitea_repo_owner_is_org   = true
gitea_org_full_name       = "Platform"
gitea_org_visibility      = "private"
gitea_org_member_emails   = ["demo@admin.test"]

# SSO components

argocd_server_node_port = 30080
hubble_ui_node_port     = 31235
gitea_http_node_port    = 30090
gitea_ssh_node_port     = 30022
signoz_ui_node_port     = 30301
signoz_ui_host_port     = 3301
gateway_https_node_port = 30070
gateway_https_host_port = 443

# Keep SSO-protected HTTPRoutes.
platform_gateway_routes_path = "apps/platform-gateway-routes-sso"
