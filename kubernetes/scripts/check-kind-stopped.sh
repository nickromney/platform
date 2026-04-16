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

SHARED_CONFLICT_PORT_NUMBERS="443 30022 30080 30090 31235 3301 3302"

running_kind_nodes="$(
  docker ps --format '{{.Names}}' 2>/dev/null | \
    grep -E '^kind-local-(control-plane|worker([0-9]+)?)$' || true
)"

running_kind_ports="$(
  docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null | \
    awk -F '|' '$1 ~ /^kind-local-(control-plane|worker([0-9]+)?)$/ { print $2 }' | \
    tr ',' '\n' | \
    sed -nE 's/^[[:space:]]*([^[:space:],]+:[0-9]+)->.*$/\1/p' | \
    LC_ALL=C sort -u || true
)"

running_kind_conflicting_ports=""
running_kind_other_ports=""

while IFS= read -r host_port; do
  [[ -z "${host_port}" ]] && continue

  port_number="${host_port##*:}"
  case " ${SHARED_CONFLICT_PORT_NUMBERS} " in
    *" ${port_number} "*)
      running_kind_conflicting_ports+="${host_port}"$'\n'
      ;;
    *)
      running_kind_other_ports+="${host_port}"$'\n'
      ;;
  esac
done <<< "${running_kind_ports}"

if [[ -z "${running_kind_nodes}" ]]; then
  exit 0
fi

echo "kind-local is still running." >&2
echo "Stop it before starting Lima or Slicer on this host:" >&2
echo "  make -C kubernetes/kind stop-kind" >&2
echo "" >&2
if [[ -n "${running_kind_conflicting_ports}" ]]; then
  echo "Conflicting shared host ports for Lima/Slicer:" >&2
  while IFS= read -r host_port; do
    [[ -z "${host_port}" ]] && continue
    printf '  %s\n' "${host_port}" >&2
  done <<< "${running_kind_conflicting_ports}"
  echo "" >&2
fi
if [[ -n "${running_kind_other_ports}" ]]; then
  echo "Other published kind host ports:" >&2
  while IFS= read -r host_port; do
    [[ -z "${host_port}" ]] && continue
    printf '  %s\n' "${host_port}" >&2
  done <<< "${running_kind_other_ports}"
  echo "" >&2
fi
echo "Running kind containers:" >&2
while IFS= read -r container; do
  [[ -z "${container}" ]] && continue
  printf '  %s\n' "${container}" >&2
done <<< "${running_kind_nodes}"
exit 1
