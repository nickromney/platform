resource "tls_private_key" "policies_repo" {
  count     = local.enable_gitops_repo ? 1 : 0
  algorithm = "ED25519"
}

resource "local_sensitive_file" "policies_repo_private_key" {
  count                = local.enable_gitops_repo ? 1 : 0
  filename             = local.policies_repo_private_key_path
  content              = tls_private_key.policies_repo[0].private_key_openssh
  file_permission      = "0600"
  directory_permission = "0700"
  depends_on           = [tls_private_key.policies_repo]
}

resource "local_file" "gitops_render_contract" {
  count                = local.enable_gitops_repo ? 1 : 0
  filename             = "${local.run_dir}/gitops-render-contract.json"
  content              = jsonencode(local.policies_repo_render_contract)
  file_permission      = "0644"
  directory_permission = "0700"
}

resource "null_resource" "sync_gitea_policies_repo" {
  count = local.enable_gitops_repo ? 1 : 0

  triggers = {
    repo_render_hash = local.policies_repo_render_hash
    public_key       = tls_private_key.policies_repo[0].public_key_openssh
    script_sha       = filesha256("${local.stack_dir}/scripts/sync-gitea-policies.sh")
    gitea_http       = tostring(var.gitea_http_node_port)
    gitea_ssh        = tostring(var.gitea_ssh_node_port)
    gitea_access     = local.gitea_local_access_mode_effective
    gitea_ns_uid     = kubernetes_namespace_v1.gitea[0].metadata[0].uid
  }

  provisioner "local-exec" {
    command = "bash \"${local.stack_dir}/scripts/sync-gitea-policies.sh\" --execute"
    environment = {
      STACK_DIR                   = local.stack_dir
      GITOPS_RENDER_CONTRACT_FILE = local_file.gitops_render_contract[0].filename
      GITEA_LOCAL_ACCESS_MODE     = local.gitea_local_access_mode_effective
      GITEA_HTTP_NODE_PORT        = tostring(var.gitea_http_node_port)
      GITEA_HTTP_BASE             = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME        = var.gitea_admin_username
      GITEA_ADMIN_PWD             = var.gitea_admin_pwd
      GITEA_SSH_USERNAME          = var.gitea_ssh_username
      GITEA_SSH_NODE_PORT         = tostring(var.gitea_ssh_node_port)
      GITEA_SSH_HOST              = local.gitea_ssh_host_local
      GITEA_SSH_PORT              = tostring(var.gitea_ssh_node_port)
      GITEA_NAMESPACE             = kubernetes_namespace_v1.gitea[0].metadata[0].name
      GITEA_REPO_OWNER            = local.gitea_repo_owner
      GITEA_REPO_OWNER_IS_ORG     = tostring(local.gitea_repo_owner_is_org)
      GITEA_REPO_OWNER_FALLBACK   = local.gitea_repo_owner_fallback
      GITEA_REPO_NAME             = local.policies_repo_name
      DEPLOY_KEY_TITLE            = "argocd-policies-repo-key"
      DEPLOY_PUBLIC_KEY           = tls_private_key.policies_repo[0].public_key_openssh
      SSH_PRIVATE_KEY_PATH        = local.policies_repo_private_key_path
      KUBECONFIG                  = local.kubeconfig_path_expanded
      KUBECONFIG_CONTEXT          = trimspace(var.kubeconfig_context)
    }
  }

  depends_on = [
    null_resource.ensure_kind_kubeconfig,
    kubectl_manifest.argocd_app_gitea,
    null_resource.gitea_org,
    # Workload Applications can reconcile immediately after this repo sync.
    # Keep Terraform-owned namespaces and image pull secrets ahead of that sync
    # so Argo CD does not create those namespaces first.
    kubernetes_secret_v1.gitea_registry_creds,
    kubernetes_secret_v1.backstage_gitea_credentials,
    kubernetes_secret_v1.headlamp_mkcert_ca,
    kubernetes_secret_v1.dev_mkcert_ca,
    local_sensitive_file.policies_repo_private_key,
    local_file.gitops_render_contract,
  ]
}

