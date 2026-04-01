resource "null_resource" "kind_storage" {
  count = var.provision_kind_cluster && local.enable_cilium_effective ? 1 : 0

  triggers = {
    cluster_id               = kind_cluster.local[0].id
    ensure_script_sha        = filesha256("${path.module}/scripts/ensure-kind-storage.sh")
    local_path_manifest_sha  = filesha256("${path.module}/config/local-path-storage-v0.0.35.yaml")
    standard_manifest_sha    = filesha256("${path.module}/config/kind-standard-storageclass.yaml")
  }

  provisioner "local-exec" {
    command     = "bash \"${path.module}/scripts/ensure-kind-storage.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG                         = local.kubeconfig_path_expanded
      LOCAL_PATH_MANIFEST_PATH           = "${path.module}/config/local-path-storage-v0.0.35.yaml"
      STANDARD_STORAGECLASS_MANIFEST_PATH = "${path.module}/config/kind-standard-storageclass.yaml"
    }
  }

  depends_on = [
    local_sensitive_file.kubeconfig,
    null_resource.kind_restart_containerd_on_registry_config_change,
    helm_release.cilium,
    null_resource.cilium_restart_on_config_change,
  ]
}
