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

resource "null_resource" "sync_gitea_policies_repo" {
  count = local.enable_gitops_repo ? 1 : 0

  triggers = {
    repo_render_hash = local.policies_repo_render_hash
    public_key       = tls_private_key.policies_repo[0].public_key_openssh
    script_sha       = filesha256("${path.module}/scripts/sync-gitea-policies.sh")
    gitea_http       = tostring(var.gitea_http_node_port)
    gitea_ssh        = tostring(var.gitea_ssh_node_port)
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/sync-gitea-policies.sh\""
    environment = {
      STACK_DIR                                     = abspath(path.module)
      GITEA_HTTP_BASE                               = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME                          = var.gitea_admin_username
      GITEA_ADMIN_PWD                               = var.gitea_admin_pwd
      GITEA_SSH_USERNAME                            = var.gitea_ssh_username
      GITEA_SSH_HOST                                = local.gitea_ssh_host_local
      GITEA_SSH_PORT                                = tostring(var.gitea_ssh_node_port)
      GITEA_REPO_OWNER                              = local.gitea_repo_owner
      GITEA_REPO_OWNER_IS_ORG                       = tostring(local.gitea_repo_owner_is_org)
      GITEA_REPO_OWNER_FALLBACK                     = local.gitea_repo_owner_fallback
      GITEA_REPO_NAME                               = local.policies_repo_name
      DEPLOY_KEY_TITLE                              = "argocd-policies-repo-key"
      DEPLOY_PUBLIC_KEY                             = tls_private_key.policies_repo[0].public_key_openssh
      SSH_PRIVATE_KEY_PATH                          = local.policies_repo_private_key_path
      ENABLE_POLICIES                               = tostring(var.enable_policies)
      ENABLE_GATEWAY_TLS                            = tostring(var.enable_gateway_tls)
      ENABLE_ACTIONS_RUNNER                         = tostring(var.enable_actions_runner)
      ENABLE_APP_REPO_SENTIMENT                     = tostring(var.enable_app_repo_sentiment_llm)
      ENABLE_APP_REPO_SUBNETCALC                    = tostring(var.enable_app_repo_subnet_calculator)
      ENABLE_PROMETHEUS                             = tostring(var.enable_prometheus)
      ENABLE_GRAFANA                                = tostring(var.enable_grafana)
      ENABLE_LOKI                                   = tostring(var.enable_loki)
      ENABLE_TEMPO                                  = tostring(var.enable_tempo)
      ENABLE_SIGNOZ                                 = tostring(var.enable_signoz)
      ENABLE_OTEL_GATEWAY                           = tostring(var.enable_otel_gateway)
      ENABLE_HEADLAMP                               = tostring(var.enable_headlamp)
      ENABLE_OBSERVABILITY_AGENT                    = tostring(var.enable_observability_agent)
      PREFER_EXTERNAL_WORKLOAD_IMAGES               = tostring(var.prefer_external_workload_images)
      EXTERNAL_IMAGE_SENTIMENT_API                  = lookup(var.external_workload_image_refs, "sentiment-api", "")
      EXTERNAL_IMAGE_SENTIMENT_AUTH_UI              = lookup(var.external_workload_image_refs, "sentiment-auth-ui", "")
      EXTERNAL_IMAGE_SUBNETCALC_API_FASTAPI         = lookup(var.external_workload_image_refs, "subnetcalc-api-fastapi-container-app", "")
      EXTERNAL_IMAGE_SUBNETCALC_APIM_SIMULATOR      = lookup(var.external_workload_image_refs, "subnetcalc-apim-simulator", "")
      EXTERNAL_IMAGE_SUBNETCALC_FRONTEND_REACT      = lookup(var.external_workload_image_refs, "subnetcalc-frontend-react", "")
      EXTERNAL_IMAGE_SUBNETCALC_FRONTEND_TYPESCRIPT = lookup(var.external_workload_image_refs, "subnetcalc-frontend-typescript-vite", "")
      HARDENED_IMAGE_REGISTRY                       = var.hardened_image_registry
      LLM_GATEWAY_MODE                              = var.llm_gateway_mode
      LLM_GATEWAY_EXTERNAL_NAME                     = var.llm_gateway_external_name
      POLICIES_REPO_URL_CLUSTER                     = local.policies_repo_url_cluster
      CERT_MANAGER_CHART_VERSION                    = var.cert_manager_chart_version
      DEX_CHART_VERSION                             = var.dex_chart_version
      GRAFANA_CHART_VERSION                         = var.grafana_chart_version
      HEADLAMP_CHART_VERSION                        = var.headlamp_chart_version
      KYVERNO_CHART_VERSION                         = var.kyverno_chart_version
      LOKI_CHART_VERSION                            = var.loki_chart_version
      OAUTH2_PROXY_CHART_VERSION                    = var.oauth2_proxy_chart_version
      OPENTELEMETRY_COLLECTOR_CHART_VERSION         = var.opentelemetry_collector_chart_version
      POLICY_REPORTER_CHART_VERSION                 = var.policy_reporter_chart_version
      PROMETHEUS_CHART_VERSION                      = var.prometheus_chart_version
      SIGNOZ_CHART_VERSION                          = var.signoz_chart_version
      TEMPO_CHART_VERSION                           = var.tempo_chart_version
      LLAMA_CPP_IMAGE                               = var.llama_cpp_image
      LLAMA_CPP_HF_REPO                             = var.llama_cpp_hf_repo
      LLAMA_CPP_HF_FILE                             = var.llama_cpp_hf_file
      LLAMA_CPP_MODEL_ALIAS                         = var.llama_cpp_model_alias
      LLAMA_CPP_CTX_SIZE                            = tostring(var.llama_cpp_ctx_size)
      LITELLM_UPSTREAM_MODEL                        = var.litellm_upstream_model
      LITELLM_UPSTREAM_API_BASE                     = var.litellm_upstream_api_base
      LITELLM_UPSTREAM_API_KEY                      = nonsensitive(var.litellm_upstream_api_key)
    }
  }

  depends_on = [
    local_sensitive_file.kubeconfig,
    kubectl_manifest.argocd_app_gitea,
    null_resource.gitea_org,
    local_sensitive_file.policies_repo_private_key,
  ]
}