# -----------------------------------------------------------------------------
# Optional: seed monorepo apps into in-cluster Gitea (for in-cluster pipelines)
# -----------------------------------------------------------------------------

resource "tls_private_key" "app_repo_sentiment" {
  count     = var.enable_app_repo_sentiment && var.enable_actions_runner ? 1 : 0
  algorithm = "ED25519"
}

resource "local_sensitive_file" "app_repo_sentiment_private_key" {
  count                = var.enable_app_repo_sentiment && var.enable_actions_runner ? 1 : 0
  filename             = "${local.run_dir}/app-${local.sentiment_repo_name}.id_ed25519"
  content              = tls_private_key.app_repo_sentiment[0].private_key_openssh
  file_permission      = "0600"
  directory_permission = "0700"
  depends_on           = [tls_private_key.app_repo_sentiment]
}

resource "local_file" "app_repo_sync_contract_sentiment" {
  count                = var.enable_app_repo_sentiment && var.enable_actions_runner ? 1 : 0
  filename             = "${local.run_dir}/app-${local.sentiment_repo_name}-sync-contract.json"
  content              = jsonencode(local.app_repo_sync_contracts.sentiment)
  file_permission      = "0644"
  directory_permission = "0700"
}

resource "null_resource" "sync_gitea_app_repo_sentiment" {
  count = var.enable_app_repo_sentiment && var.enable_actions_runner ? 1 : 0

  triggers = {
    contract_hash   = sha1(jsonencode(local.app_repo_sync_contracts.sentiment))
    public_key      = tls_private_key.app_repo_sentiment[0].public_key_openssh
    script_sha      = filesha256("${local.stack_dir}/scripts/sync-gitea-app-repo.sh")
    sync_script_sha = filesha256("${local.stack_dir}/scripts/sync-gitea-repo.sh")
    gitea_http      = tostring(var.gitea_http_node_port)
    gitea_ssh       = tostring(var.gitea_ssh_node_port)
    gitea_access    = local.gitea_local_access_mode_effective
    gitea_ns_uid    = kubernetes_namespace_v1.gitea[0].metadata[0].uid
  }

  provisioner "local-exec" {
    command = "bash \"${local.stack_dir}/scripts/sync-gitea-app-repo.sh\" --execute"
    environment = {
      STACK_DIR                   = local.stack_dir
      APP_REPO_SYNC_CONTRACT_FILE = local_file.app_repo_sync_contract_sentiment[0].filename
      GITEA_LOCAL_ACCESS_MODE     = local.gitea_local_access_mode_effective
      GITEA_HTTP_NODE_PORT        = tostring(var.gitea_http_node_port)
      GITEA_HTTP_BASE             = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME        = var.gitea_admin_username
      GITEA_ADMIN_PWD             = var.gitea_admin_pwd
      GITEA_SSH_USERNAME          = var.gitea_ssh_username
      GITEA_SSH_NODE_PORT         = tostring(var.gitea_ssh_node_port)
      GITEA_SSH_HOST              = local.gitea_ssh_host_local
      GITEA_SSH_PORT              = tostring(var.gitea_ssh_node_port)
      GITEA_NAMESPACE             = kubernetes_namespace_v1.gitea[0].metadata[0].name
      DEPLOY_PUBLIC_KEY           = tls_private_key.app_repo_sentiment[0].public_key_openssh
      SSH_PRIVATE_KEY_PATH        = local_sensitive_file.app_repo_sentiment_private_key[0].filename
      KUBECONFIG                  = local.kubeconfig_path_expanded
      KUBECONFIG_CONTEXT          = trimspace(var.kubeconfig_context)
    }
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
    null_resource.gitea_org,
    local_sensitive_file.app_repo_sentiment_private_key,
    local_file.app_repo_sync_contract_sentiment,
    # Ensure the runner is ready before pushing code that triggers workflows.
    null_resource.wait_gitea_actions_runner_ready,
    # Policies repo must be synced first (see sync_gitea_app_repo_subnetcalc).
    null_resource.sync_gitea_policies_repo,
  ]
}

