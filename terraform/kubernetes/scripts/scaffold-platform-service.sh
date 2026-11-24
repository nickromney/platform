#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
TEMPLATE_DIR="${TEMPLATE_DIR:-${REPO_ROOT}/templates/platform-service/content}"
GITEA_URL="${GITEA_URL:-http://127.0.0.1:30090}"
GITEA_PUBLIC_URL="${GITEA_PUBLIC_URL:-https://gitea.admin.127.0.0.1.sslip.io}"
GITEA_OWNER="${GITEA_OWNER:-platform}"
GITEA_OWNER_IS_ORG="${GITEA_OWNER_IS_ORG:-true}"
GITEA_ADMIN_USERNAME="${GITEA_ADMIN_USERNAME:-gitea-admin}"
GITEA_ADMIN_PWD="${GITEA_ADMIN_PWD:-${PLATFORM_ADMIN_PASSWORD:-}}"
RENDER_SERVICE_TEMPLATE_CMD="${RENDER_SERVICE_TEMPLATE_CMD:-}"

SERVICE_NAME=""
SERVICE_OWNER="group:default/team-dolphin"
SERVICE_TEAM="dolphin"
SERVICE_DESCRIPTION="A platform app created from the platform-service template."
SERVICE_ENVIRONMENTS="dev"
FRONTEND_PORT="8080"
BACKEND_PORT="8080"
RENDER_ONLY_DIR=""

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ --name NAME [options]

Creates a Gitea repository for a new platform service from
templates/platform-service: a static frontend, a dependency-free backend,
starter Kubernetes, Kyverno and Cilium manifests, a Grafana dashboard seed,
and Gitea workflows for image builds and branch review environments.

Options:
  --name NAME             DNS-safe service and repository name (required)
  --owner REF             Owning team reference (default: group:default/team-dolphin)
  --team LABEL            DNS-safe team label (default: dolphin)
  --description TEXT      One-line description
  --environments LIST     Comma-separated: dev, uat (default: dev)
  --frontend-port PORT    Frontend container port (default: 8080)
  --backend-port PORT     Backend container port (default: 8080)
  --render-only DIR       Render into DIR and stop; no Gitea calls

Environment:
  GITEA_URL               Gitea API base reachable from this host (default: http://127.0.0.1:30090)
  GITEA_OWNER             Owner of the new repository (default: platform)
  GITEA_OWNER_IS_ORG      true creates under the org, false under the user (default: true)
  GITEA_ADMIN_USERNAME    Gitea user to authenticate as (default: gitea-admin)
  GITEA_ADMIN_PWD         Its password (default: PLATFORM_ADMIN_PASSWORD)

Review environments start when a non-main branch is pushed to the new
repository and an in-cluster runner with the review-env label is enabled.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

require_value() {
  [[ $# -ge 2 && -n "$2" ]] || fail "$1 requires a value"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi
  case "$1" in
    --name) require_value "$@"; SERVICE_NAME="$2"; shift 2 ;;
    --owner) require_value "$@"; SERVICE_OWNER="$2"; shift 2 ;;
    --team) require_value "$@"; SERVICE_TEAM="$2"; shift 2 ;;
    --description) require_value "$@"; SERVICE_DESCRIPTION="$2"; shift 2 ;;
    --environments) require_value "$@"; SERVICE_ENVIRONMENTS="$2"; shift 2 ;;
    --frontend-port) require_value "$@"; FRONTEND_PORT="$2"; shift 2 ;;
    --backend-port) require_value "$@"; BACKEND_PORT="$2"; shift 2 ;;
    --render-only) require_value "$@"; RENDER_ONLY_DIR="$2"; shift 2 ;;
    *) fail "Unknown argument: $1" ;;
  esac
done

# Preview and help stay usable without arguments; --name is enforced only once
# the script is asked to execute.
display_name="${SERVICE_NAME:-NAME}"
if [[ -n "${RENDER_ONLY_DIR}" ]]; then
  summary="would render templates/platform-service for ${display_name} into ${RENDER_ONLY_DIR}"
else
  summary="would create Gitea repository ${GITEA_OWNER}/${display_name} from templates/platform-service"
fi
shell_cli_maybe_execute_or_preview_summary usage "${summary}"

[[ -n "${SERVICE_NAME}" ]] || fail "--name is required"

render_template() {
  local out_dir="$1"
  local -a render_cmd

  if [[ -n "${RENDER_SERVICE_TEMPLATE_CMD}" ]]; then
    # Test seam: a stand-in renderer that takes the same flags.
    read -r -a render_cmd <<<"${RENDER_SERVICE_TEMPLATE_CMD}"
  else
    command -v go >/dev/null 2>&1 || fail "go not found in PATH; it runs tools/platform-helpers"
    render_cmd=(go -C "${REPO_ROOT}/tools/platform-helpers" run ./cmd/render-service-template)
  fi

  "${render_cmd[@]}" \
    --template "${TEMPLATE_DIR}" \
    --out "${out_dir}" \
    --name "${SERVICE_NAME}" \
    --owner "${SERVICE_OWNER}" \
    --team "${SERVICE_TEAM}" \
    --description "${SERVICE_DESCRIPTION}" \
    --environments "${SERVICE_ENVIRONMENTS}" \
    --frontend-port "${FRONTEND_PORT}" \
    --backend-port "${BACKEND_PORT}" ||
    fail "rendering templates/platform-service failed"
}