# -----------------------------------------------------------------------------
# Optional: seed monorepo apps into in-cluster Gitea (for in-cluster pipelines)
# -----------------------------------------------------------------------------

resource "tls_private_key" "app_repo_sentiment_llm" {
  count     = var.enable_app_repo_sentiment_llm && var.enable_actions_runner ? 1 : 0
  algorithm = "ED25519"
}

resource "local_sensitive_file" "app_repo_sentiment_llm_private_key" {
  count                = var.enable_app_repo_sentiment_llm && var.enable_actions_runner ? 1 : 0
  filename             = "${local.run_dir}/app-${local.sentiment_llm_repo_name}.id_ed25519"
  content              = tls_private_key.app_repo_sentiment_llm[0].private_key_openssh
  file_permission      = "0600"
  directory_permission = "0700"
  depends_on           = [tls_private_key.app_repo_sentiment_llm]
}

resource "null_resource" "sync_gitea_app_repo_sentiment_llm" {
  count = var.enable_app_repo_sentiment_llm && var.enable_actions_runner ? 1 : 0

  triggers = {
    content_hash = local.sentiment_llm_content_hash
    public_key   = tls_private_key.app_repo_sentiment_llm[0].public_key_openssh
    script_sha   = filesha256("${path.module}/scripts/sync-gitea-repo.sh")
    gitea_http   = tostring(var.gitea_http_node_port)
    gitea_ssh    = tostring(var.gitea_ssh_node_port)
    repo_owner   = local.gitea_repo_owner
    repo_is_org  = tostring(local.gitea_repo_owner_is_org)
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/sync-gitea-repo.sh\""
    environment = {
      STACK_DIR                 = abspath(path.module)
      SOURCE_DIR                = local.sentiment_llm_source_dir
      GITEA_HTTP_BASE           = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME      = var.gitea_admin_username
      GITEA_ADMIN_PWD           = var.gitea_admin_pwd
      GITEA_SSH_USERNAME        = var.gitea_ssh_username
      GITEA_SSH_HOST            = local.gitea_ssh_host_local
      GITEA_SSH_PORT            = tostring(var.gitea_ssh_node_port)
      GITEA_REPO_OWNER          = local.gitea_repo_owner
      GITEA_REPO_OWNER_IS_ORG   = tostring(local.gitea_repo_owner_is_org)
      GITEA_REPO_OWNER_FALLBACK = local.gitea_repo_owner_fallback
      GITEA_REPO_NAME           = local.sentiment_llm_repo_name
      DEPLOY_KEY_TITLE          = "ci-${local.sentiment_llm_repo_name}-key"
      DEPLOY_PUBLIC_KEY         = tls_private_key.app_repo_sentiment_llm[0].public_key_openssh
      SSH_PRIVATE_KEY_PATH      = local_sensitive_file.app_repo_sentiment_llm_private_key[0].filename
    }
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
    null_resource.gitea_org,
    local_sensitive_file.app_repo_sentiment_llm_private_key,
    # Ensure the runner is ready before pushing code that triggers workflows.
    null_resource.wait_gitea_actions_runner_ready,
    # Policies repo must be synced first (see sync_gitea_app_repo_subnet_calculator).
    null_resource.sync_gitea_policies_repo,
  ]
}

