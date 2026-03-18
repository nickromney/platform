#!/usr/bin/env bash

tf_defaults_variables_file() {
  if [[ -n "${VARIABLES_FILE:-}" ]]; then
    printf '%s\n' "${VARIABLES_FILE}"
    return 0
  fi

  local script_dir stack_dir candidate
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  stack_dir="$(cd "${script_dir}/.." && pwd)"

  if [[ -n "${STACK_DIR:-}" ]]; then
    candidate="${STACK_DIR}/variables.tf"
    if [[ -f "${candidate}" ]]; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  fi

  printf '%s\n' "${stack_dir}/variables.tf"
}

tf_default_from_variables() {
  local key="$1"
  local variables_file
  variables_file="$(tf_defaults_variables_file)"

  if [[ ! -f "${variables_file}" ]]; then
    printf '\n'
    return 0
  fi

  awk -v key="$key" '
    $0 ~ "^[[:space:]]*variable[[:space:]]+\"" key "\"[[:space:]]*{" { in_var=1; next }
    in_var && $0 ~ "^[[:space:]]*default[[:space:]]*=" {
      value=$0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      gsub(/"/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      print value
      exit
    }
    in_var && $0 ~ "^[[:space:]]*}" { in_var=0 }
  ' "${variables_file}" || true
}
