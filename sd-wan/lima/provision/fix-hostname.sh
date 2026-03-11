#!/bin/bash
set -euo pipefail

target_cloud_name="${1:-${TARGET_CLOUD_NAME:-${CLOUD_NAME:-}}}"
current_hostname="$(hostname)"

if grep -Eq "(^|[[:space:]])${current_hostname}([[:space:]]|$)" /etc/hosts; then
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
