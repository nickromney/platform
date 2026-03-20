#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

allowed_inline_python=(
  "sd-wan/lima/provision/common.sh"
  "sd-wan/lima/provision/cloud2.sh"
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

  for allowed in "${allowed_inline_python[@]}"; do
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

  if grep -Eq '(^|[^[:alnum:]_])(python3|python)([[:space:]]|$)' "${file}"; then
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
  printf 'FAIL shell audit: unexpected inline Python found in:\n' >&2
  printf '  %s\n' "${unexpected_python[@]}" >&2
  printf 'Allowlist only scripts that intentionally provision or run Python.\n' >&2
  exit 1
fi

if [[ "${#bash4_feature_usage[@]}" -gt 0 ]]; then
  printf 'FAIL shell audit: Bash 4+ features found in tracked shell scripts:\n' >&2
  printf '  %s\n' "${bash4_feature_usage[@]}" >&2
  printf 'Tracked *.sh scripts should remain compatible with Bash 3.2.\n' >&2
  exit 1
fi

echo "OK   shell audit (${count} script(s) scanned; inline Python limited to provision scripts)"
