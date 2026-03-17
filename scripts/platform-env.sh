#!/usr/bin/env bash

platform_repo_root() {
  local script_dir
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "${script_dir}/.." && pwd
}

platform_env_file() {
  printf '%s\n' "${PLATFORM_ENV_FILE:-$(platform_repo_root)/.env}"
}

platform_env_template() {
  printf '%s\n' "${PLATFORM_ENV_TEMPLATE:-$(platform_repo_root)/.env.example}"
}

platform_load_env() {
  local env_file="${1:-$(platform_env_file)}"

  if [[ -f "${env_file}" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "${env_file}"
    set +a
  fi
}

platform_require_vars() {
  local env_file template_file
  local missing=()
  local name

  env_file="${PLATFORM_ENV_FILE:-$(platform_env_file)}"
  template_file="${PLATFORM_ENV_TEMPLATE:-$(platform_env_template)}"

  for name in "$@"; do
    if [[ -z "${!name:-}" ]]; then
      missing+=("${name}")
    fi
  done

  if (( ${#missing[@]} == 0 )); then
    return 0
  fi

  printf 'Missing required platform secrets: %s\n' "${missing[*]}" >&2
  if [[ -f "${template_file}" ]]; then
    printf 'Copy %s to %s and set those values.\n' "${template_file}" "${env_file}" >&2
  else
    printf 'Set them in %s or export them in your shell.\n' "${env_file}" >&2
  fi
  return 1
}
