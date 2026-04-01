#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: check-kind-stopped.sh [--dry-run] [--execute]

Checks whether the local kind cluster is still running and exits non-zero when
it would conflict with Lima or Slicer startup.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would check whether kind-local is still running" "$@"

if ! command -v docker >/dev/null 2>&1; then
  exit 0
fi

running_kind_nodes="$(
  docker ps --format '{{.Names}}' 2>/dev/null | \
    grep -E '^kind-local-(control-plane|worker([0-9]+)?)$' || true
)"

if [[ -z "${running_kind_nodes}" ]]; then
  exit 0
fi

echo "kind-local is still running." >&2
echo "Stop it before starting Lima or Slicer on this host:" >&2
echo "  make -C kubernetes/kind stop-kind" >&2
echo "" >&2
echo "Running kind containers:" >&2
while IFS= read -r container; do
  [[ -z "${container}" ]] && continue
  printf '  %s\n' "${container}" >&2
done <<< "${running_kind_nodes}"
exit 1
