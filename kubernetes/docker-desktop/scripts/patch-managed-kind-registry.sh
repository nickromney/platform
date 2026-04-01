#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../../scripts/lib/shell-cli.sh"

context="docker-desktop"
node_pattern='^desktop-'
restart_workloads="false"
registries=(
  "host.docker.internal:5002"
  "192.168.65.254:5002"
)

usage() {
  cat <<'EOF'
Usage: patch-managed-kind-registry.sh [options]

Patch Docker Desktop managed kind nodes so containerd can pull local workload
images directly instead of forcing them through Docker Desktop's broken
registry-mirror fallback for local registries.

Options:
  --context NAME           kubeconfig context to wait on (default: docker-desktop)
  --node-pattern REGEX     docker container name regex for managed nodes
                           (default: ^desktop-)
  --registry HOST:PORT     add another plain-http registry override
  --restart-workloads      rollout-restart app deployments in dev/uat/apim
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --context)
      [[ $# -ge 2 ]] || { echo "--context requires a value" >&2; exit 1; }
      context="$2"
      shift 2
      ;;
    --node-pattern)
      [[ $# -ge 2 ]] || { echo "--node-pattern requires a value" >&2; exit 1; }
      node_pattern="$2"
      shift 2
      ;;
    --registry)
      [[ $# -ge 2 ]] || { echo "--registry requires a value" >&2; exit 1; }
      registries+=("$2")
      shift 2
      ;;
    --restart-workloads)
      restart_workloads="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  shell_cli_print_dry_run_summary "would patch Docker Desktop managed kind nodes for direct local registry pulls"
  exit 0
fi

nodes=()
while IFS= read -r node; do
  [[ -n "$node" ]] || continue
  nodes+=("$node")
done < <(docker ps --format '{{.Names}}' | grep -E "${node_pattern}" | sort || true)

if [[ ${#nodes[@]} -eq 0 ]]; then
  echo "No managed Docker Desktop kind nodes matched ${node_pattern}" >&2
  exit 1
fi

echo "Patching registries on nodes: ${nodes[*]}"

for node in "${nodes[@]}"; do
  echo "==> ${node}"
  for registry in "${registries[@]}"; do
    echo "  - ${registry}"
    docker exec -e REGISTRY="${registry}" "${node}" sh -lc '
set -eu
dir="/etc/containerd/certs.d/${REGISTRY}"
mkdir -p "${dir}"
cat > "${dir}/hosts.toml" <<EOF
server = "http://${REGISTRY}"

[host."http://${REGISTRY}"]
capabilities = ["pull", "resolve"]
skip_verify = true
EOF
'
  done
  docker exec "${node}" sh -lc 'set -eu; systemctl restart containerd; systemctl is-active containerd'
done

kubectl --context "${context}" wait --for=condition=Ready nodes --all --timeout=180s >/dev/null
echo "All nodes are Ready in context ${context}"

if [[ "${restart_workloads}" == "true" ]]; then
  for ns in dev uat apim; do
    if kubectl --context "${context}" get namespace "${ns}" >/dev/null 2>&1; then
      if kubectl --context "${context}" -n "${ns}" get deployment >/dev/null 2>&1; then
        echo "Restarting deployments in namespace ${ns}"
        kubectl --context "${context}" -n "${ns}" rollout restart deployment >/dev/null
      fi
    fi
  done
fi

echo "Done."
