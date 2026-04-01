#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPT="$(cd "${SCRIPT_DIR}/../.." && pwd)/scripts/check-target-host-ports.sh"

ORIGINAL_ARGS=("$@")
TFVARS_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file)
      [[ $# -ge 2 ]] || break
      TFVARS_FILES+=("$2")
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

tfvar_get() {
  local key="$1"
  local fallback="$2"
  local file value="" match=""

  if [[ "${#TFVARS_FILES[@]}" -gt 0 ]]; then
    for file in "${TFVARS_FILES[@]}"; do
      [[ -f "${file}" ]] || continue
      match="$(
        grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | \
          sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true
      )"
      [[ -n "${match}" ]] || continue
      value="${match}"
    done
  fi

  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
  else
    printf '%s\n' "${fallback}"
  fi
}

EXPOSE_ADMIN_NODEPORTS="$(tfvar_get expose_admin_nodeports true)"
GATEWAY_LISTEN_ADDRESS="$(tfvar_get gateway_https_listen_address 127.0.0.1)"

PORT_CHECKS="$(cat <<EOF
gateway-https|${GATEWAY_LISTEN_ADDRESS}|gateway_https_host_port|443|gateway_https_node_port|30070
api-server|127.0.0.1|kind_api_server_port|6443|kind_api_server_port|6443
EOF
)"

if [[ "${EXPOSE_ADMIN_NODEPORTS}" == "true" ]]; then
  PORT_CHECKS+=$'\n'"$(cat <<'EOF'
argocd|127.0.0.1|argocd_server_node_port|30080|argocd_server_node_port|30080
hubble-ui|127.0.0.1|hubble_ui_node_port|31235|hubble_ui_node_port|31235
gitea-http|127.0.0.1|gitea_http_node_port|30090|gitea_http_node_port|30090
gitea-ssh|127.0.0.1|gitea_ssh_node_port|30022|gitea_ssh_node_port|30022
grafana-ui|127.0.0.1|grafana_ui_host_port|3302|grafana_ui_node_port|30302
EOF
)"
fi

TARGET_LABEL="kind" \
PORT_CHECKS="${PORT_CHECKS}" \
exec "${SHARED_SCRIPT}" "${ORIGINAL_ARGS[@]}"
