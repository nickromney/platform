#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

REGISTRY="dhi.io"
TARGET_HELPER_NAME="platform-file"
SOURCE_HELPER_NAME="${PLATFORM_DHI_SOURCE_HELPER:-desktop}"
HELPER_BIN_DIR="${PLATFORM_DOCKER_CREDENTIAL_HELPER_BIN_DIR:-${HOME}/.local/bin}"
CREDS_FILE="${PLATFORM_DOCKER_CREDS_FILE:-${HOME}/.config/platform/docker-creds.json}"
HELPER_SCRIPT="${REPO_ROOT}/kubernetes/scripts/docker-credential-platform-file.sh"
AUTO_APPROVE="${PLATFORM_DHI_CREDS_AUTO_APPROVE:-0}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute] [options]

Migrate dhi.io Docker credentials from the current Docker Desktop credential
helper into the platform file-backed helper, then configure Docker:
  credHelpers["dhi.io"] = "platform-file"

The target helper stores pull-only dhi.io credentials in:
  ${CREDS_FILE}

Options:
  --source-helper NAME  Source helper suffix to read once (default: ${SOURCE_HELPER_NAME})
  --helper-bin-dir DIR  Directory for the docker-credential-platform-file copy (default: ${HELPER_BIN_DIR})
$(shell_cli_standard_options)
EOF
}

fail() {
  printf 'dhi-creds-offline: %s\n' "$*" >&2
  exit 1
}

docker_config_path() {
  if [[ -n "${DOCKER_CONFIG_PATH:-}" ]]; then
    printf '%s\n' "${DOCKER_CONFIG_PATH}"
    return 0
  fi

  if [[ -n "${DOCKER_CONFIG:-}" ]]; then
    printf '%s/config.json\n' "${DOCKER_CONFIG%/}"
    return 0
  fi

  printf '%s/.docker/config.json\n' "${HOME}"
}

candidate_keys() {
  printf '%s\n' \
    "dhi.io" \
    "https://dhi.io" \
    "https://dhi.io/"
}

print_plan() {
  local config_path=""

  config_path="$(docker_config_path)"
  shell_cli_print_dry_run_summary "would migrate dhi.io Docker credentials to the platform file helper"
  echo "Would read existing credentials using docker-credential-${SOURCE_HELPER_NAME}."
  echo "Would write file-backed credentials to ${CREDS_FILE}."
  echo "Would copy ${HELPER_SCRIPT} to ${HELPER_BIN_DIR}/docker-credential-platform-file."
  echo "Would back up ${config_path} before setting credHelpers[\"dhi.io\"] = \"${TARGET_HELPER_NAME}\"."
  echo "Docker must be launched with ${HELPER_BIN_DIR} on PATH so it can find docker-credential-platform-file."
}

