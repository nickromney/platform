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
    restart_script_ver = "6"
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
export KUBECONFIG="${local.kubeconfig_path_expanded}"
KNOWN_HOSTS_FILE="${local.gitea_known_hosts_cluster_path}"
mkdir -p "$(dirname "$KNOWN_HOSTS_FILE")"
cat >"$KNOWN_HOSTS_FILE" <<'EOF_KNOWN_HOSTS'
${local.gitea_known_hosts_cluster_content}
EOF_KNOWN_HOSTS
trap 'rm -f "$KNOWN_HOSTS_FILE"' EXIT

# The Kubernetes provider state can drift from the live, Helm-owned ConfigMap.
# Patch the live ConfigMap explicitly from the generated Gitea host key file, then
# restart argocd-repo-server so it re-reads both the mounted ssh_known_hosts
# content and the repository credentials secrets. On a clean cluster, skipping
# the restart because the ConfigMap is already current can leave repo-server
# serving stale SSH trust state for newly created repo secrets.
#
# During Kyverno install/upgrade, the apiserver can temporarily fail admission webhooks with failurePolicy=Fail
# (e.g. "failed calling webhook ... connect: connection refused"). Retry the restart in that case.

retry_webhook_fail() {
  local max=12
  local attempt=0
  local delay=2
  while true; do
    set +e
    out="$("$@" 2>&1)"
    rc=$?
    set -e
    if [ "$rc" -eq 0 ]; then
      echo "$out"
      return 0
    fi
    if echo "$out" | grep -qE 'failed calling webhook|kyverno-svc|kyverno\\.svc-fail|connect: connection refused|no endpoints available for service'; then
      attempt=$((attempt + 1))
      if [ "$attempt" -ge "$max" ]; then
        echo "$out" >&2
        return "$rc"
      fi
      # Avoid Terraform interpolation in this heredoc: escape bash vars as $${var} or use $var.
      echo "WARN webhook not ready; retrying ($attempt/$max) after $${delay}s..." >&2
      sleep "$delay"
      delay=$((delay * 2))
      if [ "$delay" -gt 30 ]; then delay=30; fi
      continue
    fi
    echo "$out" >&2
    return "$rc"
  done
}

wait_for_gitea_ssh() {
  local gitea_ns="gitea"
  local deadline=$((SECONDS + 300))
  local pod_name=""
  local ssh_target_port=""

  if ! kubectl -n "$gitea_ns" get deployment gitea >/dev/null 2>&1; then
    echo "Gitea deployment not found in namespace $gitea_ns" >&2
    return 1
  fi

  kubectl -n "$gitea_ns" rollout status deployment/gitea --timeout=300s

  while (( SECONDS < deadline )); do
    pod_name="$(kubectl -n "$gitea_ns" get pods -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    ssh_target_port="$(kubectl -n "$gitea_ns" get endpoints gitea-ssh -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null || true)"
    if [[ -n "$pod_name" && -n "$ssh_target_port" ]] && kubectl -n "$gitea_ns" exec "$pod_name" -- sh -c '
      ssh_target_port="$1"
      if command -v ss >/dev/null 2>&1; then
        ss -ltn | grep -qE "[[:space:]]:$ssh_target_port[[:space:]]"
      elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep -qE "[.:]$ssh_target_port[[:space:]]"
      else
        exit 1
      fi
    ' sh "$ssh_target_port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "Timed out waiting for Gitea SSH listener to become ready" >&2
  kubectl -n "$gitea_ns" get pods,svc,endpoints gitea gitea-ssh -o wide 2>/dev/null || true
  return 1
}