resource "tls_private_key" "app_repo_subnet_calculator" {
  count     = var.enable_app_repo_subnet_calculator && var.enable_actions_runner ? 1 : 0
  algorithm = "ED25519"
}

resource "local_sensitive_file" "app_repo_subnet_calculator_private_key" {
  count                = var.enable_app_repo_subnet_calculator && var.enable_actions_runner ? 1 : 0
  filename             = "${local.run_dir}/app-${local.subnet_calculator_repo_name}.id_ed25519"
  content              = tls_private_key.app_repo_subnet_calculator[0].private_key_openssh
  file_permission      = "0600"
  directory_permission = "0700"
  depends_on           = [tls_private_key.app_repo_subnet_calculator]
}

resource "null_resource" "sync_gitea_app_repo_subnet_calculator" {
  count = var.enable_app_repo_subnet_calculator && var.enable_actions_runner ? 1 : 0

  triggers = {
    content_hash = local.subnet_calculator_content_hash
    public_key   = tls_private_key.app_repo_subnet_calculator[0].public_key_openssh
    script_sha   = filesha256("${path.module}/scripts/sync-gitea-repo.sh")
    gitea_http   = tostring(var.gitea_http_node_port)
    gitea_ssh    = tostring(var.gitea_ssh_node_port)
    repo_owner   = local.gitea_repo_owner
    repo_is_org  = tostring(local.gitea_repo_owner_is_org)
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/scripts/sync-gitea-repo.sh\""
    environment = {
      STACK_DIR                 = abspath(path.module)
      SOURCE_DIR                = local.subnet_calculator_source_dir
      GITEA_HTTP_BASE           = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME      = var.gitea_admin_username
      GITEA_ADMIN_PWD           = var.gitea_admin_pwd
      GITEA_SSH_USERNAME        = var.gitea_ssh_username
      GITEA_SSH_HOST            = local.gitea_ssh_host_local
      GITEA_SSH_PORT            = tostring(var.gitea_ssh_node_port)
      GITEA_REPO_OWNER          = local.gitea_repo_owner
      GITEA_REPO_OWNER_IS_ORG   = tostring(local.gitea_repo_owner_is_org)
      GITEA_REPO_OWNER_FALLBACK = local.gitea_repo_owner_fallback
      GITEA_REPO_NAME           = local.subnet_calculator_repo_name
      DEPLOY_KEY_TITLE          = "ci-${local.subnet_calculator_repo_name}-key"
      DEPLOY_PUBLIC_KEY         = tls_private_key.app_repo_subnet_calculator[0].public_key_openssh
      SSH_PRIVATE_KEY_PATH      = local_sensitive_file.app_repo_subnet_calculator_private_key[0].filename
    }
  }

  depends_on = [
    kubectl_manifest.argocd_app_gitea,
    null_resource.gitea_org,
    local_sensitive_file.app_repo_subnet_calculator_private_key,
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

# Reference pattern: wait for a single app's images + policy stamping to complete
# after a full reset. Keep this scoped to subnetcalc to avoid boiling the ocean;
# replicate for other apps only when needed.
resource "null_resource" "wait_subnetcalc_images" {
  count = var.enable_app_repo_subnet_calculator && var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0

  triggers = {
    app_repo_sync       = null_resource.sync_gitea_app_repo_subnet_calculator[0].id
    registry_host       = var.gitea_registry_host
    registry_scheme     = var.gitea_registry_scheme
    repo_owner          = local.gitea_repo_owner
    registry_repo_owner = local.gitea_repo_owner
  }

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<EOT
set -euo pipefail

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "$1 not found in PATH" >&2; exit 1; }; }
require_cmd curl
require_cmd jq
require_cmd kubectl

GITEA_HTTP_BASE="$${GITEA_HTTP_BASE:?}"
GITEA_ADMIN_USERNAME="$${GITEA_ADMIN_USERNAME:?}"
GITEA_ADMIN_PWD="$${GITEA_ADMIN_PWD:?}"
GITEA_REPO_OWNER="$${GITEA_REPO_OWNER:?}"
REGISTRY_HOST="$${REGISTRY_HOST:?}"
REGISTRY_SCHEME="$${REGISTRY_SCHEME:?}"
REGISTRY_REPO_OWNER="$${REGISTRY_REPO_OWNER:?}"
REGISTRY_USERNAME="$${REGISTRY_USERNAME:?}"
REGISTRY_PWD="$${REGISTRY_PWD:?}"

WAIT_SECONDS="$${WAIT_SECONDS:-600}"
SLEEP_SECONDS="$${SLEEP_SECONDS:-5}"
RUNNER_WAIT_SECONDS="$${RUNNER_WAIT_SECONDS:-900}"
ARGOCD_NAMESPACE="$${ARGOCD_NAMESPACE:-argocd}"
SUBNETCALC_WORKFLOW_ID="$${SUBNETCALC_WORKFLOW_ID:-build-images.yaml}"
ACTIONS_RETRIGGERED_TAG=""

decode_base64() {
  if base64 --help 2>&1 | grep -q -- '-d'; then
    base64 -d
  else
    base64 -D
  fi
}

wait_for_gitea() {
  local code
  for i in {1..120}; do
    code="$(curl -sS -o /dev/null -w "%%{http_code}" --connect-timeout 2 --max-time 5 \
      "$${GITEA_HTTP_BASE}/api/v1/version" 2>/dev/null || echo 000)"
    if [[ "$${code}" =~ ^[234][0-9][0-9]$ ]]; then
      return 0
    fi
    echo "Waiting for Gitea API... ($i/120)" >&2
    sleep 2
  done
  echo "Gitea API not reachable at $${GITEA_HTTP_BASE}" >&2
  exit 1
}

wait_for_namespace() {
  local ns="$1"
  local waited=0
  while [ "$${waited}" -lt "$${RUNNER_WAIT_SECONDS}" ]; do
    if kubectl get ns "$${ns}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "Timed out waiting for namespace $${ns}" >&2
  exit 1
}

wait_for_deployment() {
  local ns="$1"
  local name="$2"
  local waited=0
  while [ "$${waited}" -lt "$${RUNNER_WAIT_SECONDS}" ]; do
    if kubectl -n "$${ns}" get deploy "$${name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "Timed out waiting for deployment $${ns}/$${name}" >&2

  if [ "$${ns}" = "gitea-runner" ] && [ "$${name}" = "act-runner" ]; then
    echo "ArgoCD app status (gitea-actions-runner):" >&2
    kubectl -n "$${ARGOCD_NAMESPACE}" get applications.argoproj.io gitea-actions-runner \
      -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}' 2>/dev/null || true
    kubectl -n "$${ARGOCD_NAMESPACE}" get applications.argoproj.io gitea-actions-runner \
      -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.message}{"\n"}{end}' 2>/dev/null || true
  fi

  exit 1
}

