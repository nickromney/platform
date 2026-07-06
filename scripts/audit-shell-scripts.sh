#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

allowed_python_execution=(
  ".devcontainer/check-toolchain-surface.sh"
  "scripts/platform-workflow-ui.sh"
)

# Pre-existing entrypoint-interface violations grandfathered so this audit can
# run in CI. Do not add new scripts here; burn this list down by giving each
# script the standard --help/--dry-run/--execute interface.
entrypoint_interface_exemptions=(
  "apps/shared/keycloak/start-with-templated-realm.sh"
  "apps/subnetcalc/update-subnetcalc-image-tags.sh"
  "kubernetes/kind/scripts/rewrite-devcontainer-kubeconfig.sh"
  "kubernetes/kind/scripts/run-bats-shards.sh"
  "kubernetes/scripts/idp-preview-action-catalog.sh"
  "kubernetes/scripts/plan-post-apply-verification.sh"
  "kubernetes/scripts/reconcile-kubeconfig.sh"
  "kubernetes/scripts/run-diagnostic-check.sh"
  "kubernetes/scripts/run-post-apply-verification.sh"
  "kubernetes/workflow/validate-image-catalog-target-refs.sh"
  "scripts/check-make-target-surfaces.sh"
  "scripts/make-known-goals.sh"
  "scripts/platform-status-action-catalog.sh"
  "scripts/validate-json-schema.sh"
  "terraform/kubernetes/scripts/render-kind-apiserver-oidc-manifest.sh"
)

bash4_feature_patterns=(
  '(^|[^[:alnum:]_])(mapfile|readarray)([[:space:]]|$)'
  '(^|[^[:alnum:]_])(declare|typeset)[[:space:]]+-A([[:space:]]|$)'
  '(^|[^[:alnum:]_])(declare|local)[[:space:]]+-n([[:space:]]|$)'
  '(^|[^[:alnum:]_])wait[[:space:]]+-n([[:space:]]|$)'
  '(^|[^[:alnum:]_])coproc([[:space:]]|$)'
  '\$\{[^}]*\^\^'
  '\$\{[^}]*,,'
)

usage() {
  cat <<EOF
Usage: ${0##*/} [--path PATH]... [--dry-run] [--execute]

Audit tracked shell scripts for Bash 3.2 compatibility guardrails and shell
repo hygiene checks.

Scope options:
  --path PATH  Limit the audit to a tracked file or directory under the repo root.

$(shell_cli_standard_options)
EOF
}

is_allowed_python_script() {
  local candidate="$1"
  local allowed

  [ "${#allowed_python_execution[@]}" -gt 0 ] || return 1
  for allowed in "${allowed_python_execution[@]}"; do
    if [[ "${candidate}" == "${allowed}" ]]; then
      return 0
    fi
  done

  return 1
}

is_entrypoint_interface_exempt() {
  local candidate="$1"
  local allowed

  [ "${#entrypoint_interface_exemptions[@]}" -gt 0 ] || return 1
  for allowed in "${entrypoint_interface_exemptions[@]}"; do
    if [[ "${candidate}" == "${allowed}" ]]; then
      return 0
    fi
  done

  return 1
}

count=0
entrypoint_count=0
entrypoint_interface_exempt_count=0
unexpected_python=()
yaml_module_usage=()
bash4_feature_usage=()
interface_failures=()
descriptor_failures=()
library_entrypoint_failures=()
scope_paths=()
SHELL_AUDIT_PROBE_STDOUT_FILE=""
SHELL_AUDIT_PROBE_STDERR_FILE=""

cleanup_interface_probe_files() {
  rm -f "${SHELL_AUDIT_PROBE_STDOUT_FILE}" "${SHELL_AUDIT_PROBE_STDERR_FILE}"
}

ensure_interface_probe_files() {
  if [[ -n "${SHELL_AUDIT_PROBE_STDOUT_FILE}" && -n "${SHELL_AUDIT_PROBE_STDERR_FILE}" ]]; then
    return 0
  fi

  SHELL_AUDIT_PROBE_STDOUT_FILE="$(mktemp "${TMPDIR:-/tmp}/shell-audit-stdout.XXXXXX")"
  trap cleanup_interface_probe_files EXIT
  SHELL_AUDIT_PROBE_STDERR_FILE="$(mktemp "${TMPDIR:-/tmp}/shell-audit-stderr.XXXXXX")"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --path)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--path"
        exit 1
      }
      scope_paths+=("${2:-}")
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would audit tracked shell scripts for Python usage and Bash 3.2 compatibility"

