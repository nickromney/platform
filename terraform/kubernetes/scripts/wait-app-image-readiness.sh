#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "wait-app-image-readiness: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Waits for a Gitea app repository workflow to publish the expected image tags
and stamp the policies repository with those tags.

$(shell_cli_standard_options)
EOF
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  shell_cli_handle_standard_no_args usage "would wait for app image readiness from APP_IMAGE_READINESS_CONTRACT_FILE" "$@"
fi

contract_value() {
  local key="$1"
  local file="${APP_IMAGE_READINESS_CONTRACT_FILE:-}"

  [[ -n "${file}" && -f "${file}" ]] || fail "APP_IMAGE_READINESS_CONTRACT_FILE not found: ${file:-unset}"
  jq -er --arg key "${key}" 'if has($key) then .[$key] | tostring else empty end' "${file}"
}

contract_bool() {
  local key="$1"
  local fallback="$2"
  local file="${APP_IMAGE_READINESS_CONTRACT_FILE:-}"

  [[ -n "${file}" && -f "${file}" ]] || fail "APP_IMAGE_READINESS_CONTRACT_FILE not found: ${file:-unset}"
  jq -er --arg key "${key}" --argjson fallback "${fallback}" 'if has($key) then .[$key] else $fallback end | tostring' "${file}"
}

load_app_image_readiness_contract() {
  APP_REPO_NAME="$(contract_value repo_name)"
  APP_DISPLAY_NAME="$(contract_value display_name)"
  APP_WORKFLOW_ID="$(contract_value workflow_id)"
  APP_WORKFLOW_REF="$(contract_value workflow_ref)"
  APP_FAILURE_CONSEQUENCE="$(contract_value failure_consequence)"
  APP_ENSURE_WORKFLOW_STARTED="$(contract_bool ensure_workflow_started false)"
}

app_image_names() {
  local file="${APP_IMAGE_READINESS_CONTRACT_FILE:-}"

  [[ -n "${file}" && -f "${file}" ]] || fail "APP_IMAGE_READINESS_CONTRACT_FILE not found: ${file:-unset}"
  jq -r '.image_names[]?' "${file}"
}

policy_check_files() {
  local file="${APP_IMAGE_READINESS_CONTRACT_FILE:-}"

  [[ -n "${file}" && -f "${file}" ]] || fail "APP_IMAGE_READINESS_CONTRACT_FILE not found: ${file:-unset}"
  jq -r '.policy_checks[]?.file' "${file}"
}

policy_required_images_for_file() {
  local policy_file="$1"
  local file="${APP_IMAGE_READINESS_CONTRACT_FILE:-}"

  [[ -n "${file}" && -f "${file}" ]] || fail "APP_IMAGE_READINESS_CONTRACT_FILE not found: ${file:-unset}"
  jq -r --arg policy_file "${policy_file}" '.policy_checks[]? | select(.file == $policy_file) | .required_images[]?' "${file}"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

is_true() {
  case "${1:-}" in
    true|TRUE|1|yes|YES|y|Y) return 0 ;;
    *) return 1 ;;
  esac
}

POLICIES_REPO_DIR=""
POLICIES_REPO_HOME=""
ACTIONS_RETRIGGERED_TAG=""

policies_repo_cleanup() {
  if [ -n "${POLICIES_REPO_DIR}" ] && [ -d "${POLICIES_REPO_DIR}" ]; then
    rm -rf "${POLICIES_REPO_DIR}"
  fi
  if [ -n "${POLICIES_REPO_HOME}" ] && [ -d "${POLICIES_REPO_HOME}" ]; then
    rm -rf "${POLICIES_REPO_HOME}"
  fi
}

policies_repo_setup() {
  if [ -n "${POLICIES_REPO_DIR}" ] && [ -d "${POLICIES_REPO_DIR}/.git" ]; then
    return 0
  fi

  local gitea_host repo_url
  gitea_host="${GITEA_HTTP_BASE#*://}"
  gitea_host="${gitea_host%%/*}"
  gitea_host="${gitea_host%%:*}"

  POLICIES_REPO_HOME="$(mktemp -d)"
  chmod 700 "${POLICIES_REPO_HOME}"
  cat >"${POLICIES_REPO_HOME}/.netrc" <<EOF
machine ${gitea_host}
login ${GITEA_ADMIN_USERNAME}
password ${GITEA_ADMIN_PWD}
EOF
  chmod 600 "${POLICIES_REPO_HOME}/.netrc"

  POLICIES_REPO_DIR="$(mktemp -d)"
  repo_url="${GITEA_HTTP_BASE}/${GITEA_REPO_OWNER}/policies.git"
  HOME="${POLICIES_REPO_HOME}" GIT_TERMINAL_PROMPT=0 \
    git clone --quiet --depth=1 --branch main "${repo_url}" "${POLICIES_REPO_DIR}"
}