resource "tls_private_key" "app_repo_subnetcalc" {
  count     = var.enable_app_repo_subnetcalc && var.enable_actions_runner ? 1 : 0
  algorithm = "ED25519"
}

resource "local_sensitive_file" "app_repo_subnetcalc_private_key" {
  count                = var.enable_app_repo_subnetcalc && var.enable_actions_runner ? 1 : 0
  filename             = "${local.run_dir}/app-${local.subnetcalc_repo_name}.id_ed25519"
  content              = tls_private_key.app_repo_subnetcalc[0].private_key_openssh
  file_permission      = "0600"
  directory_permission = "0700"
  depends_on           = [tls_private_key.app_repo_subnetcalc]
}

resource "local_file" "app_repo_sync_contract_subnetcalc" {
  count                = var.enable_app_repo_subnetcalc && var.enable_actions_runner ? 1 : 0
  filename             = "${local.run_dir}/app-${local.subnetcalc_repo_name}-sync-contract.json"
  content              = jsonencode(local.app_repo_sync_contracts.subnetcalc)
  file_permission      = "0644"
  directory_permission = "0700"
}

resource "null_resource" "sync_gitea_app_repo_subnetcalc" {
  count = var.enable_app_repo_subnetcalc && var.enable_actions_runner ? 1 : 0

  triggers = {
    contract_hash   = sha1(jsonencode(local.app_repo_sync_contracts.subnetcalc))
    public_key      = tls_private_key.app_repo_subnetcalc[0].public_key_openssh
    script_sha      = filesha256("${local.stack_dir}/scripts/sync-gitea-app-repo.sh")
    sync_script_sha = filesha256("${local.stack_dir}/scripts/sync-gitea-repo.sh")
    gitea_http      = tostring(var.gitea_http_node_port)
    gitea_ssh       = tostring(var.gitea_ssh_node_port)
    gitea_access    = local.gitea_local_access_mode_effective
    gitea_ns_uid    = kubernetes_namespace_v1.gitea[0].metadata[0].uid
  }

  provisioner "local-exec" {
    command = "bash \"${local.stack_dir}/scripts/sync-gitea-app-repo.sh\" --execute"
    environment = {
      STACK_DIR                   = local.stack_dir
      APP_REPO_SYNC_CONTRACT_FILE = local_file.app_repo_sync_contract_subnetcalc[0].filename
      GITEA_LOCAL_ACCESS_MODE     = local.gitea_local_access_mode_effective
      GITEA_HTTP_NODE_PORT        = tostring(var.gitea_http_node_port)
      GITEA_HTTP_BASE             = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME        = var.gitea_admin_username
      GITEA_ADMIN_PWD             = var.gitea_admin_pwd
      GITEA_SSH_USERNAME          = var.gitea_ssh_username
      GITEA_SSH_NODE_PORT         = tostring(var.gitea_ssh_node_port)
      GITEA_SSH_HOST              = local.gitea_ssh_host_local
      GITEA_SSH_PORT              = tostring(var.gitea_ssh_node_port)
      GITEA_NAMESPACE             = kubernetes_namespace_v1.gitea[0].metadata[0].name
      DEPLOY_PUBLIC_KEY           = tls_private_key.app_repo_subnetcalc[0].public_key_openssh
      SSH_PRIVATE_KEY_PATH        = local_sensitive_file.app_repo_subnetcalc_private_key[0].filename
      KUBECONFIG                  = local.kubeconfig_path_expanded
      KUBECONFIG_CONTEXT          = trimspace(var.kubeconfig_context)
    }
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
    null_resource.gitea_org,
    local_sensitive_file.app_repo_subnetcalc_private_key,
    local_file.app_repo_sync_contract_subnetcalc,
    # Ensure the runner is ready before pushing code that triggers workflows.
    # Without this, the workflow triggers before any runner can pick it up.
    null_resource.wait_gitea_actions_runner_ready,
    # Policies repo must be synced BEFORE app repos. The CI workflow stamps
    # the policies repo with image tags after building. If policies sync runs
    # after the CI stamp, it overwrites the tag back to :latest and the
    # wait_subnetcalc_images resource times out.
    null_resource.sync_gitea_policies_repo,
  ]
}