patch_known_hosts() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  local base_file="$tmpdir/base"
  local base_filtered="$tmpdir/base-filtered"
  local current_hosts="$tmpdir/current-hosts"
  local merged_file="$tmpdir/merged"
  local patch_file="$tmpdir/patch.yaml"
  local patch_out

  kubectl -n ${var.argocd_namespace} get configmap argocd-ssh-known-hosts-cm -o jsonpath='{.data.ssh_known_hosts}' > "$base_file"
  printf '\n' >> "$base_file"

  awk 'NF {print $1}' "$KNOWN_HOSTS_FILE" | LC_ALL=C sort -u > "$current_hosts"
  awk 'NR==FNR {replace[$1]=1; next} NF && !($1 in replace)' "$current_hosts" "$base_file" > "$base_filtered"
  awk 'NF && !seen[$0]++' "$base_filtered" "$KNOWN_HOSTS_FILE" | LC_ALL=C sort -u > "$merged_file"

  {
    echo "data:"
    echo "  ssh_known_hosts: |"
    sed 's/^/    /' "$merged_file"
  } > "$patch_file"

  patch_out="$(retry_webhook_fail kubectl patch configmap argocd-ssh-known-hosts-cm -n ${var.argocd_namespace} --type merge --patch-file "$patch_file")"
  echo "$patch_out"
  rm -rf "$tmpdir"
}

force_delete_stuck_repo_server_pods() {
  local stuck_pods
  stuck_pods="$(
    kubectl -n ${var.argocd_namespace} get pods \
      -l app.kubernetes.io/name=argocd-repo-server \
      -o jsonpath='{range .items[?(@.metadata.deletionTimestamp)]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true
  )"

  if [ -z "$stuck_pods" ]; then
    return 1
  fi

  while IFS= read -r pod; do
    [ -n "$pod" ] || continue
    echo "WARN force deleting stuck repo-server pod: $pod" >&2
    kubectl -n ${var.argocd_namespace} delete pod "$pod" --force --grace-period=0 >/dev/null 2>&1 || true
  done <<< "$stuck_pods"

  return 0
}

if kubectl -n ${var.argocd_namespace} get deployment argocd-repo-server >/dev/null 2>&1; then
  wait_for_gitea_ssh
  patch_known_hosts
  retry_webhook_fail kubectl rollout restart deployment argocd-repo-server -n ${var.argocd_namespace}
  if ! retry_webhook_fail kubectl rollout status deployment argocd-repo-server -n ${var.argocd_namespace} --timeout=180s; then
    if force_delete_stuck_repo_server_pods; then
      retry_webhook_fail kubectl rollout status deployment argocd-repo-server -n ${var.argocd_namespace} --timeout=180s
    else
      exit 1
    fi
  fi
else
  echo "WARN argocd-repo-server deployment not found in namespace ${var.argocd_namespace}; skipping restart" >&2
fi
EOT
    interpreter = ["/bin/bash", "-c"]
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
    refresh_script_ver = "10"
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
export KUBECONFIG="${local.kubeconfig_path_expanded}"
ARGOCD_NS="${var.argocd_namespace}"
APP_NAMES="${join(",", local.argocd_gitops_repo_app_names)}"

if [[ -z "$APP_NAMES" ]]; then
  exit 0
fi

if ! kubectl -n "$ARGOCD_NS" get deployment argocd-repo-server >/dev/null 2>&1; then
  echo "WARN argocd-repo-server deployment not found in namespace $ARGOCD_NS; skipping refresh" >&2
  exit 0
fi

kubectl -n "$ARGOCD_NS" rollout status deployment argocd-repo-server --timeout=180s >/dev/null 2>&1 || true
if kubectl -n "$ARGOCD_NS" get statefulset argocd-application-controller >/dev/null 2>&1; then
  kubectl -n "$ARGOCD_NS" rollout status statefulset argocd-application-controller --timeout=180s >/dev/null 2>&1 || true
fi

wait_for_gitea_ssh() {
  local gitea_ns="gitea"
  local deadline=$((SECONDS + 240))
  local pod_name=""
  local ssh_target_port=""

  if ! kubectl -n "$gitea_ns" get deployment gitea >/dev/null 2>&1; then
    return 0
  fi

  kubectl -n "$gitea_ns" rollout status deployment/gitea --timeout=240s >/dev/null 2>&1 || true

  while (( SECONDS < deadline )); do
    pod_name="$(kubectl -n "$gitea_ns" get pods -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    ssh_target_port="$(kubectl -n "$gitea_ns" get endpoints gitea-ssh -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null || true)"
    if [[ -n "$pod_name" && -n "$ssh_target_port" ]] && kubectl -n "$gitea_ns" exec "$pod_name" -- sh -c '
      ssh_target_port="$1"
      if command -v ss >/dev/null 2>&1; then
        ss -ltn | grep -qE "[[:space:]]:$${ssh_target_port}[[:space:]]"
      elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep -qE "[.:]$${ssh_target_port}[[:space:]]"
      else
        exit 1
      fi
    ' sh "$ssh_target_port" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  echo "WARN gitea SSH listener did not become ready before Argo refresh" >&2
  return 0
}

