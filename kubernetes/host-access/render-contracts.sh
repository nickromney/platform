#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VARIANTS_DIR="${VARIANTS_DIR:-${REPO_ROOT}/kubernetes/variants}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Projects the host access path contract from kubernetes/variants/*/variant.json.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would project host access path contracts from ${VARIANTS_DIR}" "$@"

contracts=()
while IFS= read -r contract; do
  contracts+=("${contract}")
done < <(find "${VARIANTS_DIR}" -mindepth 2 -maxdepth 2 -name variant.json -type f | LC_ALL=C sort)

if [[ "${#contracts[@]}" -eq 0 ]]; then
  echo "No variant contracts found under ${VARIANTS_DIR}" >&2
  exit 1
fi

jq -s '
  def required_processes($host_access_path):
    [
      if $host_access_path.requires_proxy then "proxy" else empty end,
      if $host_access_path.requires_forward_process then "forward" else empty end
    ];

  {
    schema_version: "platform.host_access_paths/v1",
    source_schema_version: "platform.variant/v1",
    source: "kubernetes/variants/*/variant.json",
    variants: [
      .[]
      | {
          id,
          path,
          mode: .host_access_path.mode,
          gateway_host_port: .host_access_path.gateway_host_port,
          gateway_forward_port: .host_access_path.gateway_forward_port,
          gateway_target_port: .host_access_path.gateway_target_port,
          shared_host_ports: .host_access_path.shared_host_ports,
          requires_proxy: .host_access_path.requires_proxy,
          requires_forward_process: .host_access_path.requires_forward_process,
          required_processes: required_processes(.host_access_path),
          can_degrade: .host_access_path.can_degrade
        }
    ]
  }
' "${contracts[@]}"