# Reference pattern: wait for app images + policy stamping to complete after a
# full reset. Keep this scoped to the repos that feed live workloads.
resource "local_file" "app_image_readiness_contract_subnetcalc" {
  count                = var.enable_app_repo_subnetcalc && var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0
  filename             = "${local.run_dir}/app-${local.subnetcalc_repo_name}-image-readiness-contract.json"
  content              = jsonencode(local.app_image_readiness_contracts.subnetcalc)
  file_permission      = "0644"
  directory_permission = "0700"
}

resource "null_resource" "wait_subnetcalc_images" {
  count = var.enable_app_repo_subnetcalc && var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0

  triggers = {
    app_repo_sync       = null_resource.sync_gitea_app_repo_subnetcalc[0].id
    contract_hash       = sha1(jsonencode(local.app_image_readiness_contracts.subnetcalc))
    script_sha          = filesha256("${local.stack_dir}/scripts/wait-app-image-readiness.sh")
    registry_host       = var.gitea_registry_host
    registry_scheme     = var.gitea_registry_scheme
    repo_owner          = local.gitea_repo_owner
    registry_repo_owner = local.gitea_repo_owner
  }

  provisioner "local-exec" {
    command = "bash \"${local.stack_dir}/scripts/wait-app-image-readiness.sh\" --execute"
    environment = {
      STACK_DIR                         = local.stack_dir
      APP_IMAGE_READINESS_CONTRACT_FILE = local_file.app_image_readiness_contract_subnetcalc[0].filename
      GITEA_LOCAL_ACCESS_MODE           = local.gitea_local_access_mode_effective
      GITEA_HTTP_NODE_PORT              = tostring(var.gitea_http_node_port)
      GITEA_HTTP_BASE                   = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME              = var.gitea_admin_username
      GITEA_ADMIN_PWD                   = var.gitea_admin_pwd
      GITEA_REPO_OWNER                  = local.gitea_repo_owner
      GITEA_NAMESPACE                   = kubernetes_namespace_v1.gitea[0].metadata[0].name
      REGISTRY_REPO_OWNER               = local.gitea_repo_owner
      REGISTRY_HOST                     = var.gitea_registry_host
      REGISTRY_SCHEME                   = var.gitea_registry_scheme
      REGISTRY_USERNAME                 = var.gitea_admin_username
      REGISTRY_PWD                      = var.gitea_admin_pwd
      KUBECONFIG                        = local.kubeconfig_path_expanded
      KUBECONFIG_CONTEXT                = trimspace(var.kubeconfig_context)
    }
  }

  depends_on = [
    null_resource.sync_gitea_app_repo_subnetcalc,
    kubernetes_secret_v1.gitea_runner,
    local_file.app_image_readiness_contract_subnetcalc,
  ]
}

resource "local_file" "app_image_readiness_contract_sentiment" {
  count                = var.enable_app_repo_sentiment && var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0
  filename             = "${local.run_dir}/app-${local.sentiment_repo_name}-image-readiness-contract.json"
  content              = jsonencode(local.app_image_readiness_contracts.sentiment)
  file_permission      = "0644"
  directory_permission = "0700"
}

