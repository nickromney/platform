#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

TOFU_BIN="${TOFU_BIN:-}"
TERRAFORM_BIN="${TERRAFORM_BIN:-}"
GIT_BIN="${GIT_BIN:-git}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Format tracked Terraform/OpenTofu/HCL files using any available \`tofu fmt\`
and/or \`terraform fmt\` binaries.

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

select_tool_bin() {
  local requested="$1"
  local fallback="$2"

  if tool_exists "${requested}"; then
    printf '%s\n' "${requested}"
    return 0
  fi

  if tool_exists "${fallback}"; then
    printf '%s\n' "${fallback}"
    return 0
  fi

  return 1
}

list_hcl_files() {
  if tool_exists "${GIT_BIN}" && "${GIT_BIN}" -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    "${GIT_BIN}" -C "${REPO_ROOT}" ls-files -z -- \
      '*.hcl' \
      '*.tf' \
      '*.tfvars' \
      '.terraform.lock.hcl'
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/.run' -o -path '*/node_modules' -o -path '*/.terraform' -o -path '*/.terragrunt-cache' -o -path '*/.venv' \) -prune \
    -o \( -type f \( -name '*.hcl' -o -name '*.tf' -o -name '*.tfvars' -o -name '.terraform.lock.hcl' \) -print0 \) | sort -z
}

run_fmt() {
  local bin="$1"
  shift

  echo "INFO running $(basename "${bin}") fmt on ${#terraform_fmt_files[@]} Terraform fmt-compatible file(s)"
  "${bin}" fmt "$@"
}

shell_cli_handle_standard_no_args usage "would format tracked HCL/Terraform files under ${REPO_ROOT}" "$@"

hcl_files=()
while IFS= read -r -d '' file; do
  hcl_files+=("${file}")
done < <(list_hcl_files)

if [[ "${#hcl_files[@]}" -eq 0 ]]; then
  echo "WARN no tracked HCL/Terraform files found under ${REPO_ROOT}"
  exit 0
fi

terraform_fmt_files=()
skipped_hcl_files=()
for file in "${hcl_files[@]}"; do
  case "${file}" in
    *.tf|*.tfvars|*.tftest.hcl)
      terraform_fmt_files+=("${file}")
      ;;
    *)
      skipped_hcl_files+=("${file}")
      ;;
  esac
done

if [[ "${#terraform_fmt_files[@]}" -eq 0 ]]; then
  echo "WARN no Terraform fmt-compatible files found under ${REPO_ROOT}"
  if [[ "${#skipped_hcl_files[@]}" -gt 0 ]]; then
    echo "INFO skipped ${#skipped_hcl_files[@]} generic HCL file(s) unsupported by tofu/terraform fmt"
  fi
  exit 0
fi

formatter_bins=()
if tofu_bin="$(select_tool_bin "${TOFU_BIN}" tofu 2>/dev/null)"; then
  formatter_bins+=("${tofu_bin}")
fi
if terraform_bin="$(select_tool_bin "${TERRAFORM_BIN}" terraform 2>/dev/null)"; then
  formatter_bins+=("${terraform_bin}")
fi

if [[ "${#formatter_bins[@]}" -eq 0 ]]; then
  fail "neither tofu nor terraform was found in PATH"
fi

echo "INFO formatting ${#terraform_fmt_files[@]} Terraform fmt-compatible file(s) under ${REPO_ROOT}"
if [[ "${#skipped_hcl_files[@]}" -gt 0 ]]; then
  echo "INFO skipping ${#skipped_hcl_files[@]} generic HCL file(s) unsupported by tofu/terraform fmt"
fi
for formatter_bin in "${formatter_bins[@]}"; do
  version_line="$("${formatter_bin}" version 2>/dev/null | head -n 1 || true)"
  if [[ -n "${version_line}" ]]; then
    echo "OK   ${version_line}"
  fi
  run_fmt "${formatter_bin}" "${terraform_fmt_files[@]}"
done