python_execution_matches() {
  local file="$1"

  awk '
    /^[[:space:]]*#/ {
      next
    }

    /^[[:space:]]*$/ {
      next
    }

    /^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]+[[:space:]]+)*(if[[:space:]]+|!+[[:space:]]+)?(command[[:space:]]+|exec[[:space:]]+|env[[:space:]]+)?python3?([[:space:]]|$)/ {
      print
      found = 1
      next
    }

    /(\$\(|&&|\|\||;)[[:space:]]*(command[[:space:]]+|exec[[:space:]]+|env[[:space:]]+)?python3?([[:space:]]|$)/ {
      print
      found = 1
    }

    END {
      exit found ? 0 : 1
    }
  ' "${file}"
}

list_shell_scripts() {
  local rel=""
  local full_path=""

  if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "${#scope_paths[@]}" -gt 0 ]]; then
      while IFS= read -r -d '' rel; do
        if [[ "${rel}" == *.sh ]]; then
          printf '%s\0' "${rel}"
        fi
      done < <(git -C "${REPO_ROOT}" ls-files -z -- "${scope_paths[@]}")
      return 0
    fi

    git -C "${REPO_ROOT}" ls-files -z -- \
      '*.sh' \
      ':(exclude)apps/apim-simulator/**'
    return 0
  fi

  if [[ "${#scope_paths[@]}" -gt 0 ]]; then
    for rel in "${scope_paths[@]}"; do
      full_path="${rel}"
      if [[ "${full_path}" != /* ]]; then
        full_path="${REPO_ROOT}/${full_path}"
      fi
      if [[ -d "${full_path}" ]]; then
        find "${full_path}" \
          \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.run' -o -path '*/.terraform' -o -path '*/.venv' -o -path '*/venv' -o -path '*/dist' -o -path '*/build' \) -prune \
          -o -type f -name '*.sh' -print0
      elif [[ -f "${full_path}" && "${full_path}" == *.sh ]]; then
        printf '%s\0' "${full_path}"
      fi
    done | sort -z
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.run' -o -path '*/.terraform' -o -path '*/.venv' -o -path '*/venv' -o -path '*/dist' -o -path '*/build' -o -path "${REPO_ROOT}/apps/apim-simulator" \) -prune \
    -o -type f -name '*.sh' -print0 | sort -z
}

run_interface_probe() {
  local file="$1"
  shift

  local rc=0
  local stdout_output=""
  local stderr_output=""
  local -a env_cmd=(env -i "PATH=${PATH}")

  if [[ -n "${HOME:-}" ]]; then
    env_cmd+=("HOME=${HOME}")
  fi
  if [[ -n "${TMPDIR:-}" ]]; then
    env_cmd+=("TMPDIR=${TMPDIR}")
  fi

  ensure_interface_probe_files
  : >"${SHELL_AUDIT_PROBE_STDOUT_FILE}"
  : >"${SHELL_AUDIT_PROBE_STDERR_FILE}"

  if "${env_cmd[@]}" "${file}" "$@" >"${SHELL_AUDIT_PROBE_STDOUT_FILE}" 2>"${SHELL_AUDIT_PROBE_STDERR_FILE}"; then
    rc=0
  else
    rc=$?
  fi

  if [[ "${rc}" -ne 0 ]]; then
    SHELL_AUDIT_LAST_ERROR=""
    IFS= read -r SHELL_AUDIT_LAST_ERROR <"${SHELL_AUDIT_PROBE_STDERR_FILE}" || true
    if [[ -z "${SHELL_AUDIT_LAST_ERROR}" ]]; then
      IFS= read -r SHELL_AUDIT_LAST_ERROR <"${SHELL_AUDIT_PROBE_STDOUT_FILE}" || true
    fi
    if [[ -z "${SHELL_AUDIT_LAST_ERROR}" ]]; then
      SHELL_AUDIT_LAST_ERROR="exit ${rc}"
    fi
    return 1
  fi

  stdout_output="$(<"${SHELL_AUDIT_PROBE_STDOUT_FILE}")"
  stderr_output="$(<"${SHELL_AUDIT_PROBE_STDERR_FILE}")"
  if [[ -n "${stdout_output}" && -n "${stderr_output}" ]]; then
    SHELL_AUDIT_LAST_OUTPUT="${stdout_output}"$'\n'"${stderr_output}"
  else
    SHELL_AUDIT_LAST_OUTPUT="${stdout_output}${stderr_output}"
  fi

  return 0
}

usage_output_names_entrypoint() {
  local output="$1"
  local expected_name="$2"
  local line=""
  local text=""
  local token=""
  local check_next=0

  while IFS= read -r line || [[ -n "${line}" ]]; do
    if [[ "${line}" =~ (^|[[:space:]])Usage: ]]; then
      text="${line#*Usage:}"
      token=""
      read -r token _ <<<"${text}"
      if [[ "${token}" == "${expected_name}" ]]; then
        return 0
      fi
      if [[ -z "${token}" ]]; then
        check_next=1
      else
        check_next=0
      fi
      continue
    fi

    if [[ "${check_next}" -eq 1 && "${line}" =~ [^[:space:]] ]]; then
      token=""
      read -r token _ <<<"${line}"
      if [[ "${token}" == "${expected_name}" ]]; then
        return 0
      fi
      check_next=0
    fi
  done <<<"${output}"

  return 1
}

interface_output_has_usage() {
  local output="$1"

  [[ "${output}" =~ (^|[[:space:]])Usage: ]]
}

interface_output_has_bare_contract() {
  local output="$1"
  local expected_name="$2"

  interface_output_has_usage "${output}" \
    && [[ "${output}" == *"INFO dry-run:"* ]] \
    && usage_output_names_entrypoint "${output}" "${expected_name}"
}

interface_output_has_help_contract() {
  local output="$1"
  local expected_name="$2"

  interface_output_has_usage "${output}" \
    && [[ "${output}" == *"--dry-run"* ]] \
    && [[ "${output}" == *"--execute"* ]] \
    && usage_output_names_entrypoint "${output}" "${expected_name}"
}

entrypoint_sources_shell_cli_helper() {
  local file="$1"

  grep -Eq '(^|[[:space:]])(source|\.)[[:space:]]+.*shell-cli\.sh' "${file}" \
    && grep -Eq 'shell_cli_handle_standard_no_args|shell_cli_parse_standard_only' "${file}"
}

json_descriptor_field() {
  local json="$1"
  local field="$2"

  printf '%s\n' "${json}" | sed -n "s/.*\"${field}\":\"\\([^\"]*\\)\".*/\\1/p" | head -n 1
}

validate_entrypoint_descriptor() {
  local rel="$1"
  local file="$2"
  local expected_name="${rel##*/}"
  local descriptor=""
  local descriptor_name=""
  local descriptor_path=""
  local failures=""

  entrypoint_sources_shell_cli_helper "${file}" || return 0

  if ! run_interface_probe "${file}" --shell-entrypoint-descriptor; then
    descriptor_failures+=("${rel}: descriptor probe (${SHELL_AUDIT_LAST_ERROR})")
    return 0
  fi

  descriptor="$(printf '%s\n' "${SHELL_AUDIT_LAST_OUTPUT}" | sed -n '1p')"
  descriptor_name="$(json_descriptor_field "${descriptor}" "name")"
  descriptor_path="$(json_descriptor_field "${descriptor}" "path")"

  if [[ "${descriptor}" != *'"schema_version":"shell-entrypoint/v1"'* ]]; then
    failures="descriptor schema_version was not shell-entrypoint/v1"
  fi

  if [[ -z "${descriptor_name}" ]]; then
    if [[ -n "${failures}" ]]; then failures="${failures}; "; fi
    failures="${failures}descriptor name was missing"
  elif [[ "${descriptor_name}" != "${expected_name}" ]]; then
    if [[ -n "${failures}" ]]; then failures="${failures}; "; fi
    failures="${failures}descriptor name ${descriptor_name} did not match ${expected_name}"
  fi

  if [[ -z "${descriptor_path}" ]]; then
    if [[ -n "${failures}" ]]; then failures="${failures}; "; fi
    failures="${failures}descriptor path was missing"
  fi

  if [[ "${descriptor}" != *'"supports":["--help","--dry-run","--execute"]'* ]]; then
    if [[ -n "${failures}" ]]; then failures="${failures}; "; fi
    failures="${failures}descriptor supports did not list the standard flags"
  fi

  if [[ "${descriptor}" != *'"default_mode":"dry-run"'* ]]; then
    if [[ -n "${failures}" ]]; then failures="${failures}; "; fi
    failures="${failures}descriptor default_mode was not dry-run"
  fi

  if [[ -n "${failures}" ]]; then
    descriptor_failures+=("${rel}: ${failures}")
  fi
}

validate_entrypoint_interface() {
  local rel="$1"
  local file="$2"
  local failures=""
  local expected_name="${rel##*/}"

  if ! run_interface_probe "${file}"; then
    failures="bare invocation (${SHELL_AUDIT_LAST_ERROR})"
  elif ! interface_output_has_bare_contract "${SHELL_AUDIT_LAST_OUTPUT}" "${expected_name}"; then
    failures="bare invocation (output did not show help plus dry-run preview; Usage output did not name ${expected_name})"
  fi

  if ! run_interface_probe "${file}" --help; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--help (${SHELL_AUDIT_LAST_ERROR})"
  elif ! interface_output_has_help_contract "${SHELL_AUDIT_LAST_OUTPUT}" "${expected_name}"; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--help (output did not advertise the standard interface; Usage output did not name ${expected_name})"
  fi

  if ! run_interface_probe "${file}" --dry-run --help; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--dry-run --help (${SHELL_AUDIT_LAST_ERROR})"
  elif ! interface_output_has_help_contract "${SHELL_AUDIT_LAST_OUTPUT}" "${expected_name}"; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--dry-run --help (output did not advertise the standard interface; Usage output did not name ${expected_name})"
  fi

  if ! run_interface_probe "${file}" --execute --help; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--execute --help (${SHELL_AUDIT_LAST_ERROR})"
  elif ! interface_output_has_help_contract "${SHELL_AUDIT_LAST_OUTPUT}" "${expected_name}"; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--execute --help (output did not advertise the standard interface; Usage output did not name ${expected_name})"
  fi

  if [[ -n "${failures}" ]]; then
    interface_failures+=("${rel}: ${failures}")
  fi
}

while IFS= read -r -d '' rel; do
  if [[ "${rel}" == /* ]]; then
    file="${rel}"
    rel="${file#"${REPO_ROOT}"/}"
  else
    file="${REPO_ROOT}/${rel}"
  fi
  [[ -e "${file}" ]] || continue
  count=$((count + 1))

  if [[ "${rel}" == "scripts/lib/"* && -x "${file}" ]]; then
    library_entrypoint_failures+=("${rel}")
  elif [[ -x "${file}" ]]; then
    entrypoint_count=$((entrypoint_count + 1))
    if is_entrypoint_interface_exempt "${rel}"; then
      entrypoint_interface_exempt_count=$((entrypoint_interface_exempt_count + 1))
    else
      validate_entrypoint_interface "${rel}" "${file}"
      validate_entrypoint_descriptor "${rel}" "${file}"
    fi
  fi

  if python_matches="$(python_execution_matches "${file}" 2>/dev/null)" && [[ -n "${python_matches}" ]]; then
    if ! is_allowed_python_script "${rel}"; then
      unexpected_python+=("${rel}")
    fi
  fi

  if grep -Eq '\bimport yaml\b|yaml\.safe_load|yaml\.dump' "${file}"; then
    yaml_module_usage+=("${rel}")
  fi

  for pattern in "${bash4_feature_patterns[@]}"; do
    if grep -Eq "${pattern}" "${file}"; then
      bash4_feature_usage+=("${rel}")
      break
    fi
  done
done < <(list_shell_scripts)

if [[ "${#interface_failures[@]}" -gt 0 ]]; then
  printf 'FAIL shell audit: executable shell entrypoints must support --help, --dry-run, and --execute without prerequisites:\n' >&2
  printf '  %s\n' "${interface_failures[@]}" >&2
  exit 1
fi

if [[ "${#descriptor_failures[@]}" -gt 0 ]]; then
  printf 'FAIL shell audit: executable shell entrypoints must expose valid descriptor metadata:\n' >&2
  printf '  %s\n' "${descriptor_failures[@]}" >&2
  exit 1
fi

if [[ "${#library_entrypoint_failures[@]}" -gt 0 ]]; then
  printf 'FAIL shell audit: library scripts under scripts/lib should not be executable entrypoints:\n' >&2
  printf '  %s\n' "${library_entrypoint_failures[@]}" >&2
  exit 1
fi

if [[ "${#yaml_module_usage[@]}" -gt 0 ]]; then
  printf 'FAIL shell audit: external Python YAML module usage found in:\n' >&2
  printf '  %s\n' "${yaml_module_usage[@]}" >&2
  exit 1
fi

if [[ "${#unexpected_python[@]}" -gt 0 ]]; then
  printf 'FAIL shell audit: unexpected Python execution found in:\n' >&2
  printf '  %s\n' "${unexpected_python[@]}" >&2
  printf 'Allowlist only approved shell wrappers or provision scripts that intentionally execute Python.\n' >&2
  exit 1
fi

if [[ "${#bash4_feature_usage[@]}" -gt 0 ]]; then
  printf 'FAIL shell audit: Bash 4+ features found in tracked shell scripts:\n' >&2
  printf '  %s\n' "${bash4_feature_usage[@]}" >&2
  printf 'Tracked *.sh scripts should remain compatible with Bash 3.2.\n' >&2
  exit 1
fi

echo "OK   shell audit (${count} script(s) scanned; ${entrypoint_count} executable entrypoint(s) inspected; ${entrypoint_interface_exempt_count} legacy/helper interface exemption(s); Python execution limited to approved shell wrappers and provision scripts)"