resource "null_resource" "wait_sentiment_images" {
  count = var.enable_app_repo_sentiment && var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0

  triggers = {
    app_repo_sync       = null_resource.sync_gitea_app_repo_sentiment[0].id
    contract_hash       = sha1(jsonencode(local.app_image_readiness_contracts.sentiment))
    script_sha          = filesha256("${local.stack_dir}/scripts/wait-app-image-readiness.sh")
    registry_host       = var.gitea_registry_host
    registry_scheme     = var.gitea_registry_scheme
    repo_owner          = local.gitea_repo_owner
    registry_repo_owner = local.gitea_repo_owner
  }

  provisioner "local-exec" {
    command = "bash \"${local.stack_dir}/scripts/wait-app-image-readiness.sh\" --execute"
    environment = {
      STACK_DIR                         = local.stack_dir
      APP_IMAGE_READINESS_CONTRACT_FILE = local_file.app_image_readiness_contract_sentiment[0].filename
      GITEA_LOCAL_ACCESS_MODE           = local.gitea_local_access_mode_effective
      GITEA_HTTP_NODE_PORT              = tostring(var.gitea_http_node_port)
      GITEA_HTTP_BASE                   = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME              = var.gitea_admin_username
      GITEA_ADMIN_PWD                   = var.gitea_admin_pwd
      GITEA_REPO_OWNER                  = local.gitea_repo_owner
      GITEA_NAMESPACE                   = kubernetes_namespace_v1.gitea[0].metadata[0].name
      REGISTRY_REPO_OWNER               = local.gitea_repo_owner
      REGISTRY_HOST                     = var.gitea_registry_host
      REGISTRY_SCHEME                   = var.gitea_registry_scheme
      REGISTRY_USERNAME                 = var.gitea_admin_username
      REGISTRY_PWD                      = var.gitea_admin_pwd
      KUBECONFIG                        = local.kubeconfig_path_expanded
      KUBECONFIG_CONTEXT                = trimspace(var.kubeconfig_context)
    }
  }

  depends_on = [
    null_resource.sync_gitea_app_repo_sentiment,
    kubernetes_secret_v1.gitea_runner,
    local_file.app_image_readiness_contract_sentiment,
  ]
}

# -----------------------------------------------------------------------------
# In-cluster Gitea Actions Runner (optional)
# -----------------------------------------------------------------------------

data "external" "gitea_runner_token" {
  count   = var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0
  program = ["/bin/bash", "${local.stack_dir}/scripts/fetch-gitea-runner-token.sh", "--execute"]

  query = {
    gitea_http_base         = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
    gitea_admin_username    = var.gitea_admin_username
    gitea_admin_pwd         = var.gitea_admin_pwd
    gitea_local_access_mode = local.gitea_local_access_mode_effective
    gitea_http_node_port    = tostring(var.gitea_http_node_port)
    gitea_ssh_node_port     = tostring(var.gitea_ssh_node_port)
    gitea_namespace         = kubernetes_namespace_v1.gitea[0].metadata[0].name
    kubeconfig_path         = local.kubeconfig_path_expanded
    kubeconfig_context      = trimspace(var.kubeconfig_context)
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
    null_resource.sync_gitea_policies_repo,
  ]
}

resource "kubernetes_secret_v1" "gitea_runner" {
  count = var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0

  metadata {
    name      = "act-runner-secret"
    namespace = kubernetes_namespace_v1.gitea_runner[0].metadata[0].name
  }

  data = {
    gitea_url         = "http://gitea-http.gitea.svc.cluster.local:3000"
    runner_token      = trimspace(data.external.gitea_runner_token[0].result.token)
    registry_host     = var.gitea_registry_host
    registry_username = var.gitea_admin_username
    registry_password = var.gitea_admin_pwd
    gitea_http_base   = "http://gitea-http.gitea.svc.cluster.local:3000"
    gitea_repo_owner  = local.gitea_repo_owner
  }

  depends_on = [
    kubernetes_namespace_v1.gitea_runner[0],
    data.external.gitea_runner_token[0],
  ]
}

data "external" "gitea_ssh_public_keys_cluster" {
  count   = local.enable_gitops_repo ? 1 : 0
  program = ["/bin/bash", "${local.stack_dir}/scripts/fetch-gitea-ssh-public-keys.sh", "--execute"]

  query = {
    gitea_namespace    = kubernetes_namespace_v1.gitea[0].metadata[0].name
    kubeconfig_path    = local.kubeconfig_path_expanded
    kubeconfig_context = trimspace(var.kubeconfig_context)
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
    null_resource.ensure_kind_kubeconfig,
    null_resource.sync_gitea_policies_repo,
  ]
}