wait_for_gitea() {
  local code i
  for i in {1..120}; do
    code="$(curl -sS -o /dev/null -w "%{http_code}" --connect-timeout 2 --max-time 5 \
      "${GITEA_HTTP_BASE}/api/v1/version" 2>/dev/null || echo 000)"
    if [[ "${code}" =~ ^[234][0-9][0-9]$ ]]; then
      return 0
    fi
    echo "Waiting for Gitea API... (${i}/120)" >&2
    sleep 2
  done
  fail "Gitea API not reachable at ${GITEA_HTTP_BASE}"
}

wait_for_namespace() {
  local ns="$1"
  local waited=0
  while [ "${waited}" -lt "${RUNNER_WAIT_SECONDS}" ]; do
    if kubectl get ns "${ns}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  fail "Timed out waiting for namespace ${ns}"
}

wait_for_deployment() {
  local ns="$1"
  local name="$2"
  local waited=0
  while [ "${waited}" -lt "${RUNNER_WAIT_SECONDS}" ]; do
    if kubectl -n "${ns}" get deploy "${name}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
    waited=$((waited + 2))
  done
  echo "Timed out waiting for deployment ${ns}/${name}" >&2

  if [ "${ns}" = "gitea-runner" ] && [ "${name}" = "act-runner" ]; then
    echo "ArgoCD app status (gitea-actions-runner):" >&2
    kubectl -n "${ARGOCD_NAMESPACE}" get applications.argoproj.io gitea-actions-runner \
      -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}' 2>/dev/null || true
    kubectl -n "${ARGOCD_NAMESPACE}" get applications.argoproj.io gitea-actions-runner \
      -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.message}{"\n"}{end}' 2>/dev/null || true
  fi

  exit 1
}

wait_for_runner() {
  echo "Waiting for Gitea Actions runner (gitea-runner/act-runner)..."
  wait_for_namespace "gitea-runner"
  wait_for_deployment "gitea-runner" "act-runner"
  if ! kubectl -n gitea-runner rollout status deploy/act-runner --timeout="${RUNNER_WAIT_SECONDS}s"; then
    echo "Gitea Actions runner not ready" >&2
    kubectl -n gitea-runner get pods -o wide || true
    exit 1
  fi
}

latest_app_sha() {
  local waited=0
  while [ "${waited}" -lt "${WAIT_SECONDS}" ]; do
    local resp code json sha
    resp="$(curl -sS -u "${GITEA_ADMIN_USERNAME}:${GITEA_ADMIN_PWD}" \
      "${GITEA_HTTP_BASE}/api/v1/repos/${GITEA_REPO_OWNER}/${APP_REPO_NAME}/commits?limit=1" \
      -w '\n%{http_code}')"
    code="$(printf '%s' "${resp}" | tail -n 1)"
    json="$(printf '%s' "${resp}" | sed '$d')"

    if [ "${code}" = "200" ]; then
      sha="$(printf '%s' "${json}" | jq -r '.[0].sha // empty')"
      if [ -n "${sha}" ] && [ "${sha}" != "null" ]; then
        echo "${sha}"
        return 0
      fi
    elif [ "${code}" = "409" ]; then
      echo "${APP_DISPLAY_NAME} repo has no commits yet; waiting..." >&2
    else
      echo "Unexpected HTTP ${code} from ${APP_REPO_NAME} commits API" >&2
    fi

    sleep "${SLEEP_SECONDS}"
    waited=$((waited + SLEEP_SECONDS))
  done

  return 1
}

check_actions_failure() {
  review_check_actions_failure "$@"
}

ensure_workflow_started_if_requested() {
  if is_true "${APP_ENSURE_WORKFLOW_STARTED}"; then
    review_ensure_workflow_started "${TAG}"
  fi
}

