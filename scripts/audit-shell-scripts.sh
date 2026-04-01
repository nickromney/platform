#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

allowed_python_execution=(
  "sd-wan/lima/provision/common.sh"
  "sd-wan/lima/provision/cloud2.sh"
  "kubernetes/kind/scripts/ensure-kind-kubeconfig.sh"
  "terraform/kubernetes/scripts/configure-kind-apiserver-oidc.sh"
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
Usage: audit-shell-scripts.sh [--dry-run] [--execute]

Audit tracked shell scripts for Bash 3.2 compatibility guardrails and shell
repo hygiene checks.

$(shell_cli_standard_options)
EOF
}

is_allowed_python_script() {
  local candidate="$1"
  local allowed

  for allowed in "${allowed_python_execution[@]}"; do
    if [[ "${candidate}" == "${allowed}" ]]; then
      return 0
    fi
  done

  return 1
}

count=0
entrypoint_count=0
unexpected_python=()
yaml_module_usage=()
bash4_feature_usage=()
interface_failures=()

shell_cli_handle_standard_no_args usage "would audit tracked shell scripts for Python usage and Bash 3.2 compatibility" "$@"

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
  if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" ls-files -z -- '*.sh'
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.run' -o -path '*/.terraform' -o -path '*/.venv' -o -path '*/venv' -o -path '*/dist' -o -path '*/build' \) -prune \
    -o -type f -name '*.sh' -print0 | sort -z
}

run_interface_probe() {
  local file="$1"
  shift

  local stdout_file=""
  local stderr_file=""
  local rc=0
  local -a env_cmd=(env -i "PATH=${PATH}")

  if [[ -n "${HOME:-}" ]]; then
    env_cmd+=("HOME=${HOME}")
  fi
  if [[ -n "${TMPDIR:-}" ]]; then
    env_cmd+=("TMPDIR=${TMPDIR}")
  fi

  stdout_file="$(mktemp "${TMPDIR:-/tmp}/shell-audit-stdout.XXXXXX")"
  stderr_file="$(mktemp "${TMPDIR:-/tmp}/shell-audit-stderr.XXXXXX")"

  if "${env_cmd[@]}" "${file}" "$@" >"${stdout_file}" 2>"${stderr_file}"; then
    rc=0
  else
    rc=$?
  fi

  if [[ "${rc}" -ne 0 ]]; then
    SHELL_AUDIT_LAST_ERROR="$(head -n 1 "${stderr_file}" || true)"
    if [[ -z "${SHELL_AUDIT_LAST_ERROR}" ]]; then
      SHELL_AUDIT_LAST_ERROR="$(head -n 1 "${stdout_file}" || true)"
    fi
    if [[ -z "${SHELL_AUDIT_LAST_ERROR}" ]]; then
      SHELL_AUDIT_LAST_ERROR="exit ${rc}"
    fi
    rm -f "${stdout_file}" "${stderr_file}"
    return 1
  fi

  SHELL_AUDIT_LAST_OUTPUT="$(
    {
      cat "${stdout_file}"
      cat "${stderr_file}"
    } 2>/dev/null
  )"

  rm -f "${stdout_file}" "${stderr_file}"
  return 0
}

validate_entrypoint_interface() {
  local rel="$1"
  local file="$2"
  local failures=""

  if ! run_interface_probe "${file}"; then
    failures="bare invocation (${SHELL_AUDIT_LAST_ERROR})"
  elif ! grep -Eq '(^|[[:space:]])Usage:' <<<"${SHELL_AUDIT_LAST_OUTPUT}" \
    || ! grep -Fq -- 'INFO dry-run:' <<<"${SHELL_AUDIT_LAST_OUTPUT}"; then
    failures="bare invocation (output did not show help plus dry-run preview)"
  fi

  if ! run_interface_probe "${file}" --help; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--help (${SHELL_AUDIT_LAST_ERROR})"
  elif ! grep -Eq '(^|[[:space:]])Usage:' <<<"${SHELL_AUDIT_LAST_OUTPUT}" \
    || ! grep -Fq -- '--dry-run' <<<"${SHELL_AUDIT_LAST_OUTPUT}" \
    || ! grep -Fq -- '--execute' <<<"${SHELL_AUDIT_LAST_OUTPUT}"; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--help (output did not advertise the standard interface)"
  fi

  if ! run_interface_probe "${file}" --dry-run --help; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--dry-run --help (${SHELL_AUDIT_LAST_ERROR})"
  elif ! grep -Eq '(^|[[:space:]])Usage:' <<<"${SHELL_AUDIT_LAST_OUTPUT}" \
    || ! grep -Fq -- '--dry-run' <<<"${SHELL_AUDIT_LAST_OUTPUT}" \
    || ! grep -Fq -- '--execute' <<<"${SHELL_AUDIT_LAST_OUTPUT}"; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--dry-run --help (output did not advertise the standard interface)"
  fi

  if ! run_interface_probe "${file}" --execute --help; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--execute --help (${SHELL_AUDIT_LAST_ERROR})"
  elif ! grep -Eq '(^|[[:space:]])Usage:' <<<"${SHELL_AUDIT_LAST_OUTPUT}" \
    || ! grep -Fq -- '--dry-run' <<<"${SHELL_AUDIT_LAST_OUTPUT}" \
    || ! grep -Fq -- '--execute' <<<"${SHELL_AUDIT_LAST_OUTPUT}"; then
    if [[ -n "${failures}" ]]; then
      failures="${failures}; "
    fi
    failures="${failures}--execute --help (output did not advertise the standard interface)"
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
  count=$((count + 1))

  if [[ -x "${file}" ]]; then
    entrypoint_count=$((entrypoint_count + 1))
    validate_entrypoint_interface "${rel}" "${file}"
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

echo "OK   shell audit (${count} script(s) scanned; ${entrypoint_count} executable entrypoint(s) validated; Python execution limited to approved shell wrappers and provision scripts)"
