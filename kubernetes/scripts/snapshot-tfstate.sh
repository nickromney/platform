#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

DEFAULT_STATE_FILE="${REPO_ROOT}/terraform/.run/kubernetes/terraform.tfstate"
STATE_FILE="${TFSTATE_SNAPSHOT_STATE_FILE:-${DEFAULT_STATE_FILE}}"
KEEP="${TFSTATE_SNAPSHOT_KEEP:-5}"
RESTORE_MODE=0
RESTORE_COMMAND=""

usage() {
  cat <<EOF
Usage: ${0##*/} [--state-file PATH] [--keep N] [--restore] [--restore-command COMMAND] [--dry-run] [--execute]

Snapshot or explicitly restore the local Terraform/OpenTofu state file.

Options:
  --state-file PATH          Live terraform.tfstate path (default: ${DEFAULT_STATE_FILE})
  --keep N                   Number of snapshots to keep after creating one (default: ${KEEP})
  --restore                  Preview or execute guarded restore from the newest snapshot
  --restore-command COMMAND  Operator command printed when a zero-byte live state is detected

$(shell_cli_standard_options)
EOF
}

fail() {
  printf 'FAIL %s\n' "$*" >&2
  exit 1
}

warn() {
  printf 'WARN %s\n' "$*" >&2
}

ok() {
  printf 'OK   %s\n' "$*"
}

snapshot_dir() {
  printf '%s/snapshots\n' "$(dirname "${STATE_FILE}")"
}

snapshot_prefix() {
  printf '%s' "$(basename "${STATE_FILE}")"
}

newest_snapshot() {
  local dir prefix

  dir="$(snapshot_dir)"
  prefix="$(snapshot_prefix)"
  [[ -d "${dir}" ]] || return 1
  find "${dir}" -type f -name "${prefix}.*.snapshot" -size +0c -print 2>/dev/null | sort | tail -n 1
}

print_restore_command_warning() {
  local snapshot restore_command

  snapshot="$(newest_snapshot || true)"
  if [[ -n "${RESTORE_COMMAND}" ]]; then
    restore_command="${RESTORE_COMMAND}"
  else
    restore_command="${0} --restore --execute --state-file ${STATE_FILE}"
  fi

  warn "live Terraform/OpenTofu state is zero bytes: ${STATE_FILE}"
  if [[ -n "${snapshot}" ]]; then
    warn "newest non-empty snapshot: ${snapshot}"
    warn "restore explicitly with: ${restore_command}"
  else
    warn "no non-empty snapshots found under $(snapshot_dir)"
  fi
}

validate_keep() {
  case "${KEEP}" in
    ''|*[!0-9]*)
      fail "--keep must be a positive integer"
      ;;
  esac
  if [[ "${KEEP}" -lt 1 ]]; then
    fail "--keep must be at least 1"
  fi
}

prune_snapshots() {
  local dir prefix count remove_count

  dir="$(snapshot_dir)"
  prefix="$(snapshot_prefix)"
  [[ -d "${dir}" ]] || return 0

  count="$(find "${dir}" -type f -name "${prefix}.*.snapshot" -print 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${count}" -le "${KEEP}" ]]; then
    return 0
  fi

  remove_count=$((count - KEEP))
  find "${dir}" -type f -name "${prefix}.*.snapshot" -print 2>/dev/null | sort | head -n "${remove_count}" | while IFS= read -r old_snapshot; do
    [[ -n "${old_snapshot}" ]] || continue
    rm -f "${old_snapshot}"
  done
}

create_snapshot() {
  local dir prefix timestamp snapshot_path

  validate_keep

  if [[ ! -e "${STATE_FILE}" ]]; then
    ok "No live Terraform/OpenTofu state found; snapshot skipped: ${STATE_FILE}"
    return 0
  fi

  if [[ ! -s "${STATE_FILE}" ]]; then
    print_restore_command_warning
    return 1
  fi

  dir="$(snapshot_dir)"
  prefix="$(snapshot_prefix)"
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
  snapshot_path="${dir}/${prefix}.${timestamp}.$$.snapshot"

  mkdir -p "${dir}"
  cp -p "${STATE_FILE}" "${snapshot_path}"
  prune_snapshots
  ok "Terraform/OpenTofu state snapshot: ${snapshot_path}"
}

restore_snapshot() {
  local snapshot

  snapshot="$(newest_snapshot || true)"
  if [[ -z "${snapshot}" ]]; then
    fail "No non-empty Terraform/OpenTofu state snapshot found under $(snapshot_dir)"
  fi

  if [[ ! -e "${STATE_FILE}" ]]; then
    fail "Live Terraform/OpenTofu state is missing; guarded restore only handles existing zero-byte state: ${STATE_FILE}"
  fi

  if [[ -s "${STATE_FILE}" ]]; then
    fail "Refusing to restore because live Terraform/OpenTofu state is non-empty: ${STATE_FILE}"
  fi

  printf 'Restore candidate:\n'
  printf '  live:     %s\n' "${STATE_FILE}"
  printf '  snapshot: %s\n' "${snapshot}"

  if [[ "${SHELL_CLI_EXECUTE}" -eq 1 ]]; then
    cp -p "${snapshot}" "${STATE_FILE}"
    ok "Restored Terraform/OpenTofu state from ${snapshot}"
  fi
}

preview() {
  if [[ "${RESTORE_MODE}" -eq 1 ]]; then
    shell_cli_print_dry_run_summary "would restore newest non-empty snapshot only if live state exists and is zero bytes: ${STATE_FILE}"
  else
    shell_cli_print_dry_run_summary "would snapshot non-empty Terraform/OpenTofu state and keep last ${KEEP}: ${STATE_FILE}"
  fi
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --state-file)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--state-file"
        exit 1
      }
      STATE_FILE="${2:-}"
      shift 2
      ;;
    --keep)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--keep"
        exit 1
      }
      KEEP="${2:-}"
      shift 2
      ;;
    --restore)
      RESTORE_MODE=1
      shift
      ;;
    --restore-command)
      [[ $# -ge 2 ]] || {
        shell_cli_missing_value "$(shell_cli_script_name)" "--restore-command"
        exit 1
      }
      RESTORE_COMMAND="${2:-}"
      shift 2
      ;;
    --)
      shift
      break
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
    *)
      shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
  exit 1
fi

if [[ -z "${STATE_FILE}" ]]; then
  fail "--state-file must not be empty"
fi

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  if [[ "${RESTORE_MODE}" -eq 1 ]]; then
    restore_snapshot
  else
    preview
  fi
  exit 0
fi

if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  if [[ "${RESTORE_MODE}" -eq 1 ]]; then
    restore_snapshot
  else
    preview
  fi
  exit 0
fi

if [[ "${RESTORE_MODE}" -eq 1 ]]; then
  restore_snapshot
else
  create_snapshot
fi
