#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KIND_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
STAGE_LADDER_HELPER="${KIND_DIR}/../scripts/stage-ladder.sh"
VARIABLES_FILE="${KIND_DIR}/../../terraform/kubernetes/variables.tf"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Checks that enable_* stage toggles in the kind stage ladder only move forward
and do not regress between tfvars stages.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would validate kind stage monotonicity across staged tfvars files" "$@"

if [ ! -f "${VARIABLES_FILE}" ]; then
  echo "Missing variables file: ${VARIABLES_FILE}" >&2
  exit 1
fi

defaults_file="$(mktemp)"
keys_file="$(mktemp)"
previous_file="$(mktemp)"
current_file="$(mktemp)"
stage_list_file="$(mktemp)"

cleanup() {
  rm -f "${defaults_file}" "${keys_file}" "${previous_file}" "${current_file}" "${stage_list_file}"
}
trap cleanup EXIT

immutable_keys=(
  enable_app_of_apps
)

"${STAGE_LADDER_HELPER}" --execute --stack-dir "${KIND_DIR}" > "${stage_list_file}"

awk '
  /^variable "enable_[^"]+"/ {
    name = $2
    gsub(/"/, "", name)
    in_var = 1
    next
  }
  in_var && /^[[:space:]]*default[[:space:]]*=[[:space:]]*(true|false)[[:space:]]*$/ {
    print name "=" $3
    in_var = 0
    next
  }
  in_var && /^}/ {
    in_var = 0
  }
' "${VARIABLES_FILE}" | sort > "${defaults_file}"

if [ ! -s "${defaults_file}" ]; then
  echo "No enable_* boolean defaults found in ${VARIABLES_FILE}" >&2
  exit 1
fi

cut -d= -f1 "${defaults_file}" > "${keys_file}"
: > "${previous_file}"
failures=0

lookup_value() {
  local file="$1"
  local key="$2"

  awk -F= -v lookup_key="${key}" '
    $1 == lookup_key {
      print $2
      found = 1
      exit
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "${file}"
}

tfvar_bool() {
  local file="$1"
  local key="$2"

  awk -v lookup_key="${key}" '
    {
      line = $0
      sub(/#.*/, "", line)
      if (line ~ "^[[:space:]]*" lookup_key "[[:space:]]*=") {
        sub(/^[^=]*=[[:space:]]*/, "", line)
        sub(/[[:space:]].*$/, "", line)
        if (line == "true" || line == "false") {
          print line
          found = 1
        }
      }
    }
    END {
      if (!found) {
        exit 1
      }
    }
  ' "${file}"
}

while IFS=: read -r stage stage_file; do
  [ -n "${stage}" ] || continue

  if [ ! -f "${stage_file}" ]; then
    echo "Missing stage tfvars for stage ${stage}" >&2
    exit 1
  fi

  : > "${current_file}"
  while IFS= read -r key; do
    default_value="$(lookup_value "${defaults_file}" "${key}")"
    current_value="$(tfvar_bool "${stage_file}" "${key}" || true)"
    if [ -z "${current_value}" ]; then
      current_value="${default_value}"
    fi

    previous_value="$(lookup_value "${previous_file}" "${key}" || true)"
    if [ "${previous_value}" = "true" ] && [ "${current_value}" = "false" ]; then
      echo "Monotonicity violation: ${key} regresses true -> false at stage ${stage} (${stage_file})" >&2
      failures=$((failures + 1))
    fi
    for immutable_key in "${immutable_keys[@]}"; do
      if [ "${key}" = "${immutable_key}" ] && [ -n "${previous_value}" ] && [ "${previous_value}" != "${current_value}" ]; then
        echo "Monotonicity violation: ${key} changes ${previous_value} -> ${current_value} at stage ${stage} (${stage_file}); management-mode toggles must remain constant across the ladder" >&2
        failures=$((failures + 1))
      fi
    done

    printf '%s=%s\n' "${key}" "${current_value}" >> "${current_file}"
  done < "${keys_file}"

  cp "${current_file}" "${previous_file}"
done < "${stage_list_file}"

if [ "${failures}" -ne 0 ]; then
  echo "Stage monotonicity check failed with ${failures} regression(s)." >&2
  exit 1
fi

echo "OK   stage monotonicity"