wait_for_runner() {
  echo "Waiting for Gitea Actions runner (gitea-runner/act-runner)..."
  wait_for_namespace "gitea-runner"
  wait_for_deployment "gitea-runner" "act-runner"
  if ! kubectl -n gitea-runner rollout status deploy/act-runner --timeout="$${RUNNER_WAIT_SECONDS}s"; then
    echo "Gitea Actions runner not ready" >&2
    kubectl -n gitea-runner get pods -o wide || true
    exit 1
  fi
}

latest_subnetcalc_sha() {
  local waited=0
  while [ "$${waited}" -lt "$${WAIT_SECONDS}" ]; do
    local resp code json sha
    resp="$(curl -sS -u "$${GITEA_ADMIN_USERNAME}:$${GITEA_ADMIN_PWD}" \
      "$${GITEA_HTTP_BASE}/api/v1/repos/$${GITEA_REPO_OWNER}/subnet-calculator/commits?limit=1" \
      -w '\n%%{http_code}')"
    code="$(printf '%s' "$${resp}" | tail -n 1)"
    json="$(printf '%s' "$${resp}" | sed '$d')"

    if [ "$${code}" = "200" ]; then
      sha="$(printf '%s' "$${json}" | jq -r '.[0].sha // empty')"
      if [ -n "$${sha}" ] && [ "$${sha}" != "null" ]; then
        echo "$${sha}"
        return 0
      fi
    elif [ "$${code}" = "409" ]; then
      echo "Subnet-calculator repo has no commits yet; waiting..." >&2
    else
      echo "Unexpected HTTP $${code} from subnet-calculator commits API" >&2
    fi

    sleep "$${SLEEP_SECONDS}"
    waited=$((waited + SLEEP_SECONDS))
  done

  return 1
}

