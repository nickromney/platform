#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

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
unexpected_python=()
yaml_module_usage=()
bash4_feature_usage=()

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

while IFS= read -r -d '' rel; do
  if [[ "${rel}" == /* ]]; then
    file="${rel}"
    rel="${file#"${REPO_ROOT}"/}"
  else
    file="${REPO_ROOT}/${rel}"
  fi
  count=$((count + 1))

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

echo "OK   shell audit (${count} script(s) scanned; Python execution limited to approved shell wrappers and provision scripts)"
