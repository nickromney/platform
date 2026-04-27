# Kind platform context: Cilium (+ Hubble) + Argo CD + Gitea + Keycloak SSO

include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

inputs = {
  cluster_name          = "kind-local"
  worker_count          = 1
  node_image            = "kindest/node:v1.35.1"
  kind_api_server_port  = 6443
  kind_config_path      = get_env("TF_VAR_kind_config_path", "${get_original_terragrunt_dir()}/kind-config.yaml")
  kind_stack_dir        = get_env("TF_VAR_kind_stack_dir", get_original_terragrunt_dir())
  kubeconfig_path       = pathexpand("~/.kube/kind-kind-local.yaml")
  kubeconfig_context    = "kind-kind-local"
  platform_devcontainer = get_env("PLATFORM_DEVCONTAINER", "0") == "1"

  argocd_namespace      = "argocd"

  gitea_admin_username  = "gitea-admin"
  gitea_ssh_username    = "git"


  argocd_server_node_port = 30080
  hubble_ui_node_port      = 31235
  gitea_http_node_port     = 30090
  gitea_ssh_node_port      = 30022
  signoz_ui_node_port      = 30301
  signoz_ui_host_port      = 3301
  gateway_https_node_port  = 30070
  gateway_https_host_port  = 443
}