wait_for_tag() {
  local image="$1"
  local url="$${REGISTRY_SCHEME}://$${REGISTRY_HOST}/v2/$${REGISTRY_REPO_OWNER}/$${image}/tags/list"
  local waited=0
  while [ "$${waited}" -lt "$${WAIT_SECONDS}" ]; do
    check_actions_failure "$${TAG}"
    local json
    json="$(curl -fsS -u "$${REGISTRY_USERNAME}:$${REGISTRY_PWD}" "$${url}" || true)"
    if [ -n "$${json}" ] && ! echo "$${json}" | jq -e '.errors? | length > 0' >/dev/null 2>&1; then
      if echo "$${json}" | jq -r '.tags[]?' | grep -qx "$${TAG}"; then
        echo "Found $${image}:$${TAG} in registry"
        return 0
      fi
    fi
    sleep "$${SLEEP_SECONDS}"
    waited=$((waited + SLEEP_SECONDS))
  done
  echo "Timed out waiting for $${image}:$${TAG} in registry" >&2
  exit 1
}

wait_for_policies_tag() {
  local file="$1"
  local waited=0
  while [ "$${waited}" -lt "$${WAIT_SECONDS}" ]; do
    check_actions_failure "$${TAG}"
    local json content decoded
    json="$(curl -fsS -u "$${GITEA_ADMIN_USERNAME}:$${GITEA_ADMIN_PWD}" \
      "$${GITEA_HTTP_BASE}/api/v1/repos/$${GITEA_REPO_OWNER}/policies/contents/$${file}?ref=main" || true)"
    content="$(echo "$${json}" | jq -r '.content // empty' | tr -d '\n')"
    if [ -n "$${content}" ]; then
      decoded="$(printf '%s' "$${content}" | decode_base64)"
      if echo "$${decoded}" | grep -q "subnetcalc-frontend-react:$${TAG}"; then
        echo "Policies updated in $${file}"
        return 0
      fi
    fi
    sleep "$${SLEEP_SECONDS}"
    waited=$((waited + SLEEP_SECONDS))
  done
  echo "Timed out waiting for policies $${file} to reference $${TAG}" >&2
  exit 1
}

dispatch_subnetcalc_workflow() {
  local resp code body
  resp="$(curl -sS -u "$${GITEA_ADMIN_USERNAME}:$${GITEA_ADMIN_PWD}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d '{"ref":"main"}' \
    "$${GITEA_HTTP_BASE}/api/v1/repos/$${GITEA_REPO_OWNER}/subnet-calculator/actions/workflows/$${SUBNETCALC_WORKFLOW_ID}/dispatches" \
    -w '\n%%{http_code}' || true)"
  code="$(printf '%s' "$${resp}" | tail -n 1)"
  body="$(printf '%s' "$${resp}" | sed '$d')"

  if [ "$${code}" = "204" ] || [ "$${code}" = "201" ]; then
    return 0
  fi

  echo "Failed to dispatch subnet-calculator workflow ($${SUBNETCALC_WORKFLOW_ID}), HTTP $${code}" >&2
  if [ -n "$${body}" ]; then
    echo "$${body}" >&2
  fi
  return 1
}