wait_for_tag() {
  local image="$1"
  local url="${REGISTRY_SCHEME}://${REGISTRY_HOST}/v2/${REGISTRY_REPO_OWNER}/${image}/tags/list"
  local waited=0
  while [ "${waited}" -lt "${WAIT_SECONDS}" ]; do
    check_actions_failure "${TAG}"
    local json
    json="$(curl -fsS -u "${REGISTRY_USERNAME}:${REGISTRY_PWD}" "${url}" || true)"
    if [ -n "${json}" ] && ! echo "${json}" | jq -e '.errors? | length > 0' >/dev/null 2>&1; then
      if echo "${json}" | jq -r '.tags[]?' | grep -qx "${TAG}"; then
        echo "Found ${image}:${TAG} in registry"
        return 0
      fi
    fi
    sleep "${SLEEP_SECONDS}"
    waited=$((waited + SLEEP_SECONDS))
  done
  fail "Timed out waiting for ${image}:${TAG} in registry"
}

wait_for_policies_tag() {
  local file="$1"
  local waited=0
  local required_images=()
  local image=""
  local decoded=""

  while IFS= read -r image; do
    [ -n "${image}" ] || continue
    required_images+=("${image}")
  done < <(policy_required_images_for_file "${file}")

  policies_repo_setup
  while [ "${waited}" -lt "${WAIT_SECONDS}" ]; do
    check_actions_failure "${TAG}"
    HOME="${POLICIES_REPO_HOME}" GIT_TERMINAL_PROMPT=0 \
      git -C "${POLICIES_REPO_DIR}" fetch --quiet origin main
    decoded="$(git -C "${POLICIES_REPO_DIR}" show "FETCH_HEAD:${file}" 2>/dev/null || true)"
    if [ -n "${decoded}" ]; then
      local all_present=1
      for image in "${required_images[@]}"; do
        if ! echo "${decoded}" | grep -q "${image}:${TAG}"; then
          all_present=0
        fi
      done
      if [ "${all_present}" -eq 1 ]; then
        echo "Policies updated in ${file}"
        return 0
      fi
    fi
    sleep "${SLEEP_SECONDS}"
    waited=$((waited + SLEEP_SECONDS))
  done
  fail "Timed out waiting for policies ${file} to reference ${TAG}"
}

main() {
  local sha image policy_file

  require_cmd curl
  require_cmd jq
  require_cmd kubectl
  require_cmd git
  load_app_image_readiness_contract

  # shellcheck source=/dev/null
  source "${STACK_DIR:?STACK_DIR is required}/scripts/gitea-local-access.sh"
  # shellcheck source=/dev/null
  source "${STACK_DIR}/scripts/review-environment-dispatch.sh"
  trap 'gitea_local_access_cleanup || true; policies_repo_cleanup || true' EXIT
  gitea_local_access_setup http

  : "${GITEA_HTTP_BASE:?}"
  : "${GITEA_ADMIN_USERNAME:?}"
  : "${GITEA_ADMIN_PWD:?}"
  : "${GITEA_REPO_OWNER:?}"
  : "${REGISTRY_HOST:?}"
  : "${REGISTRY_SCHEME:?}"
  : "${REGISTRY_REPO_OWNER:?}"
  : "${REGISTRY_USERNAME:?}"
  : "${REGISTRY_PWD:?}"

  WAIT_SECONDS="${WAIT_SECONDS:-600}"
  SLEEP_SECONDS="${SLEEP_SECONDS:-5}"
  RUNNER_WAIT_SECONDS="${RUNNER_WAIT_SECONDS:-900}"
  ARGOCD_NAMESPACE="${ARGOCD_NAMESPACE:-argocd}"
  ACTIONS_RETRIGGERED_TAG=""

  wait_for_gitea
  wait_for_runner
  if ! sha="$(latest_app_sha)"; then
    fail "Failed to resolve ${APP_REPO_NAME} commit SHA"
  fi
  TAG="${sha:0:12}"
  APP_WORKFLOW_REF="${APP_WORKFLOW_REF:-main}"
  echo "Waiting for ${APP_DISPLAY_NAME} images and policies to reach tag ${TAG}..."

  ensure_workflow_started_if_requested
  while IFS= read -r image; do
    [ -n "${image}" ] || continue
    wait_for_tag "${image}"
  done < <(app_image_names)

  while IFS= read -r policy_file; do
    [ -n "${policy_file}" ] || continue
    wait_for_policies_tag "${policy_file}"
  done < <(policy_check_files)

  echo "${APP_DISPLAY_NAME} images and policies are ready for tag ${TAG}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
