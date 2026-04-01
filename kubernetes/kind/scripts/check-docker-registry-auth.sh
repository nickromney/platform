#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

registry=""
display_name=""
positional=()

usage() {
  cat <<EOF >&2
Usage: check-docker-registry-auth.sh --registry HOST [--display-name NAME] [--dry-run] [--execute]

Checks whether Docker credentials exist for a registry.

Positional compatibility:
  check-docker-registry-auth.sh <registry> [display-name]

$(shell_cli_standard_options)
EOF
}

warn() {
  echo "WARN $*" >&2
}

ok() {
  echo "OK   $*"
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
  case "${registry}" in
    dhi.io)
      printf '%s\n' \
        "dhi.io" \
        "https://dhi.io" \
        "https://dhi.io/"
      ;;
    index.docker.io|docker.io)
      printf '%s\n' \
        "docker.io" \
        "https://docker.io" \
        "https://docker.io/" \
        "index.docker.io" \
        "https://index.docker.io/v1/" \
        "https://index.docker.io/v1" \
        "https://index.docker.io/v1/access-token" \
        "https://index.docker.io/v1/refresh-token"
      ;;
    *)
      printf '%s\n' \
        "${registry}" \
        "https://${registry}" \
        "https://${registry}/"
      ;;
  esac
}

helper_name_for_registry() {
  local config_path="$1"
  local helper_name=""
  local key=""

  while IFS= read -r key; do
    helper_name="$(jq -r --arg key "${key}" '.credHelpers[$key] // empty' "${config_path}")"
    if [[ -n "${helper_name}" && "${helper_name}" != "null" ]]; then
      printf '%s\n' "${helper_name}"
      return 0
    fi
  done < <(candidate_keys)

  helper_name="$(jq -r '.credsStore // empty' "${config_path}")"
  if [[ -n "${helper_name}" && "${helper_name}" != "null" ]]; then
    printf '%s\n' "${helper_name}"
  fi
}

auths_contains_registry() {
  local config_path="$1"
  local key=""

  while IFS= read -r key; do
    if jq -e --arg key "${key}" '.auths[$key] != null' "${config_path}" >/dev/null 2>&1; then
      return 0
    fi
  done < <(candidate_keys)

  return 1
}

helper_contains_registry() {
  local helper_bin="$1"
  local listing=""
  local key=""

  listing="$("${helper_bin}" list 2>/dev/null || true)"
  [[ -n "${listing}" ]] || return 1

  while IFS= read -r key; do
    if printf '%s' "${listing}" | jq -e --arg key "${key}" 'has($key)' >/dev/null 2>&1; then
      return 0
    fi
  done < <(candidate_keys)

  return 1
}

login_hint() {
  case "${registry}" in
    index.docker.io|docker.io)
      printf '%s\n' "docker login"
      ;;
    *)
      printf 'docker login %s\n' "${registry}"
      ;;
  esac
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --registry)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--registry"
        exit 1
      }
      registry="$2"
      shift 2
      ;;
    --display-name)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--display-name"
        exit 1
      }
      display_name="$2"
      shift 2
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        positional+=("$1")
        shift
      done
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      positional+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${registry}" ]]; then
  registry="${positional[0]:-}"
fi
if [[ -z "${display_name}" ]]; then
  display_name="${positional[1]:-${registry}}"
fi
if [[ "${#positional[@]}" -gt 2 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "${positional[2]}"
  exit 1
fi

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would check Docker auth for registry ${registry:-<missing>}"
  exit 0
fi

if [[ -z "${registry}" ]]; then
  usage
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  warn "jq not found; cannot inspect Docker auth for ${display_name}"
  exit 1
fi

config_path="$(docker_config_path)"
if [[ ! -f "${config_path}" ]]; then
  warn "Docker config not found at ${config_path}; cannot inspect Docker auth for ${display_name} (run: $(login_hint))"
  exit 1
fi

helper_name="$(helper_name_for_registry "${config_path}" || true)"
if [[ -n "${helper_name}" ]]; then
  helper_bin="docker-credential-${helper_name}"
  if ! command -v "${helper_bin}" >/dev/null 2>&1; then
    warn "${display_name} uses ${helper_bin}, but it is not available on PATH"
    exit 1
  fi

  if helper_contains_registry "${helper_bin}"; then
    ok "${display_name} credentials found via ${helper_bin}"
    exit 0
  fi

  warn "${display_name} credentials not found via ${helper_bin} (run: $(login_hint))"
  exit 1
fi

if auths_contains_registry "${config_path}"; then
  ok "${display_name} credentials found in $(basename "${config_path}")"
  exit 0
fi

warn "${display_name} credentials not found in Docker auth config (run: $(login_hint))"
exit 1
