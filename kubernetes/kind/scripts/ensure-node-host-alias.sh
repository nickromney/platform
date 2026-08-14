#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind-local}"
HOST_ALIAS="${KIND_NODE_HOST_ALIAS:-host.docker.internal}"
DOCKER_NETWORK="${KIND_DOCKER_NETWORK:-kind}"
CHECK_ONLY=0

usage() {
  cat <<EOF
Usage: ${0##*/} [--name <cluster-name>] [--alias <hostname>] [--check] [--dry-run] [--execute]

Ensures ${HOST_ALIAS} resolves to the host from inside the kind nodes.

With --check the nodes are only reported on, never modified. Diagnostics use
this so a missing alias is named directly rather than surfacing later as
unexplained ImagePullBackOff pods. It reports and exits 0 either way.

Docker Desktop injects that name automatically; Docker Engine on Linux does
not. The platform points the host-local registry and several image references
at it, so without the alias containerd cannot pull them and pods land in
ImagePullBackOff.

The alias is mapped to the IPv4 gateway of the "${DOCKER_NETWORK}" Docker
network, which is the host as seen from the node containers. Nodes that already
resolve the name are left untouched, so this is safe to rerun and a no-op on
Docker Desktop.

$(shell_cli_standard_options)
EOF
}

warn() { echo "WARN $*" >&2; }
ok() { echo "OK   $*"; }

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --name)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--name"; exit 1; }
      CLUSTER_NAME="$2"
      shift 2
      ;;
    --alias)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "$(shell_cli_script_name)" "--alias"; exit 1; }
      HOST_ALIAS="$2"
      shift 2
      ;;
    --check)
      CHECK_ONLY=1
      shift
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 1
      ;;
  esac
done

# --check never writes, so it does not need the --execute confirmation gate.
if [[ "${CHECK_ONLY}" -eq 0 ]]; then
  shell_cli_maybe_execute_or_preview_summary usage \
    "would ensure ${HOST_ALIAS} resolves inside the ${CLUSTER_NAME} kind nodes"
fi

command -v docker >/dev/null 2>&1 || { warn "docker not found in PATH; skipping host alias check"; exit 0; }
command -v kind >/dev/null 2>&1 || { warn "kind not found in PATH; skipping host alias check"; exit 0; }

nodes="$(kind get nodes --name "${CLUSTER_NAME}" 2>/dev/null || true)"
if [[ -z "${nodes}" ]]; then
  warn "no nodes found for kind cluster ${CLUSTER_NAME}; skipping host alias check"
  exit 0
fi

# Only the IPv4 gateway is useful here: the registry publishes on 0.0.0.0, and
# a dual-stack kind network reports the IPv6 gateway first.
gateway="$(docker network inspect "${DOCKER_NETWORK}" \
  -f '{{range .IPAM.Config}}{{.Gateway}}{{"\n"}}{{end}}' 2>/dev/null |
  grep -E '^[0-9]+\.' | head -n 1 || true)"

patched=0
skipped=0
missing=0
for node in ${nodes}; do
  if docker exec "${node}" getent hosts "${HOST_ALIAS}" >/dev/null 2>&1; then
    skipped=$((skipped + 1))
    continue
  fi

  if [[ "${CHECK_ONLY}" -eq 1 ]]; then
    missing=$((missing + 1))
    continue
  fi

  if [[ -z "${gateway}" ]]; then
    warn "could not determine an IPv4 gateway for the ${DOCKER_NETWORK} network; ${HOST_ALIAS} will not resolve in ${node}"
    continue
  fi

  if docker exec "${node}" sh -c "printf '%s %s\n' '${gateway}' '${HOST_ALIAS}' >> /etc/hosts" 2>/dev/null; then
    patched=$((patched + 1))
  else
    warn "could not add ${HOST_ALIAS} to /etc/hosts in ${node}"
  fi
done

if [[ "${patched}" -gt 0 ]]; then
  ok "${HOST_ALIAS} -> ${gateway} added to ${patched} kind node(s)"
fi
if [[ "${skipped}" -gt 0 ]]; then
  ok "${HOST_ALIAS} already resolves in ${skipped} kind node(s)"
fi
if [[ "${missing}" -gt 0 ]]; then
  warn "${HOST_ALIAS} does not resolve in ${missing} kind node(s); images referencing it cannot be pulled"
  warn "repair: make -C kubernetes/kind ensure-node-host-alias"
fi
