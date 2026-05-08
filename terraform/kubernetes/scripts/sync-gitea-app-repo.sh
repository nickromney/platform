#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() { echo "sync-gitea-app-repo: $*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Load an app repository sync contract and delegate to sync-gitea-repo.sh.

$(shell_cli_standard_options)
EOF
}

app_repo_sync_contract_value() {
  local key="$1"
  local file="${APP_REPO_SYNC_CONTRACT_FILE:-}"

  if [[ -z "${file}" || ! -f "${file}" ]]; then
    return 0
  fi

  jq -er --arg key "${key}" 'if has($key) then .[$key] | tostring else empty end' "${file}" 2>/dev/null || true
}

app_repo_sync_contract_default() {
  local env_name="$1"
  local contract_key="$2"
  local fallback="${3:-}"
  local value current

  value="$(app_repo_sync_contract_value "${contract_key}")"
  if [[ -z "${value}" ]]; then
    eval "current=\"\${${env_name}:-}\""
    if [[ -n "${current}" ]]; then
      return 0
    fi
    value="${fallback}"
  fi

  printf -v "${env_name}" '%s' "${value}"
}

app_repo_sync_has_extra_source_dirs() {
  local file="${APP_REPO_SYNC_CONTRACT_FILE:-}"

  [[ -n "${file}" && -f "${file}" ]] || return 1
  jq -e '(.extra_source_dirs // []) | length > 0' "${file}" >/dev/null 2>&1
}

copy_app_repo_source_dir() {
  local source="$1"
  local target="$2"

  [[ -d "${source}" ]] || fail "extra source_dir does not exist: ${source}"
  mkdir -p "${target}"
  if command -v rsync >/dev/null 2>&1; then
    rsync -a \
      --exclude '.git' \
      --exclude '.DS_Store' \
      --exclude 'node_modules' \
      --exclude '.venv' \
      --exclude '__pycache__' \
      "${source}/" "${target}/"
  else
    cp -R "${source}/." "${target}/"
  fi
}

prepare_app_repo_source_projection() {
  local file="${APP_REPO_SYNC_CONTRACT_FILE:-}"
  local projection_dir projection_source
  local entry source target

  if ! app_repo_sync_has_extra_source_dirs; then
    return 0
  fi

  projection_dir="$(mktemp -d)"
  APP_REPO_SYNC_PROJECTION_DIR="${projection_dir}"
  projection_source="${projection_dir}/repo"
  copy_app_repo_source_dir "${SOURCE_DIR}" "${projection_source}"

  while IFS= read -r entry; do
    source="$(jq -er '.source_dir // empty' <<<"${entry}")"
    target="$(jq -er '.target_dir // empty' <<<"${entry}")"
    [[ -n "${source}" ]] || fail "extra_source_dirs entry missing source_dir"
    [[ -n "${target}" ]] || fail "extra_source_dirs entry missing target_dir"
    [[ "${target}" != /* ]] || fail "extra_source_dirs target_dir must be relative: ${target}"
    [[ "${target}" != *".."* ]] || fail "extra_source_dirs target_dir must not contain '..': ${target}"
    copy_app_repo_source_dir "${source}" "${projection_source}/${target}"
  done < <(jq -c '(.extra_source_dirs // [])[]' "${file}")

  SOURCE_DIR="${projection_source}"
}

load_app_repo_sync_contract_defaults() {
  local file="${APP_REPO_SYNC_CONTRACT_FILE:-}"

  [[ -n "${file}" ]] || fail "APP_REPO_SYNC_CONTRACT_FILE is required"
  [[ -f "${file}" ]] || fail "APP_REPO_SYNC_CONTRACT_FILE not found: ${file}"
  command -v jq >/dev/null 2>&1 || fail "jq not found"

  app_repo_sync_contract_default SOURCE_DIR source_dir
  app_repo_sync_contract_default GITEA_REPO_NAME repo_name
  app_repo_sync_contract_default GITEA_REPO_OWNER repo_owner
  app_repo_sync_contract_default GITEA_REPO_OWNER_IS_ORG repo_is_org false
  app_repo_sync_contract_default GITEA_REPO_OWNER_FALLBACK repo_owner_fallback ""
  app_repo_sync_contract_default DEPLOY_KEY_TITLE deploy_key_title "ci-${GITEA_REPO_NAME:-app}-key"
}

cleanup_app_repo_projection() {
  local d="${APP_REPO_SYNC_PROJECTION_DIR:-}"
  if [[ -n "${d}" && -d "${d}" ]]; then
    rm -rf "${d}"
  fi
}

sync_gitea_app_repo_main() {
  load_app_repo_sync_contract_defaults

  : "${STACK_DIR:?STACK_DIR is required}"
  : "${SOURCE_DIR:?SOURCE_DIR is required by app repo sync contract}"
  : "${GITEA_REPO_NAME:?GITEA_REPO_NAME is required by app repo sync contract}"
  : "${GITEA_REPO_OWNER:?GITEA_REPO_OWNER is required by app repo sync contract}"
  : "${DEPLOY_KEY_TITLE:?DEPLOY_KEY_TITLE is required by app repo sync contract}"
  : "${DEPLOY_PUBLIC_KEY:?DEPLOY_PUBLIC_KEY is required}"
  : "${SSH_PRIVATE_KEY_PATH:?SSH_PRIVATE_KEY_PATH is required}"

  APP_REPO_SYNC_PROJECTION_DIR=""
  trap cleanup_app_repo_projection EXIT
  prepare_app_repo_source_projection

  export SOURCE_DIR
  export GITEA_REPO_NAME
  export GITEA_REPO_OWNER
  export GITEA_REPO_OWNER_IS_ORG
  export GITEA_REPO_OWNER_FALLBACK
  export DEPLOY_KEY_TITLE

  bash "${SCRIPT_DIR}/sync-gitea-repo.sh" --execute
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  shell_cli_handle_standard_no_args usage \
    "would load APP_REPO_SYNC_CONTRACT_FILE and sync the configured app repo into Gitea" \
    "$@"
  sync_gitea_app_repo_main
fi
