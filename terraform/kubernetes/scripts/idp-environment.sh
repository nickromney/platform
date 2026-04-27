#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"
CATALOG_FILE="${PLATFORM_APP_CATALOG:-${REPO_ROOT}/catalog/platform-apps.json}"
RUN_DIR="${PLATFORM_IDP_RUN_DIR:-${REPO_ROOT}/.run/idp/environments}"
ACTION="${ACTION:-}"
APP="${APP:-}"
ENV_NAME="${ENV:-}"
ENV_TYPE="${ENV_TYPE:-development}"
IMAGE="${IMAGE:-}"
TARGET_ENV="${TARGET_ENV:-}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

relative_to_repo_path() {
  local from_dir="$1"
  local to_path="$2"
  local suffix=""
  local depth=0
  local prefix=""
  local i=0

  case "${from_dir}" in
    "${REPO_ROOT}"/*)
      suffix="${from_dir#"${REPO_ROOT}/"}"
      depth="$(awk -F/ '{ print NF }' <<<"${suffix}")"
      while [ "${i}" -lt "${depth}" ]; do
        prefix="${prefix}../"
        i=$((i + 1))
      done
      printf '%s%s\n' "${prefix}" "${to_path#"${REPO_ROOT}/"}"
      ;;
    *)
      printf '%s\n' "${to_path}"
      ;;
  esac
}

usage() {
  cat <<'EOF'
Usage: idp-environment.sh --action create|delete|promote --app NAME --env NAME [--image REF] [--target-env NAME]

Creates or deletes a local generated environment request, or promotes an app
image by updating the target environment image patch declared in the catalog.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi
  case "$1" in
    --action)
      ACTION="${2:-}"
      shift 2
      ;;
    --app)
      APP="${2:-}"
      shift 2
      ;;
    --env)
      ENV_NAME="${2:-}"
      shift 2
      ;;
    --env-type)
      ENV_TYPE="${2:-}"
      shift 2
      ;;
    --image)
      IMAGE="${2:-}"
      shift 2
      ;;
    --target-env)
      TARGET_ENV="${2:-}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[[ -n "${ACTION}" ]] || fail "Set ACTION or pass --action"
[[ -n "${APP}" ]] || fail "Set APP or pass --app"
[[ -n "${ENV_NAME}" ]] || fail "Set ENV or pass --env"

case "${ACTION}" in
  create)
    preview="would create environment ${ENV_NAME} for ${APP}"
    ;;
  delete)
    preview="would delete environment ${ENV_NAME} for ${APP}"
    ;;
  promote)
    preview="would promote ${APP} to ${TARGET_ENV:-${ENV_NAME}}"
    ;;
  *)
    fail "Unknown action: ${ACTION}"
    ;;
esac

shell_cli_maybe_execute_or_preview_summary usage "${preview}"

command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
[[ -f "${CATALOG_FILE}" ]] || fail "catalog not found: ${CATALOG_FILE}"
[[ "${APP}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "Invalid app name: ${APP}"
[[ "${ENV_NAME}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || fail "Invalid environment name: ${ENV_NAME}"

app_json="$(jq -c --arg app "${APP}" '.applications[] | select(.name == $app)' "${CATALOG_FILE}")"
[[ -n "${app_json}" ]] || fail "App not found in catalog: ${APP}"

request_dir="${RUN_DIR}/${APP}-${ENV_NAME}"

case "${ACTION}" in
  create)
    owner="$(jq -r '.owner' <<<"${app_json}")"
    route="https://${APP}.${ENV_NAME}.127.0.0.1.sslip.io"
    workload_base="$(relative_to_repo_path "${request_dir}" "${REPO_ROOT}/terraform/kubernetes/apps/workloads/${APP}")"
    mkdir -p "${request_dir}"
    cat >"${request_dir}/request.json" <<EOF
{
  "schema_version": "platform.idp.environment-request/v1",
  "app": "${APP}",
  "environment": "${ENV_NAME}",
  "environment_type": "${ENV_TYPE}",
  "owner": "${owner}",
  "route": "${route}",
  "status": "requested"
}
EOF
    cat >"${request_dir}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${ENV_NAME}
resources:
  - ${workload_base}
EOF
    ok "created local environment request: ${request_dir}"
    ;;
  delete)
    [[ -d "${request_dir}" ]] || fail "environment request not found: ${request_dir}"
    rm -rf "${request_dir}"
    ok "deleted local environment request: ${request_dir}"
    ;;
  promote)
    target="${TARGET_ENV:-${ENV_NAME}}"
    [[ -n "${IMAGE}" ]] || fail "Set IMAGE or pass --image for promote"
    patch_file="$(jq -r --arg env "${target}" '.deployment.image_patch_files[$env] // empty' <<<"${app_json}")"
    [[ -n "${patch_file}" ]] || fail "No image patch file declared for ${APP}/${target}"
    abs_patch="${REPO_ROOT}/${patch_file}"
    [[ -f "${abs_patch}" ]] || fail "Image patch file not found: ${abs_patch}"
    tmp_file="$(mktemp)"
    awk -v image="${IMAGE}" '
      BEGIN { replaced=0 }
      /^([[:space:]]*)image:/ && replaced == 0 {
        sub(/image:.*/, "image: " image)
        print
        replaced=1
        next
      }
      { print }
    ' "${abs_patch}" >"${tmp_file}"
    mv "${tmp_file}" "${abs_patch}"
    ok "promoted ${APP} to ${target}: ${IMAGE}"
    ;;
esac