if [[ -n "${RENDER_ONLY_DIR}" ]]; then
  render_template "${RENDER_ONLY_DIR}"
  ok "rendered ${SERVICE_NAME} into ${RENDER_ONLY_DIR}"
  exit 0
fi

command -v curl >/dev/null 2>&1 || fail "curl not found in PATH"
command -v git >/dev/null 2>&1 || fail "git not found in PATH"
command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
[[ -n "${GITEA_ADMIN_PWD}" ]] || fail "GITEA_ADMIN_PWD or PLATFORM_ADMIN_PASSWORD must be set"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/scaffold-platform-service.XXXXXX")"
trap 'rm -rf "${work_dir}"' EXIT

# curl reads the credentials from a file so the password stays out of argv.
curl_config="${work_dir}/curl.config"
(umask 077 && printf 'user = "%s:%s"\n' "${GITEA_ADMIN_USERNAME}" "${GITEA_ADMIN_PWD}" >"${curl_config}")

gitea_api() {
  local method="$1"
  local path="$2"
  local body="${3:-}"
  local -a args=(-sS -o "${work_dir}/response.json" -w '%{http_code}' -K "${curl_config}" -X "${method}" -H 'Accept: application/json')

  if [[ -n "${body}" ]]; then
    args+=(-H 'Content-Type: application/json' --data "${body}")
  fi
  curl "${args[@]}" "${GITEA_URL%/}/api/v1${path}" || printf '000'
}

repo_path="/repos/${GITEA_OWNER}/${SERVICE_NAME}"
code="$(gitea_api GET "${repo_path}")"
case "${code}" in
  404) ;;
  200) fail "Gitea repository ${GITEA_OWNER}/${SERVICE_NAME} already exists; pick another --name or delete it first" ;;
  401|403) fail "Gitea rejected ${GITEA_ADMIN_USERNAME}'s credentials (HTTP ${code})" ;;
  *) fail "unexpected Gitea API status ${code} for ${GITEA_URL%/}/api/v1${repo_path}" ;;
esac

render_dir="${work_dir}/${SERVICE_NAME}"
render_template "${render_dir}"
ok "rendered templates/platform-service for ${SERVICE_NAME}"

create_body="$(jq -cn --arg name "${SERVICE_NAME}" --arg description "${SERVICE_DESCRIPTION}" \
  '{name: $name, description: $description, private: true, default_branch: "main", auto_init: false}')"
if [[ "${GITEA_OWNER_IS_ORG}" == "true" ]]; then
  create_path="/orgs/${GITEA_OWNER}/repos"
else
  create_path="/user/repos"
fi
code="$(gitea_api POST "${create_path}" "${create_body}")"
[[ "${code}" == "201" ]] || fail "creating ${GITEA_OWNER}/${SERVICE_NAME} returned HTTP ${code}: $(cat "${work_dir}/response.json" 2>/dev/null)"
ok "created Gitea repository ${GITEA_OWNER}/${SERVICE_NAME}"

push_url="${GITEA_URL%/}/${GITEA_OWNER}/${SERVICE_NAME}.git"
export SCAFFOLD_GIT_USERNAME="${GITEA_ADMIN_USERNAME}"
export SCAFFOLD_GIT_PASSWORD="${GITEA_ADMIN_PWD}"
# The credential helper reads the environment, so neither the URL nor argv
# carries the password.
git_in_repo() {
  git -C "${render_dir}" \
    -c user.name="platform scaffold" \
    -c user.email="scaffold@platform.local" \
    -c credential.helper= \
    -c "credential.helper=!f() { echo username=\"\${SCAFFOLD_GIT_USERNAME}\"; echo password=\"\${SCAFFOLD_GIT_PASSWORD}\"; }; f" \
    "$@"
}
git -C "${render_dir}" init -q -b main
git_in_repo add -A
git_in_repo commit -q -m "Scaffold ${SERVICE_NAME} from templates/platform-service"
git_in_repo push -q "${push_url}" main
ok "pushed main to ${GITEA_OWNER}/${SERVICE_NAME}"

echo "Repository: ${GITEA_PUBLIC_URL%/}/${GITEA_OWNER}/${SERVICE_NAME}"
echo "Grafana:    https://grafana.admin.127.0.0.1.sslip.io/d/${SERVICE_NAME}-golden-signals/${SERVICE_NAME}-golden-signals"
echo "Push a non-main branch to start a review environment."
