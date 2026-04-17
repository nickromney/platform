#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: fix-hostname.sh [--dry-run] [--execute]

Repair /etc/hosts so localhost and container hostnames can be reached from Lima.

$(shell_cli_standard_options)
EOF
}

shell_cli_init_standard_flags
shell_cli_parse_standard_only usage "$@"

if [ "${SHELL_CLI_ARG_COUNT:-0}" -gt 0 ]; then
  set -- "${SHELL_CLI_ARGS[@]}"
  shell_cli_unexpected_arg "$1"
  exit 1
fi

if [ "${SHELL_CLI_DRY_RUN}" = "1" ] || [ "${SHELL_CLI_EXECUTE}" != "1" ]; then
  usage
  echo "INFO dry-run: would repair /etc/hosts for target-hostname mapping"
  exit 0
fi

target_cloud_name="${TARGET_CLOUD_NAME:-${CLOUD_NAME:-}}"

current_hostname="$(hostname)"

if awk -v hostname="${current_hostname}" -v target="${target_cloud_name}" '
  BEGIN { target_has_alias = (target != "")
  }
  $1 == "127.0.1.1" {
    for (i = 2; i <= NF; i++) {
      if ($i == hostname || (target_has_alias && $i == target)) {
        found = 1
        exit
      }
    }
  }
  END {
    if (found) exit 0
    exit 1
  }
' /etc/hosts; then
    exit 0
fi

desired_names="${current_hostname}"
if [ -n "${target_cloud_name}" ] && [ "${target_cloud_name}" != "${current_hostname}" ]; then
    desired_names="${desired_names} ${target_cloud_name}"
fi

append_entry() {
    printf '\n127.0.1.1 %s\n' "${desired_names}" >> /etc/hosts
}

if [ "$(id -u)" -eq 0 ]; then
    append_entry
else
    printf '\n127.0.1.1 %s\n' "${desired_names}" | sudo tee -a /etc/hosts >/dev/null
fi

echo "Repaired hostname mapping for ${current_hostname}" >&2