confirm_if_interactive() {
  local answer=""

  if [[ "${AUTO_APPROVE}" = "1" ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    return 0
  fi

  printf 'Migrate dhi.io credentials to %s and update Docker config? [y/N] ' "${CREDS_FILE}" >&2
  IFS= read -r answer
  case "${answer}" in
    y|Y|yes|YES)
      return 0
      ;;
  esac
  fail "aborted"
}

require_tools() {
  command -v jq >/dev/null 2>&1 || fail "jq not found in PATH"
  [[ -x "${HELPER_SCRIPT}" ]] || fail "helper script is not executable: ${HELPER_SCRIPT}"
}

read_source_credential() {
  local helper_bin="$1"
  local key=""
  local output=""

  command -v "${helper_bin}" >/dev/null 2>&1 || fail "${helper_bin} not found in PATH; unlock your session and install/login to Docker Desktop first"

  while IFS= read -r key; do
    if output="$(printf '%s' "${key}" | "${helper_bin}" get 2>/dev/null)"; then
      if printf '%s' "${output}" | jq -e '.Username != null and .Secret != null' >/dev/null 2>&1; then
        printf '%s\n' "${output}" |
          jq -c --arg server "${REGISTRY}" '{ServerURL: $server, Username: .Username, Secret: .Secret}'
        return 0
      fi
    fi
  done < <(candidate_keys)

  fail "${helper_bin} did not return dhi.io credentials; run docker login dhi.io with an unlocked session first"
}

install_helper_symlink() {
  local target_path=""

  # Copy rather than symlink: repo checkouts (especially worktrees) move and
  # vanish, and docker resolves this helper via PATH at every credential use.
  mkdir -p "${HELPER_BIN_DIR}"
  target_path="${HELPER_BIN_DIR}/docker-credential-platform-file"
  if [[ -e "${target_path}" && ! -L "${target_path}" && ! -f "${target_path}" ]]; then
    fail "${target_path} exists and is not a regular file or symlink"
  fi
  rm -f "${target_path}"
  cp "${HELPER_SCRIPT}" "${target_path}"
  chmod 0755 "${target_path}"
  echo "Installed helper copy: ${target_path} (from ${HELPER_SCRIPT})"
}

path_contains_helper_dir() {
  case ":${PATH}:" in
    *":${HELPER_BIN_DIR}:"*)
      return 0
      ;;
  esac
  return 1
}

backup_config() {
  local config_path="$1"
  local backup_path=""
  local timestamp=""

  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  backup_path="${config_path}.platform-file-creds.${timestamp}.bak"
  cp "${config_path}" "${backup_path}"
  printf '%s\n' "${backup_path}"
}

update_docker_config() {
  local config_path="$1"
  local tmp=""

  tmp="$(mktemp "${config_path}.XXXXXX")"
  jq --arg registry "${REGISTRY}" --arg helper "${TARGET_HELPER_NAME}" \
    '.credHelpers = (.credHelpers // {}) | .credHelpers[$registry] = $helper' \
    "${config_path}" >"${tmp}"
  mv "${tmp}" "${config_path}"
}

main() {
  local config_path=""
  local helper_bin=""
  local payload=""
  local backup_path=""

  require_tools
  config_path="$(docker_config_path)"
  [[ -f "${config_path}" ]] || fail "Docker config not found at ${config_path}"
  jq -e 'type == "object"' "${config_path}" >/dev/null || fail "Docker config is not valid JSON: ${config_path}"

  confirm_if_interactive

  helper_bin="docker-credential-${SOURCE_HELPER_NAME}"
  payload="$(read_source_credential "${helper_bin}")"
  printf '%s' "${payload}" | PLATFORM_DOCKER_CREDS_FILE="${CREDS_FILE}" "${HELPER_SCRIPT}" store
  echo "Stored dhi.io credentials in ${CREDS_FILE}"

  install_helper_symlink
  backup_path="$(backup_config "${config_path}")"
  update_docker_config "${config_path}"

  echo "Updated Docker config: ${config_path}"
  echo "Backup: ${backup_path}"
  echo "Changed: credHelpers[\"dhi.io\"] = \"${TARGET_HELPER_NAME}\""
  if path_contains_helper_dir; then
    echo "PATH check: ${HELPER_BIN_DIR} is on PATH"
  else
    echo "WARN PATH check: ${HELPER_BIN_DIR} is not on PATH; Docker must be able to run docker-credential-platform-file"
  fi
  echo "Revert: restore ${backup_path}, or remove credHelpers[\"dhi.io\"] from ${config_path}; then remove ${CREDS_FILE} and ${HELPER_BIN_DIR}/docker-credential-platform-file if no longer needed."
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --source-helper)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--source-helper"
        exit 1
      }
      SOURCE_HELPER_NAME="$2"
      shift 2
      ;;
    --helper-bin-dir)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--helper-bin-dir"
        exit 1
      }
      HELPER_BIN_DIR="$2"
      shift 2
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  print_plan
  exit 0
fi
if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  print_plan
  exit 0
fi

main