data "kubernetes_config_map_v1" "argocd_ssh_known_hosts_cm" {
  count = local.enable_gitops_repo ? 1 : 0

  metadata {
    name      = "argocd-ssh-known-hosts-cm"
    namespace = var.argocd_namespace
  }

  depends_on = [
    helm_release.argocd,
  ]
}

locals {
  gitea_ssh_public_key_lines = local.enable_gitops_repo ? compact(split("\n", trimspace(base64decode(data.external.gitea_ssh_public_keys_cluster[0].result.keys_b64)))) : []
  gitea_known_hosts_cluster_hosts = local.enable_gitops_repo ? distinct(compact(concat(
    [local.gitea_ssh_host_cluster],
    [
      for host in [try(data.external.gitea_ssh_public_keys_cluster[0].result.cluster_ip, "")] :
      trimspace(host)
      if trimspace(host) != "" && trimspace(host) != "None"
    ]
  ))) : []
  gitea_known_hosts_cluster_lines = local.enable_gitops_repo ? sort(distinct(flatten([
    for host in local.gitea_known_hosts_cluster_hosts : [
      for key_line in local.gitea_ssh_public_key_lines : [
        "${host} ${trimspace(key_line)}",
        "[${host}]:${local.gitea_ssh_port_cluster} ${trimspace(key_line)}",
      ]
    ]
  ]))) : []
  gitea_known_hosts_cluster_content = local.enable_gitops_repo ? format("%s\n", join("\n", local.gitea_known_hosts_cluster_lines)) : ""
  argocd_ssh_known_hosts_base       = local.enable_gitops_repo ? try(data.kubernetes_config_map_v1.argocd_ssh_known_hosts_cm[0].data["ssh_known_hosts"], "") : ""
  argocd_ssh_known_hosts_gitea_hosts = local.enable_gitops_repo ? distinct([
    for line in compact(split("\n", trimspace(local.gitea_known_hosts_cluster_content))) :
    split(" ", trimspace(line))[0]
  ]) : []
  argocd_ssh_known_hosts_base_filtered = local.enable_gitops_repo ? sort([
    for line in compact(split("\n", trimspace(local.argocd_ssh_known_hosts_base))) :
    line
    if !contains(local.argocd_ssh_known_hosts_gitea_hosts, split(" ", trimspace(line))[0])
  ]) : []
  argocd_ssh_known_hosts_merged_lines = local.enable_gitops_repo ? sort(distinct(concat(
    local.argocd_ssh_known_hosts_base_filtered,
    compact(split("\n", trimspace(local.gitea_known_hosts_cluster_content))),
  ))) : []

  argocd_ssh_known_hosts_merged = local.enable_gitops_repo ? (
    length(local.argocd_ssh_known_hosts_merged_lines) > 0 ?
    format("%s\n", join("\n", local.argocd_ssh_known_hosts_merged_lines)) :
    ""
  ) : ""
  argocd_gitops_repo_trust_hash = local.enable_gitops_repo ? sha1(join("\n", compact([
    local.policies_repo_url_cluster,
    join("\n", local.gitea_known_hosts_cluster_lines),
  ]))) : ""
}

resource "kubernetes_config_map_v1_data" "argocd_ssh_known_hosts_cm" {
  count = local.enable_gitops_repo ? 1 : 0

  metadata {
    name      = "argocd-ssh-known-hosts-cm"
    namespace = var.argocd_namespace
  }

  data = {
    ssh_known_hosts = local.argocd_ssh_known_hosts_merged
  }

  force = true

  depends_on = [
    helm_release.argocd,
    data.kubernetes_config_map_v1.argocd_ssh_known_hosts_cm,
  ]
}