check_actions_failure() {
  local tag="$1"
  local json status conclusion run_id run_url
  json="$(curl -fsS -u "$${GITEA_ADMIN_USERNAME}:$${GITEA_ADMIN_PWD}" \
    "$${GITEA_HTTP_BASE}/api/v1/repos/$${GITEA_REPO_OWNER}/subnet-calculator/actions/runs?limit=5" || true)"
  if [ -z "$${json}" ]; then
    return 0
  fi
  status="$(echo "$${json}" | jq -r --arg tag "$${tag}" '.workflow_runs[] | select(.head_sha | startswith($tag)) | .status' | head -n1)"
  conclusion="$(echo "$${json}" | jq -r --arg tag "$${tag}" '.workflow_runs[] | select(.head_sha | startswith($tag)) | .conclusion' | head -n1)"
  run_id="$(echo "$${json}" | jq -r --arg tag "$${tag}" '.workflow_runs[] | select(.head_sha | startswith($tag)) | .id // empty' | head -n1)"
  run_url="$(echo "$${json}" | jq -r --arg tag "$${tag}" '.workflow_runs[] | select(.head_sha | startswith($tag)) | .html_url // empty' | head -n1)"
  if [ "$${status}" = "completed" ] && [ -n "$${conclusion}" ] && [ "$${conclusion}" != "success" ]; then
    if [ "$${ACTIONS_RETRIGGERED_TAG}" != "$${tag}" ]; then
      echo "Subnet-calculator Actions run for $${tag} failed ($${conclusion}). Triggering one workflow_dispatch retry..." >&2
      if dispatch_subnetcalc_workflow; then
        ACTIONS_RETRIGGERED_TAG="$${tag}"
        return 0
      fi
      echo "Automatic retry dispatch failed; surfacing workflow failure details." >&2
    fi

    echo "Subnet-calculator Actions run for $${tag} failed ($${conclusion}). Policies will not update until it succeeds." >&2
    if [ -n "$${run_url}" ]; then
      echo "Run URL: $${run_url}" >&2
    fi
    if [ -n "$${run_id}" ]; then
      local job_json job_id excerpt
      job_json="$(curl -fsS -u "$${GITEA_ADMIN_USERNAME}:$${GITEA_ADMIN_PWD}" \
        "$${GITEA_HTTP_BASE}/api/v1/repos/$${GITEA_REPO_OWNER}/subnet-calculator/actions/runs/$${run_id}/jobs" || true)"
      job_id="$(echo "$${job_json}" | jq -r '.jobs[0].id // empty')"
      if [ -n "$${job_id}" ]; then
        excerpt="$(
          curl -fsS -u "$${GITEA_ADMIN_USERNAME}:$${GITEA_ADMIN_PWD}" \
            "$${GITEA_HTTP_BASE}/api/v1/repos/$${GITEA_REPO_OWNER}/subnet-calculator/actions/jobs/$${job_id}/logs" 2>/dev/null \
            | tr -d '\r' \
            | grep -Ei "ERROR|failed to|\\bFailure\\b|exit status|timed out|timeout|denied|unauthorized|DeadlineExceeded" \
            | tail -n 30 || true
        )"
        if [ -n "$${excerpt}" ]; then
          echo "Failure excerpts (job $${job_id}):" >&2
          printf '%s\n' "$${excerpt}" >&2
        fi
      fi
    fi
    exit 1
  fi
}

wait_for_gitea
wait_for_runner
if ! sha="$(latest_subnetcalc_sha)"; then
  echo "Failed to resolve subnet-calculator commit SHA" >&2
  exit 1
fi
TAG="$${sha:0:12}"
echo "Waiting for subnetcalc images and policies to reach tag $${TAG}..."

wait_for_tag "subnetcalc-frontend-react"
wait_for_tag "subnetcalc-frontend-typescript-vite"
wait_for_policies_tag "apps/workloads/base/all.yaml"

echo "Subnetcalc images and policies are ready for tag $${TAG}"
EOT

    environment = {
      GITEA_HTTP_BASE      = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
      GITEA_ADMIN_USERNAME = var.gitea_admin_username
      GITEA_ADMIN_PWD      = var.gitea_admin_pwd
      GITEA_REPO_OWNER     = local.gitea_repo_owner
      REGISTRY_REPO_OWNER  = local.gitea_repo_owner
      REGISTRY_HOST        = var.gitea_registry_host
      REGISTRY_SCHEME      = var.gitea_registry_scheme
      REGISTRY_USERNAME    = var.gitea_admin_username
      REGISTRY_PWD         = var.gitea_admin_pwd
      KUBECONFIG           = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    null_resource.sync_gitea_app_repo_subnet_calculator,
    kubernetes_secret_v1.gitea_runner,
  ]
}

# -----------------------------------------------------------------------------
# In-cluster Gitea Actions Runner (optional)
# -----------------------------------------------------------------------------

