#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEW_SCRIPT="${SCRIPT_DIR}/hubble-observe-cilium-policies.sh"

if [[ ! -x "${NEW_SCRIPT}" ]]; then
  echo "hubble-audit-cilium-policies.sh: expected renamed script at ${NEW_SCRIPT}" >&2
  exit 1
fi

echo "hubble-audit-cilium-policies.sh: renamed to hubble-observe-cilium-policies.sh; forwarding" >&2
SHELL_CLI_SCRIPT_NAME_OVERRIDE="${0##*/}" exec "${NEW_SCRIPT}" "$@"
