#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPT="$(cd "${SCRIPT_DIR}/../.." && pwd)/scripts/check-target-host-ports.sh"

TARGET_LABEL="kind" \
PORT_CHECKS="$(cat <<'EOF'
gateway-https|127.0.0.1|gateway_https_host_port|443|gateway_https_node_port|30070
argocd|127.0.0.1|argocd_server_node_port|30080|argocd_server_node_port|30080
hubble-ui|127.0.0.1|hubble_ui_node_port|31235|hubble_ui_node_port|31235
gitea-http|127.0.0.1|gitea_http_node_port|30090|gitea_http_node_port|30090
gitea-ssh|127.0.0.1|gitea_ssh_node_port|30022|gitea_ssh_node_port|30022
grafana-ui|127.0.0.1|grafana_ui_host_port|3302|grafana_ui_node_port|30302
api-server|127.0.0.1|kind_api_server_port|6443|kind_api_server_port|6443
EOF
)" \
exec "${SHARED_SCRIPT}" "$@"