data "external" "gitea_runner_token" {
  count   = var.enable_actions_runner && var.enable_gitea && var.enable_argocd ? 1 : 0
  program = ["/bin/bash", "${path.module}/scripts/fetch-gitea-runner-token.sh"]

  query = {
    gitea_http_base      = "http://${local.gitea_http_host_local}:${var.gitea_http_node_port}"
    gitea_admin_username = var.gitea_admin_username
    gitea_admin_pwd      = var.gitea_admin_pwd
    kubeconfig_path      = local.kubeconfig_path_expanded
    kubeconfig_context   = trimspace(var.kubeconfig_context)
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

resource "null_resource" "gitea_known_hosts_cluster" {
  count = local.enable_gitops_repo ? 1 : 0

  triggers = {
    # Re-run if the cluster identity changes (kind reset/recreate or kubeconfig/context switch).
    cluster_id = var.provision_kind_cluster ? kind_cluster.local[0].id : "external:${local.kubeconfig_path_expanded}:${length(trimspace(var.kubeconfig_context)) > 0 ? trimspace(var.kubeconfig_context) : "default"}"
    host       = local.gitea_ssh_host_cluster
    port       = tostring(local.gitea_ssh_port_cluster)
    script_v   = "7"
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
mkdir -p "${local.run_dir}"

HOST="${local.gitea_ssh_host_cluster}"
PORT="${local.gitea_ssh_port_cluster}"
OUT_TMP="${local.run_dir}/.gitea_known_hosts_cluster.tmp"
RAW="${local.run_dir}/.gitea_known_hosts_cluster.raw"
GITEA_NS="${kubernetes_namespace_v1.gitea[0].metadata[0].name}"
GITEA_SVC="gitea-ssh"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "$1 not found in PATH" >&2; exit 1; }; }
require_cmd ssh-keyscan
require_cmd kubectl

CLUSTER_IP="$(kubectl -n "$GITEA_NS" get svc "$GITEA_SVC" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)"
EXTRA_HOSTS=()
if [ -n "$CLUSTER_IP" ] && [ "$CLUSTER_IP" != "None" ]; then
  EXTRA_HOSTS+=("$CLUSTER_IP")
fi

for i in {1..30}; do
  if ssh-keyscan -p ${var.gitea_ssh_node_port} ${local.gitea_ssh_host_local} 2>/dev/null > "$RAW" && [ -s "$RAW" ]; then

    if ! grep -E '^[^#]' "$RAW" >/dev/null 2>&1; then
      echo "ssh-keyscan output contained no host key lines" >&2
      break
    fi

    KEYS_FILE="${local.run_dir}/.gitea_known_hosts_cluster.keys"
    : > "$KEYS_FILE"

    # Some Argo CD / go-git SSH paths verify against the resolved address, not the original host.
    # Emit known_hosts entries for both the service DNS name and its ClusterIP.
    for h in "$HOST" "$${EXTRA_HOSTS[@]}"; do
      grep -E '^[^#]' "$RAW" | sed "s/^[^ ]* /$${h} /" >> "$KEYS_FILE"
    done

    # ArgoCD treats explicit ports as part of the host identity for ssh:// URLs.
    # Emit both formats for every key line returned by ssh-keyscan.
    : > "$OUT_TMP"
    while IFS= read -r key_line; do
      key_host="$(echo "$key_line" | awk '{print $1}')"
      echo "$key_line" >> "$OUT_TMP"
      echo "$key_line" | sed "s/^$key_host /[$key_host]:$PORT /" >> "$OUT_TMP"
    done < "$KEYS_FILE"

    mv "$OUT_TMP" "${local.gitea_known_hosts_cluster_path}"
    rm -f "$KEYS_FILE" 2>/dev/null || true
    rm -f "$RAW" 2>/dev/null || true
    exit 0
  fi
  echo "ssh-keyscan (cluster) failed, retrying... ($i/30)" >&2
  sleep 4
done

echo "Failed to capture Gitea SSH host key (cluster)" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
    environment = {
      KUBECONFIG = local.kubeconfig_path_expanded
    }
  }

  depends_on = [
    null_resource.sync_gitea_policies_repo,
    local_sensitive_file.kubeconfig,
  ]
}

data "local_file" "gitea_known_hosts_cluster" {
  count    = local.enable_gitops_repo ? 1 : 0
  filename = local.gitea_known_hosts_cluster_path
  depends_on = [
    null_resource.gitea_known_hosts_cluster,
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
  argocd_ssh_known_hosts_base = local.enable_gitops_repo ? try(data.kubernetes_config_map_v1.argocd_ssh_known_hosts_cm[0].data["ssh_known_hosts"], "") : ""

  argocd_ssh_known_hosts_merged = local.enable_gitops_repo ? format(
    "%s\n",
    join(
      "\n",
      distinct(concat(
        compact(split("\n", trimspace(local.argocd_ssh_known_hosts_base))),
        compact(split("\n", trimspace(data.local_file.gitea_known_hosts_cluster[0].content))),
      )),
    ),
  ) : ""
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
    null_resource.gitea_known_hosts_cluster,
    data.local_file.gitea_known_hosts_cluster,
  ]
}