wait_for_gitea_ssh

app_list="$(printf '%s' "$APP_NAMES" | tr ',' '\n')"

refresh_app() {
  local app="$1"
  kubectl -n "$ARGOCD_NS" annotate app "$app" argocd.argoproj.io/refresh=hard --overwrite >/dev/null 2>&1 || true
}

get_resource_jsonpath() {
  local resource_kind="$1"
  local resource_namespace="$2"
  local resource_name="$3"
  local jsonpath_expr="$4"

  if [[ -n "$resource_namespace" ]]; then
    kubectl -n "$resource_namespace" get "$resource_kind" "$resource_name" -o "jsonpath=$jsonpath_expr" 2>/dev/null || true
  else
    kubectl get "$resource_kind" "$resource_name" -o "jsonpath=$jsonpath_expr" 2>/dev/null || true
  fi
}

managed_workloads_ready() {
  local app="$1"
  local workloads=""
  local found_workload=0

  workloads="$(kubectl -n "$ARGOCD_NS" get app "$app" -o json 2>/dev/null | jq -r '
    .status.resources[]?
    | select(.kind == "Deployment" or .kind == "StatefulSet" or .kind == "DaemonSet" or .kind == "Job")
    | [(.kind // ""), (.namespace // ""), (.name // "")]
    | @tsv
  ' 2>/dev/null || true)"

  while IFS=$'\t' read -r workload_kind workload_namespace workload_name; do
    local desired=""
    local ready=""
    local complete=""

    [[ -n "$workload_kind" && -n "$workload_name" ]] || continue
    found_workload=1

    case "$workload_kind" in
      Deployment)
        desired="$(get_resource_jsonpath deployment "$workload_namespace" "$workload_name" '{.spec.replicas}')"
        ready="$(get_resource_jsonpath deployment "$workload_namespace" "$workload_name" '{.status.readyReplicas}')"
        ;;
      StatefulSet)
        desired="$(get_resource_jsonpath statefulset "$workload_namespace" "$workload_name" '{.spec.replicas}')"
        ready="$(get_resource_jsonpath statefulset "$workload_namespace" "$workload_name" '{.status.readyReplicas}')"
        ;;
      DaemonSet)
        desired="$(get_resource_jsonpath daemonset "$workload_namespace" "$workload_name" '{.status.desiredNumberScheduled}')"
        ready="$(get_resource_jsonpath daemonset "$workload_namespace" "$workload_name" '{.status.numberReady}')"
        ;;
      Job)
        complete="$(get_resource_jsonpath job "$workload_namespace" "$workload_name" '{.status.conditions[?(@.type=="Complete")].status}')"
        [[ "$complete" == "True" ]] || return 1
        continue
        ;;
      *)
        continue
        ;;
    esac

    if [[ -z "$desired" ]]; then
      desired="1"
    fi
    if [[ -z "$ready" ]]; then
      ready="0"
    fi

    [[ "$ready" -ge "$desired" ]] || return 1
  done <<< "$workloads"

  [[ "$found_workload" -eq 1 ]]
}

