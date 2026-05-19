#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STAGE_LADDER_HELPER="${SCRIPT_DIR}/stage-ladder.sh"
VARIABLES_FILE="${REPO_ROOT}/terraform/kubernetes/variables.tf"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ --stack-dir PATH [--label NAME] [--stages-dir PATH] [--dry-run] [--execute]

Checks that enable_* stage toggles in a Kubernetes variant stage ladder only
move forward and do not regress between tfvars stages.

Options:
  --stack-dir PATH              Kubernetes variant directory that owns staged tfvars files
  --label NAME                  Human-readable variant label for dry-run text
  --stages-dir PATH             Override staged tfvars directory for alternate ladders
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

stack_dir=""
label=""
stages_dir=""

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --stack-dir)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stack-dir"
        exit 1
      }
      stack_dir="${2:-}"
      shift 2
      ;;
    --label)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--label"
        exit 1
      }
      label="${2:-}"
      shift 2
      ;;
    --stages-dir)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--stages-dir"
        exit 1
      }
      stages_dir="${2:-}"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would validate ${label:-Kubernetes variant} stage monotonicity across staged tfvars files"

[[ -n "${stack_dir}" ]] || {
  usage
  echo "Missing --stack-dir" >&2
  exit 1
}

stack_dir="$(cd "${stack_dir}" && pwd)"
if [[ -n "${stages_dir}" ]]; then
  stages_dir="$(cd "${stages_dir}" && pwd)"
fi

if [[ ! -f "${VARIABLES_FILE}" ]]; then
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

immutable_keys=()

if [[ -n "${stages_dir}" ]]; then
  cat >"${stage_list_file}" <<EOF
100:${stages_dir}/100-cluster.tfvars
200:${stages_dir}/200-cilium.tfvars
300:${stages_dir}/300-hubble.tfvars
400:${stages_dir}/400-argocd.tfvars
500:${stages_dir}/500-gitea.tfvars
600:${stages_dir}/600-policies.tfvars
700:${stages_dir}/700-app-repos.tfvars
800:${stages_dir}/800-gateway-tls.tfvars
900:${stages_dir}/900-sso.tfvars
EOF
else
  "${STAGE_LADDER_HELPER}" --execute --stack-dir "${stack_dir}" >"${stage_list_file}"
fi

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
' "${VARIABLES_FILE}" | sort >"${defaults_file}"

if [[ ! -s "${defaults_file}" ]]; then
  echo "No enable_* boolean defaults found in ${VARIABLES_FILE}" >&2
  exit 1
fi

cut -d= -f1 "${defaults_file}" >"${keys_file}"
: >"${previous_file}"
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
  [[ -n "${stage}" ]] || continue

  if [[ ! -f "${stage_file}" ]]; then
    echo "Missing stage tfvars for stage ${stage}" >&2
    exit 1
  fi

  : >"${current_file}"
  while IFS= read -r key; do
    default_value="$(lookup_value "${defaults_file}" "${key}")"
    current_value="$(tfvar_bool "${stage_file}" "${key}" || true)"
    if [[ -z "${current_value}" ]]; then
      current_value="${default_value}"
    fi

    previous_value="$(lookup_value "${previous_file}" "${key}" || true)"
    if [[ "${previous_value}" == "true" && "${current_value}" == "false" ]]; then
      echo "Monotonicity violation: ${key} regresses true -> false at stage ${stage} (${stage_file})" >&2
      failures=$((failures + 1))
    fi
    for immutable_key in "${immutable_keys[@]}"; do
      if [[ "${key}" == "${immutable_key}" && -n "${previous_value}" && "${previous_value}" != "${current_value}" ]]; then
        echo "Monotonicity violation: ${key} changes ${previous_value} -> ${current_value} at stage ${stage} (${stage_file}); management-mode toggles must remain constant across the ladder" >&2
        failures=$((failures + 1))
      fi
    done

    printf '%s=%s\n' "${key}" "${current_value}" >>"${current_file}"
  done <"${keys_file}"

  cp "${current_file}" "${previous_file}"
done <"${stage_list_file}"

if [[ "${failures}" -ne 0 ]]; then
  echo "Stage monotonicity check failed with ${failures} regression(s)." >&2
  exit 1
fi

echo "OK   stage monotonicity"