resource "null_resource" "argocd_repo_server_restart" {
  count = local.enable_gitops_repo ? 1 : 0

  triggers = {
    cluster_id       = var.provision_kind_cluster ? kind_cluster.local[0].id : "external:${local.kubeconfig_path_expanded}:${length(trimspace(var.kubeconfig_context)) > 0 ? trimspace(var.kubeconfig_context) : "default"}"
    gitea_host_key   = sha1(data.local_file.gitea_known_hosts_cluster[0].content)
    argocd_chart_ver = var.argocd_chart_version
    known_hosts_hash = sha1(local.argocd_ssh_known_hosts_merged)
    repo_secret_hash = sha1(join("\n", [
      local.policies_repo_url_cluster,
      tls_private_key.policies_repo[0].private_key_openssh,
      data.local_file.gitea_known_hosts_cluster[0].content,
    ]))
    restart_script_ver = "5"
  }

  provisioner "local-exec" {
    command     = <<EOT
set -euo pipefail
export KUBECONFIG="${local.kubeconfig_path_expanded}"
KNOWN_HOSTS_FILE="${local.gitea_known_hosts_cluster_path}"

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

patch_known_hosts() {
  local tmpdir
  tmpdir="$(mktemp -d)"

  local base_file="$tmpdir/base"
  local merged_file="$tmpdir/merged"
  local patch_file="$tmpdir/patch.yaml"
  local patch_out

  kubectl -n ${var.argocd_namespace} get configmap argocd-ssh-known-hosts-cm -o jsonpath='{.data.ssh_known_hosts}' > "$base_file"
  printf '\n' >> "$base_file"

  awk 'NF && !seen[$0]++' "$base_file" "$KNOWN_HOSTS_FILE" > "$merged_file"

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
    data.local_file.gitea_known_hosts_cluster,
    kubernetes_secret_v1.argocd_repo_policies,
    kubernetes_secret_v1.argocd_repo_creds_gitea_ssh,
  ]
}

resource "null_resource" "argocd_refresh_gitops_repo_apps" {
  count = local.enable_gitops_repo ? 1 : 0

  triggers = {
    gitops_repo_hash   = local.policies_repo_render_hash
    known_hosts_hash   = sha1(local.argocd_ssh_known_hosts_merged)
    gitops_repo_apps   = sha1(join(",", sort(local.argocd_gitops_repo_app_names)))
    refresh_script_ver = "4"
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

needs_refresh() {
  local app="$1"
  local sync_status
  local comparison_msg

  sync_status="$(kubectl -n "$ARGOCD_NS" get app "$app" -o jsonpath='{.status.sync.status}' 2>/dev/null || true)"
  comparison_msg="$(kubectl -n "$ARGOCD_NS" get app "$app" -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null || true)"

  if [[ "$sync_status" == "Unknown" ]]; then
    return 0
  fi

  if grep -qiE 'knownhosts: key is unknown|failed to list refs: dial tcp .*:22: connect: connection refused|failed to list refs: unexpected EOF' <<<"$comparison_msg"; then
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

end=$((SECONDS + 180))
while (( SECONDS < end )); do
  pending=0
  while IFS= read -r app; do
    [[ -n "$app" ]] || continue
    if ! kubectl -n "$ARGOCD_NS" get app "$app" >/dev/null 2>&1; then
      continue
    fi

    if needs_refresh "$app"; then
      refresh_app "$app"
      pending=1
    fi
  done <<< "$app_list"

  if [[ "$pending" -eq 0 ]]; then
    exit 0
  fi

  sleep 5
done

echo "Repo-backed Argo CD applications still have stale comparison state after refresh" >&2
exit 1
EOT
    interpreter = ["/bin/bash", "-c"]
  }

  depends_on = [
    null_resource.sync_gitea_policies_repo,
    null_resource.argocd_repo_server_restart,
    kubectl_manifest.argocd_app_of_apps,
    kubectl_manifest.argocd_app_gitea_actions_runner,
    kubectl_manifest.argocd_app_kyverno_policies,
    kubectl_manifest.argocd_app_cilium_policies,
    kubectl_manifest.argocd_app_cert_manager_config,
    kubectl_manifest.argocd_app_nginx_gateway_fabric_crds,
    kubectl_manifest.argocd_app_nginx_gateway_fabric,
    kubectl_manifest.argocd_app_platform_gateway,
    kubectl_manifest.argocd_app_platform_gateway_routes,
    kubectl_manifest.argocd_app_apim,
    kubectl_manifest.argocd_app_dev,
    kubectl_manifest.argocd_app_uat,
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
    sshKnownHosts = data.local_file.gitea_known_hosts_cluster[0].content
    insecure      = "false"
  }

  depends_on = [
    kubernetes_namespace_v1.argocd,
    helm_release.argocd,
    null_resource.gitea_known_hosts_cluster,
    data.local_file.gitea_known_hosts_cluster,
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
    sshKnownHosts = data.local_file.gitea_known_hosts_cluster[0].content
    insecure      = "false"
  }

  depends_on = [
    kubernetes_namespace_v1.argocd,
    helm_release.argocd,
    null_resource.gitea_known_hosts_cluster,
    data.local_file.gitea_known_hosts_cluster,
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
    runner_manifest_hash = var.enable_app_of_apps ? filesha256("${path.module}/apps/argocd-apps/60-gitea-actions-runner.application.yaml") : "n/a"
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