needs_refresh_reason=""
needs_refresh() {
  local app="$1"
  local sync_status
  local health_status
  local comparison_msg

  needs_refresh_reason=""

  sync_status="$(kubectl -n "$ARGOCD_NS" get app "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  health_status="$(kubectl -n "$ARGOCD_NS" get app "$app" -o jsonpath='{.status.health.status}' 2>/dev/null || true)"
  comparison_msg="$(kubectl -n "$ARGOCD_NS" get app "$app" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)"

  if grep -qiE 'knownhosts: key is unknown|failed to list refs: dial tcp .*:22: connect: connection refused|failed to list refs: unexpected EOF' <<<"$comparison_msg"; then
    needs_refresh_reason="comparison=$comparison_msg"
    return 0
  fi

  # Argo can keep the parent Application at Unknown/Degraded/Progressing after
  # the child resources have all become ready. Only treat that as stale cache
  # when the live managed workloads are actually ready; some Argo versions leave
  # child resource sync/health empty while the workloads are still converging.
  if [[ "$sync_status" == "Unknown" && -z "$comparison_msg" ]] && managed_workloads_ready "$app"; then
    needs_refresh_reason="managed-workloads-ready"
    return 0
  fi

  if [[ "$sync_status" == "Synced" && "$health_status" != "Healthy" ]] && managed_workloads_ready "$app"; then
    needs_refresh_reason="managed-workloads-ready"
    return 0
  fi

  if [[ "$sync_status" == "Unknown" ]]; then
    needs_refresh_reason="sync=Unknown"
    return 0
  fi

  return 1
}

while IFS= read -r app; do
  [[ -n "$app" ]] || continue
  if kubectl -n "$ARGOCD_NS" get app "$app" >/dev/null 2>&1; then
    refresh_app "$app"
  fi
done <<< "$app_list"

# Give the controller time to process the initial hard-refresh wave before
# deciding whether any app is still stale.
sleep 15

end=$((SECONDS + 300))
stable_passes=0
soft_only_stable_passes=0
last_pending_summary=""
last_hard_pending_summary=""
last_soft_pending_summary=""
while (( SECONDS < end )); do
  pending=0
  pending_apps=()
  hard_pending_apps=()
  soft_pending_apps=()
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if ! kubectl -n "$ARGOCD_NS" get app "$app" >/dev/null 2>&1; then
      continue
    fi

    if needs_refresh "$app"; then
      pending=1
      pending_apps+=("$app:$needs_refresh_reason")
      if [[ "$needs_refresh_reason" == "managed-workloads-ready" ]]; then
        # Once the initial hard-refresh wave has landed, a Synced app with live
        # workloads ready usually just needs the controller to settle its parent
        # health. Re-refreshing every few seconds can keep the app looking
        # perpetually unsettled. Treat this as a soft wait condition instead.
        soft_pending_apps+=("$app:$needs_refresh_reason")
      else
        refresh_app "$app"
        hard_pending_apps+=("$app:$needs_refresh_reason")
      fi
    fi
  done <<< "$app_list"

  if [[ "$pending" -eq 0 ]]; then
    stable_passes=$((stable_passes + 1))
    soft_only_stable_passes=0
    last_pending_summary=""
    last_hard_pending_summary=""
    last_soft_pending_summary=""
    if [[ "$stable_passes" -ge 2 ]]; then
      exit 0
    fi
  else
    stable_passes=0
    last_pending_summary="$${pending_apps[*]-}"
    last_hard_pending_summary="$${hard_pending_apps[*]-}"
    last_soft_pending_summary="$${soft_pending_apps[*]-}"
    if [[ "$${#hard_pending_apps[@]}" -eq 0 && "$${#soft_pending_apps[@]}" -gt 0 ]]; then
      soft_only_stable_passes=$((soft_only_stable_passes + 1))
      if [[ "$soft_only_stable_passes" -ge 2 ]]; then
        echo "WARN repo-backed Argo CD applications were still waiting on parent health after refresh, but no repo comparison errors remained: $last_soft_pending_summary" >&2
        exit 0
      fi
    else
      soft_only_stable_passes=0
    fi
  fi

  sleep 5
done

if [[ -n "$last_hard_pending_summary" ]]; then
  echo "Repo-backed Argo CD applications still have stale comparison state after refresh: $last_hard_pending_summary" >&2
  exit 1
fi

if [[ -n "$last_soft_pending_summary" ]]; then
  echo "WARN repo-backed Argo CD applications were still waiting on parent health after refresh, but no repo comparison errors remained: $last_soft_pending_summary" >&2
  exit 0
