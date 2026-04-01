#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FILES_TO_SCAN="$(mktemp "${TMPDIR:-/tmp}/bash32-compat-files.XXXXXX")"
MATCH_FILE="$(mktemp "${TMPDIR:-/tmp}/bash32-compat-matches.XXXXXX")"
trap 'rm -f "${FILES_TO_SCAN}" "${MATCH_FILE}"' EXIT

usage() {
  cat <<'EOF'
Usage: check-bash32-compat.sh [path ...]

Scan tracked shell scripts for Bash 4+ constructs that are incompatible with
macOS's stock Bash 3.2.

Without arguments, the scan covers every tracked `*.sh` file in the repo.
When one or more paths are supplied, only those files/directories are scanned.
EOF
}

declare -a bash32_incompatible_patterns=(
  '(^|[^[:alnum:]_])(mapfile|readarray)([[:space:]]|$)'
  '(^|[^[:alnum:]_])(declare|typeset|local)[[:space:]]+-[^[:space:]]*A[^[:space:]]*([[:space:]]|$)'
  '(^|[^[:alnum:]_])(declare|typeset|local)[[:space:]]+-[^[:space:]]*n[^[:space:]]*([[:space:]]|$)'
  '(^|[^[:alnum:]_])wait[[:space:]]+-n([[:space:]]|$)'
  '(^|[^[:alnum:]_])coproc([[:space:]]|$)'
  '(^|[^[:alnum:]_])shopt[[:space:]]+-s[[:space:]]+globstar([[:space:]]|$)'
  '\$\{[^}]*\^\^'
  '\$\{[^}]*,,'
)

count=0
declare -a issues=()

display_path() {
  local file="$1"

  case "${file}" in
    "${REPO_ROOT}"/*)
      printf '%s\n' "${file#"${REPO_ROOT}/"}"
      ;;
    *)
      printf '%s\n' "${file}"
      ;;
  esac
}

scan_file() {
  local file="$1"
  local rel=""
  local pattern=""
  local match=""

  [[ -f "${file}" ]] || return 0
  rel="$(display_path "${file}")"
  count=$((count + 1))

  for pattern in "${bash32_incompatible_patterns[@]}"; do
    grep -En "${pattern}" "${file}" > "${MATCH_FILE}" || true
    while IFS= read -r match; do
      [[ -n "${match}" ]] || continue
      issues+=("${rel}:${match}")
    done < "${MATCH_FILE}"
  done
}

append_scan_path() {
  local candidate="$1"

  if [[ -d "${candidate}" ]]; then
    find "${candidate}" -type f -name '*.sh' >> "${FILES_TO_SCAN}"
    return 0
  fi

  printf '%s\n' "${candidate}" >> "${FILES_TO_SCAN}"
}

build_tracked_shell_script_list() {
  if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" ls-files -- '*.sh' | sed "s|^|${REPO_ROOT}/|" > "${FILES_TO_SCAN}"
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.run' -o -path '*/.terraform' -o -path '*/.venv' -o -path '*/venv' -o -path '*/dist' -o -path '*/build' \) -prune \
    -o -type f -name '*.sh' -print > "${FILES_TO_SCAN}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      printf 'check-bash32-compat.sh: unknown argument: %s\n' "$1" >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  : > "${FILES_TO_SCAN}"
  for candidate in "$@"; do
    append_scan_path "${candidate}"
  done
else
  build_tracked_shell_script_list
fi

LC_ALL=C sort -u "${FILES_TO_SCAN}" -o "${FILES_TO_SCAN}"

while IFS= read -r file; do
  [[ -n "${file}" ]] || continue
  scan_file "${file}"
done < "${FILES_TO_SCAN}"

if [[ "${#issues[@]}" -gt 0 ]]; then
  printf 'FAIL Bash 3.2 compatibility: incompatible constructs found in tracked shell scripts:\n' >&2
  printf '  %s\n' "${issues[@]}" >&2
  printf 'Use only Bash 3.2-compatible features in tracked *.sh files.\n' >&2
  exit 1
fi

printf 'OK   Bash 3.2 compatibility (%s script(s) scanned)\n' "${count}"