resource "null_resource" "argocd_repo_server_restart" {
  count = local.enable_gitops_repo ? 1 : 0

  triggers = {
    cluster_id       = var.provision_kind_cluster ? kind_cluster.local[0].id : "external:${local.kubeconfig_path_expanded}:${length(trimspace(var.kubeconfig_context)) > 0 ? trimspace(var.kubeconfig_context) : "default"}"
    gitea_host_key   = sha1(local.gitea_known_hosts_cluster_content)
    argocd_chart_ver = var.argocd_chart_version
    known_hosts_hash = local.argocd_gitops_repo_trust_hash
    repo_secret_hash = sha1(join("\n", [
      local.policies_repo_url_cluster,
      tls_private_key.policies_repo[0].private_key_openssh,
      local.gitea_known_hosts_cluster_content,
    ]))
    restart_script_sha = filesha256("${local.stack_dir}/scripts/refresh-argocd-repo-server-known-hosts.sh")
    wait_gitea_ssh_sha = filesha256("${local.stack_dir}/scripts/wait-for-gitea-ssh.sh")
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/refresh-argocd-repo-server-known-hosts.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG                = local.kubeconfig_path_expanded
      KNOWN_HOSTS_CONTENT       = local.gitea_known_hosts_cluster_content
      ARGOCD_NAMESPACE          = var.argocd_namespace
      ROLLOUT_TIMEOUT_SECONDS   = tostring(local.platform_wait_seconds.rollout_default)
      GITEA_SSH_TIMEOUT_SECONDS = tostring(local.platform_wait_seconds.rollout_default)
      WAIT_FOR_GITEA_SSH_MODE   = "strict"
    }
  }

  depends_on = [
    helm_release.argocd,
    kubernetes_config_map_v1_data.argocd_ssh_known_hosts_cm,
    kubernetes_secret_v1.argocd_repo_policies,
    kubernetes_secret_v1.argocd_repo_creds_gitea_ssh,
  ]
}

resource "null_resource" "argocd_refresh_gitops_repo_apps" {
  count = local.enable_gitops_repo ? 1 : 0

  triggers = {
    gitops_repo_hash   = local.policies_repo_render_hash
    known_hosts_hash   = local.argocd_gitops_repo_trust_hash
    gitops_repo_apps   = sha1(join(",", sort(local.argocd_gitops_repo_app_names)))
    refresh_script_sha = filesha256("${local.stack_dir}/scripts/refresh-argocd-gitops-repo-apps.sh")
    wait_gitea_ssh_sha = filesha256("${local.stack_dir}/scripts/wait-for-gitea-ssh.sh")
  }

  provisioner "local-exec" {
    command     = "bash \"${local.stack_dir}/scripts/refresh-argocd-gitops-repo-apps.sh\" --execute"
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG                = local.kubeconfig_path_expanded
      ARGOCD_NS                 = var.argocd_namespace
      APP_NAMES                 = join(",", local.argocd_gitops_repo_app_names)
      ROLLOUT_SHORT_SECONDS     = tostring(local.platform_wait_seconds.rollout_short)
      ROLLOUT_TIMEOUT_SECONDS   = tostring(local.platform_wait_seconds.rollout_default)
      GITEA_SSH_TIMEOUT_SECONDS = tostring(local.platform_wait_seconds.rollout_gitea)
      WAIT_FOR_GITEA_SSH_MODE   = "best-effort"
    }
  }

  depends_on = [
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    null_resource.wait_for_gateway_bootstrap_crds,
    kubectl_manifest.argocd_app_of_apps,
    kubectl_manifest.argocd_app_gitea_actions_runner,
    kubectl_manifest.argocd_app_kyverno,
    kubectl_manifest.argocd_app_kyverno_policies,
    kubectl_manifest.argocd_app_cilium_policies,
    kubectl_manifest.argocd_app_cert_manager_config,
    kubectl_manifest.argocd_app_platform_gateway,
    kubectl_manifest.argocd_app_platform_gateway_routes,
    kubectl_manifest.argocd_app_apim,
    kubectl_manifest.argocd_app_dev,
    kubectl_manifest.argocd_app_uat,
    kubectl_manifest.argocd_app_headlamp,
    kubectl_manifest.argocd_app_oauth2_proxy_admin,
    kubectl_manifest.argocd_app_oauth2_proxy_workload,
  ]
}

