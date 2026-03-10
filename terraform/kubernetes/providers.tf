provider "kubernetes" {
  config_path    = local.kubeconfig_path_for_providers
  config_context = local.kubeconfig_context_for_providers
}

provider "helm" {
  kubernetes = {
    config_path    = local.kubeconfig_path_for_providers
    config_context = local.kubeconfig_context_for_providers
  }
}

provider "kubectl" {
  apply_retry_count = 15
  config_path       = local.kubeconfig_path_for_providers
  config_context    = local.kubeconfig_context_for_providers
}
