#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_SCRIPT="$(cd "${SCRIPT_DIR}/../.." && pwd)/scripts/check-target-host-ports.sh"

TARGET_LABEL="slicer" \
PORT_CHECKS="$(cat <<'EOF'
gateway-https|127.0.0.1|gateway_https_host_port|8443|gateway_https_node_port|30070
argocd|127.0.0.1|argocd_server_node_port|30080|argocd_server_node_port|30080
hubble-ui|127.0.0.1|hubble_ui_node_port|31235|hubble_ui_node_port|31235
gitea-http|127.0.0.1|gitea_http_node_port|30090|gitea_http_node_port|30090
gitea-ssh|127.0.0.1|gitea_ssh_node_port|30022|gitea_ssh_node_port|30022
signoz-ui|127.0.0.1|signoz_ui_host_port|3301|signoz_ui_node_port|30301
grafana-ui|127.0.0.1|grafana_ui_host_port|3302|grafana_ui_node_port|30302
EOF
)" \
exec "${SHARED_SCRIPT}" "$@"
