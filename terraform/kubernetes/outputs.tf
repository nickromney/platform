output "cluster_name" {
  description = "Cluster name."
  value       = var.cluster_name
}

output "kubeconfig_path" {
  description = "Path to kubeconfig used by providers."
  value       = local.kubeconfig_path_expanded
}

output "kubeconfig_context" {
  description = "Kubeconfig context used by providers (empty means default context resolution)."
  value       = var.kubeconfig_context
}

output "kind_config_path" {
  description = "Path to the rendered Kind cluster configuration (null when provision_kind_cluster=false)."
  value       = var.provision_kind_cluster ? local.kind_config_path_expanded : null
}

output "argocd_url" {
  description = "Argo CD UI URL (NodePort)."
  value       = "http://localhost:${var.argocd_server_node_port}"
}

output "hubble_ui_url" {
  description = "Hubble UI URL (NodePort)."
  value       = "http://localhost:${var.hubble_ui_node_port}"
}

output "gitea_url" {
  description = "Gitea UI URL (NodePort)."
  value       = "http://localhost:${var.gitea_http_node_port}"
}

output "gitea_ssh" {
  description = "Gitea SSH endpoint (NodePort)."
  value       = "ssh://${var.gitea_admin_username}@localhost:${var.gitea_ssh_node_port}"
}

output "signoz_url" {
  description = "SigNoz UI URL when the optional SigNoz path is enabled."
  value       = var.enable_signoz ? "http://localhost:${var.signoz_ui_host_port}" : null
}
