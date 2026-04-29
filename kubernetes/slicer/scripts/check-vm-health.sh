#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/shell-cli.sh"

fail() { echo "FAIL $*" >&2; exit 1; }
ok() { echo "OK   $*"; }

slicer_url="${SLICER_URL:-${SLICER_SOCKET:-}}"
vm_name="${SLICER_VM_NAME:-slicer-1}"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Checks the configured Slicer VM for basic k3s, storage, and kernel health.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would check basic health signals for the configured Slicer VM" "$@"

[ -n "${slicer_url}" ] || fail "SLICER_URL or SLICER_SOCKET must be set"

vm_sh() {
  SLICER_URL="${slicer_url}" slicer vm exec "${vm_name}" -- "$1"
}

ok "checking ${vm_name}"

boot_epoch="$(vm_sh "awk '{print int(\$1)}' /proc/uptime" | tr -d '\r' | xargs)"
boot_human="$(vm_sh "uptime -s" | tr -d '\r')"
mem_line="$(vm_sh "free -h | awk 'NR==2 {print \$3\" used / \"\$2\" total, \"\$7\" available\"}'" | tr -d '\r')"
disk_line="$(vm_sh "df -h / | awk 'NR==2 {print \$3\" used / \"\$2\" total, \"\$4\" free\"}'" | tr -d '\r')"
swap_line="$(vm_sh "swapon --show --noheadings --bytes | awk '{sum+=\$3} END {if (sum == 0) print \"disabled\"; else printf \"%.1f GiB\", sum/1024/1024/1024}'" | tr -d '\r')"

echo "BOOT ${boot_human} (uptime ${boot_epoch}s)"
echo "MEM  ${mem_line}"
echo "DISK ${disk_line}"
echo "SWAP ${swap_line}"

if ! vm_sh "sudo systemctl is-active --quiet k3s"; then
  vm_sh "sudo systemctl status k3s --no-pager -l | tail -n 40" || true
  fail "k3s is not active"
fi
ok "k3s active"

if vm_sh "sudo dmesg | grep -Eiq 'EXT4-fs error|block bitmap corrupt|bit already cleared|deleted inode referenced'"; then
  vm_sh "sudo dmesg | grep -Ei 'EXT4-fs error|block bitmap corrupt|bit already cleared|deleted inode referenced' | tail -n 40" || true
  fail "ext4 corruption signals detected in dmesg"
fi
ok "no ext4 corruption signals in current boot dmesg"

if vm_sh "sudo dmesg | grep -Eiq 'Unable to handle kernel|Internal error: Oops|kernel panic|rcu: INFO: rcu_sched detected stalls'"; then
  vm_sh "sudo dmesg | grep -Ei 'Unable to handle kernel|Internal error: Oops|kernel panic|rcu: INFO: rcu_sched detected stalls' | tail -n 40" || true
  fail "kernel fault signals detected in dmesg"
fi
ok "no kernel fault signals in current boot dmesg"
