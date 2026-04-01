#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

MARKDOWNLINT_CONFIG_FILE="${MARKDOWNLINT_CONFIG_FILE:-${REPO_ROOT}/.markdownlint}"
MARKDOWNLINT_BIN="${MARKDOWNLINT_BIN:-}"
GIT_BIN="${GIT_BIN:-git}"

usage() {
  cat <<EOF
Usage: fmt-markdown.sh [--dry-run] [--execute]

Format tracked Markdown files using the repo markdownlint configuration when a
supported markdownlint binary is available.

$(shell_cli_standard_options)
EOF
}

tool_exists() {
  local tool="$1"

  if [[ -z "${tool}" ]]; then
    return 1
  fi

  if [[ "${tool}" == */* ]]; then
    [[ -x "${tool}" ]]
    return
  fi

  command -v "${tool}" >/dev/null 2>&1
}

fail() {
  echo "FAIL $*" >&2
  exit 1
}

select_markdownlint_bin() {
  if tool_exists "${MARKDOWNLINT_BIN}"; then
    printf '%s\n' "${MARKDOWNLINT_BIN}"
    return 0
  fi

  if tool_exists markdownlint; then
    printf '%s\n' "markdownlint"
    return 0
  fi

  if tool_exists markdownlint-cli2; then
    printf '%s\n' "markdownlint-cli2"
    return 0
  fi

  return 1
}

list_markdown_files() {
  if tool_exists "${GIT_BIN}" && "${GIT_BIN}" -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    "${GIT_BIN}" -C "${REPO_ROOT}" ls-files -z -- '*.md' '*.markdown'
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.venv' -o -path '*/.terraform' \) -prune \
    -o \( -type f \( -name '*.md' -o -name '*.markdown' \) -print0 \) | sort -z
}

run_markdownlint_fix() {
  local bin="$1"
  shift

  case "$(basename "${bin}")" in
    markdownlint)
      "${bin}" -c "${MARKDOWNLINT_CONFIG_FILE}" -f "$@" || true
      ;;
    markdownlint-cli2)
      local tmpdir tmpconfig cli2_path cli2_files

      tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/markdownlint-config.XXXXXX")"
      tmpconfig="${tmpdir}/.markdownlint.yaml"
      cp "${MARKDOWNLINT_CONFIG_FILE}" "${tmpconfig}"
      cli2_files=()
      for cli2_path in "$@"; do
        cli2_files+=(":${cli2_path}")
      done
      "${bin}" --config "${tmpconfig}" --fix "${cli2_files[@]}" || true
      rm -rf "${tmpdir}"
      ;;
    *)
      fail "unsupported markdownlint binary: ${bin}"
      ;;
  esac
}

shell_cli_handle_standard_no_args usage "would format tracked Markdown files under ${REPO_ROOT}" "$@"

markdown_files=()
while IFS= read -r -d '' file; do
  markdown_files+=("${file}")
done < <(list_markdown_files)

if [[ "${#markdown_files[@]}" -eq 0 ]]; then
  echo "WARN no tracked Markdown files found under ${REPO_ROOT}"
  exit 0
fi

if ! markdownlint_bin="$(select_markdownlint_bin)"; then
  echo "WARN markdownlint not found in PATH; skipping tracked Markdown formatting" >&2
  exit 0
fi

[[ -f "${MARKDOWNLINT_CONFIG_FILE}" ]] || fail "missing markdownlint config: ${MARKDOWNLINT_CONFIG_FILE}"

echo "INFO formatting ${#markdown_files[@]} tracked Markdown file(s) with ${MARKDOWNLINT_CONFIG_FILE}"
run_markdownlint_fix "${markdownlint_bin}" "${markdown_files[@]}"
"${SCRIPT_DIR}/lint-markdown.sh" --execute