fi

if [[ -n "$last_pending_summary" ]]; then
  echo "Repo-backed Argo CD applications still have stale comparison state after refresh: $last_pending_summary" >&2
else
  echo "Repo-backed Argo CD applications still have stale comparison state after refresh" >&2
fi
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
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
    kubectl_manifest.argocd_app_nginx_gateway_fabric,
    kubectl_manifest.argocd_app_platform_gateway,
    kubectl_manifest.argocd_app_platform_gateway_routes,
    kubectl_manifest.argocd_app_apim,
    kubectl_manifest.argocd_app_dev,
    kubectl_manifest.argocd_app_uat,
    kubectl_manifest.argocd_app_headlamp,
    kubectl_manifest.argocd_app_dex,
    kubectl_manifest.argocd_app_oauth2_proxy_argocd,
    kubectl_manifest.argocd_app_oauth2_proxy_gitea,
    kubectl_manifest.argocd_app_oauth2_proxy_hubble,
    kubectl_manifest.argocd_app_oauth2_proxy_grafana,
    kubectl_manifest.argocd_app_oauth2_proxy_signoz,
    kubectl_manifest.argocd_app_oauth2_proxy_sentiment,
    kubectl_manifest.argocd_app_oauth2_proxy_sentiment_uat,
    kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc,
    kubectl_manifest.argocd_app_oauth2_proxy_subnetcalc_uat,
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
    script_v   = "2"
    # If managed via app-of-apps, re-run when the manifest changes.
    runner_manifest_hash = var.enable_app_of_apps ? filesha256("${local.stack_dir}/apps/argocd-apps/60-gitea-actions-runner.application.yaml") : "n/a"
    # Avoid hard coupling to the Terraform-managed ArgoCD Application when the
    # runner app is managed via app-of-apps.
    runner_app = var.enable_app_of_apps ? "managed-by-app-of-apps" : kubectl_manifest.argocd_app_gitea_actions_runner[0].uid
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail

KUBECONFIG="$${KUBECONFIG:?}"
RUNNER_WAIT_SECONDS="$${RUNNER_WAIT_SECONDS:-600}"
ARGOCD_NAMESPACE="$${ARGOCD_NAMESPACE:-argocd}"

echo "Waiting for Gitea Actions runner deployment to be ready..."

# Wait for namespace
waited=0
while [ "$waited" -lt "$RUNNER_WAIT_SECONDS" ]; do
  if kubectl get ns gitea-runner >/dev/null 2>&1; then
    echo "Namespace gitea-runner exists"
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

if ! kubectl get ns gitea-runner >/dev/null 2>&1; then
  echo "Timed out waiting for namespace gitea-runner" >&2
  echo "ArgoCD app status:" >&2
  kubectl -n "$ARGOCD_NAMESPACE" get applications.argoproj.io gitea-actions-runner -o yaml 2>/dev/null || true
  exit 1
fi

# Wait for deployment
waited=0
while [ "$waited" -lt "$RUNNER_WAIT_SECONDS" ]; do
  if kubectl -n gitea-runner get deploy act-runner >/dev/null 2>&1; then
    echo "Deployment gitea-runner/act-runner exists"
    break
  fi
  sleep 2
  waited=$((waited + 2))
done

if ! kubectl -n gitea-runner get deploy act-runner >/dev/null 2>&1; then
  echo "Timed out waiting for deployment gitea-runner/act-runner" >&2
  echo "ArgoCD app status:" >&2
  kubectl -n "$ARGOCD_NAMESPACE" get applications.argoproj.io gitea-actions-runner -o yaml 2>/dev/null || true
  exit 1
fi

# Wait for rollout
if ! kubectl -n gitea-runner rollout status deploy/act-runner --timeout="$${RUNNER_WAIT_SECONDS}s"; then
  echo "Runner deployment rollout failed" >&2
  kubectl -n gitea-runner get pods -o wide || true
  kubectl -n gitea-runner describe pods -l app.kubernetes.io/name=act-runner || true
  exit 1
fi

echo "Gitea Actions runner is ready"
EOT

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
