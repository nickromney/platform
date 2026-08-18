#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

MARKDOWNLINT_CONFIG_FILE="${MARKDOWNLINT_CONFIG_FILE:-${REPO_ROOT}/.markdownlint}"
MARKDOWNLINT_BIN="${MARKDOWNLINT_BIN:-}"
GIT_BIN="${GIT_BIN:-git}"
INSTALL_HINTS_SCRIPT="${INSTALL_HINTS_SCRIPT:-${REPO_ROOT}/scripts/install-tool-hints.sh}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Lint tracked Markdown files using the repo markdownlint configuration when a
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

markdownlint_version() {
  local bin="$1"

  case "$(basename "${bin}")" in
    markdownlint)
      "${bin}" --version
      ;;
    markdownlint-cli2)
      "${bin}" --help | sed -n '1p'
      ;;
    *)
      printf '%s\n' "${bin}"
      ;;
  esac
}

list_markdown_files() {
  if tool_exists "${GIT_BIN}" && "${GIT_BIN}" -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    "${GIT_BIN}" -C "${REPO_ROOT}" ls-files -z -- \
      '*.md' \
      '*.markdown' \
      ':(exclude)apps/apim-simulator/**' \
      ':(exclude)tests/artifacts/**'
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.venv' -o -path '*/.terraform' -o -path "${REPO_ROOT}/apps/apim-simulator" -o -path "${REPO_ROOT}/tests/artifacts" \) -prune \
    -o \( -type f \( -name '*.md' -o -name '*.markdown' \) -print0 \) | sort -z
}

run_markdownlint() {
  local bin="$1"
  shift

  case "$(basename "${bin}")" in
    markdownlint)
      "${bin}" -c "${MARKDOWNLINT_CONFIG_FILE}" "$@"
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
      "${bin}" --config "${tmpconfig}" "${cli2_files[@]}"
      rm -rf "${tmpdir}"
      ;;
    *)
      fail "unsupported markdownlint binary: ${bin}"
      ;;
  esac
}

shell_cli_handle_standard_no_args usage "would lint tracked Markdown files under ${REPO_ROOT}" "$@"

markdown_files=()
while IFS= read -r -d '' file; do
  markdown_files+=("${file}")
done < <(list_markdown_files)

if [[ "${#markdown_files[@]}" -eq 0 ]]; then
  echo "WARN no tracked Markdown files found under ${REPO_ROOT}"
  exit 0
fi

# Hard failure, matching lint-yaml.sh, lint-python.sh and lint-shellcheck.sh.
# This used to WARN and exit 0, which meant `make lint` reported green on any
# host without markdownlint while every tracked Markdown file went unchecked --
# the same shape of silent gap that #200 fixed for shellcheck, one level down.
if ! markdownlint_bin="$(select_markdownlint_bin)"; then
  echo "FAIL markdownlint not found in PATH" >&2
  if [[ -x "${INSTALL_HINTS_SCRIPT}" ]]; then
    echo "" >&2
    echo "Install hints:" >&2
    "${INSTALL_HINTS_SCRIPT}" --execute --plain markdownlint-cli2 | sed 's/^/  /' >&2
  fi
  exit 1
fi

[[ -f "${MARKDOWNLINT_CONFIG_FILE}" ]] || fail "missing markdownlint config: ${MARKDOWNLINT_CONFIG_FILE}"

echo "OK   $(markdownlint_version "${markdownlint_bin}")"
echo "INFO linting ${#markdown_files[@]} tracked Markdown file(s) with ${MARKDOWNLINT_CONFIG_FILE}"
run_markdownlint "${markdownlint_bin}" "${markdown_files[@]}"
echo "OK   markdownlint"