resource "kubernetes_secret_v1" "argocd_repo_policies" {
  count = local.enable_gitops_repo ? 1 : 0

  metadata {
    name      = "repo-gitea-policies"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type          = "git"
    url           = local.policies_repo_url_cluster
    sshPrivateKey = tls_private_key.policies_repo[0].private_key_openssh
    sshKnownHosts = local.gitea_known_hosts_cluster_content
    insecure      = "false"
  }

  depends_on = [
    kubernetes_namespace_v1.argocd,
    helm_release.argocd,
    kubernetes_config_map_v1_data.argocd_ssh_known_hosts_cm,
  ]
}

resource "kubernetes_secret_v1" "argocd_repo_creds_gitea_ssh" {
  count = local.enable_gitops_repo ? 1 : 0

  metadata {
    name      = "repo-creds-gitea-ssh"
    namespace = var.argocd_namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }

  data = {
    type          = "git"
    url           = "ssh://${var.gitea_ssh_username}@${local.gitea_ssh_host_cluster}:${local.gitea_ssh_port_cluster}/"
    sshPrivateKey = tls_private_key.policies_repo[0].private_key_openssh
    sshKnownHosts = local.gitea_known_hosts_cluster_content
    insecure      = "false"
  }

  depends_on = [
    kubernetes_namespace_v1.argocd,
    helm_release.argocd,
    kubernetes_config_map_v1_data.argocd_ssh_known_hosts_cm,
  ]
}

resource "kubectl_manifest" "argocd_app_gitea_actions_runner" {
  # When enable_app_of_apps=true, this Argo CD Application is managed via GitOps
  # at apps/argocd-apps/60-gitea-actions-runner.application.yaml.
  count = var.enable_actions_runner && var.enable_gitea && var.enable_argocd && !var.enable_app_of_apps ? 1 : 0

  yaml_body = <<__YAML__
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gitea-actions-runner
  namespace: ${var.argocd_namespace}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    namespace: gitea-runner
    server: https://kubernetes.default.svc
  source:
    repoURL: ${local.policies_repo_url_cluster}
    targetRevision: main
    path: apps/gitea-actions-runner
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=false
__YAML__

  wait              = true
  validate_schema   = false
  force_conflicts   = false
  server_side_apply = false

  depends_on = [
    kubernetes_secret_v1.argocd_repo_policies,
    null_resource.sync_gitea_policies_repo,
    kubernetes_secret_v1.gitea_runner,
  ]
}

# Wait for the Gitea Actions runner to be deployed and ready before pushing
# app repos that would trigger workflows. This prevents race conditions where
# workflows trigger before any runner is available to pick them up.
resource "null_resource" "wait_gitea_actions_runner_ready" {
  count = var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0

  triggers = {
    # Re-run if the cluster identity changes (kind reset/recreate or kubeconfig/context switch).
    cluster_id = var.provision_kind_cluster ? kind_cluster.local[0].id : "external:${local.kubeconfig_path_expanded}:${length(trimspace(var.kubeconfig_context)) > 0 ? trimspace(var.kubeconfig_context) : "default"}"
    script_sha = filesha256("${local.stack_dir}/scripts/wait-for-gitea-actions-runner.sh")
    # If managed via app-of-apps, re-run when the manifest changes.
    runner_manifest_hash = var.enable_app_of_apps ? filesha256("${local.stack_dir}/apps/argocd-apps/60-gitea-actions-runner.application.yaml") : "n/a"
    # Avoid hard coupling to the Terraform-managed ArgoCD Application when the
    # runner app is managed via app-of-apps.
    runner_app = var.enable_app_of_apps ? "managed-by-app-of-apps" : kubectl_manifest.argocd_app_gitea_actions_runner[0].uid
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = "bash \"${local.stack_dir}/scripts/wait-for-gitea-actions-runner.sh\" --execute"
    environment = {
      KUBECONFIG          = local.kubeconfig_path_expanded
      ARGOCD_NAMESPACE    = var.argocd_namespace
      RUNNER_WAIT_SECONDS = "900"
    }
  }

  depends_on = [
    # One of these will exist depending on enable_app_of_apps.
    kubectl_manifest.argocd_app_gitea_actions_runner,
    kubectl_manifest.argocd_app_of_apps,
  ]
}
