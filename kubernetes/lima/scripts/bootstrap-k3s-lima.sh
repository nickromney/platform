#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${repo_root}/kubernetes/scripts/k3s-bootstrap-lib.sh"
# shellcheck source=/dev/null
source "${repo_root}/kubernetes/scripts/k3s-registries-lib.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Bootstraps or reconciles the Lima-backed k3s cluster and refreshes the managed
kubeconfig output.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would bootstrap or reconcile the Lima k3s cluster and refresh kubeconfig" "$@"

: "${LIMA_INSTANCE_PREFIX:?LIMA_INSTANCE_PREFIX is required}"
: "${DESIRED_NODES:?DESIRED_NODES is required}"

kubeconfig_helper="${KUBECONFIG_HELPER:-${repo_root}/terraform/kubernetes/scripts/manage-kubeconfig.sh}"
reconcile_kubeconfig="${RECONCILE_KUBECONFIG:-${repo_root}/kubernetes/scripts/reconcile-kubeconfig.sh}"
k3sup_context="${K3SUP_CONTEXT:-limavm-k3s}"
kubeconfig_path="${KUBECONFIG_PATH:-$HOME/.kube/${k3sup_context}.yaml}"
default_kubeconfig_path="${DEFAULT_KUBECONFIG_PATH:-$HOME/.kube/config}"
merge_kubeconfig_to_default="${MERGE_KUBECONFIG_TO_DEFAULT:-0}"
k3s_channel="${K3S_CHANNEL:-stable}"
k3s_version="${K3S_VERSION:-}"
server_extra_args="${K3S_SERVER_EXTRA_ARGS:---flannel-backend=none --disable-network-policy --disable=traefik --disable=servicelb}"
agent_extra_args="${K3S_AGENT_EXTRA_ARGS:-}"
lima_vm_user="${LIMA_VM_USER:-${USER}}"
image_list_file="${IMAGE_LIST_FILE:-}"
local_image_cache_host="${LOCAL_IMAGE_CACHE_HOST:-host.lima.internal:5002}"
local_image_cache_scheme="${LOCAL_IMAGE_CACHE_SCHEME:-http}"
gitea_registry_host="${GITEA_REGISTRY_HOST:-localhost:30090}"
gitea_registry_scheme="${GITEA_REGISTRY_SCHEME:-http}"
k3s_api_host_port="${LIMA_K3S_API_TUNNEL_PORT:-16443}"

k3sup_bin="$(k3s_bootstrap_find_client || true)"
if [ -z "$k3sup_bin" ]; then
  echo "Neither k3sup-pro nor k3sup was found. Install one with brew or arkade."
  exit 1
fi

bootstrap_client_name="$(basename "$k3sup_bin")"
if [ "$bootstrap_client_name" = "k3sup-pro" ]; then
  echo "Using k3sup-pro for bootstrap"
else
  echo "Using k3sup for bootstrap"
fi

lima_ssh_key="${HOME}/.lima/_config/user"
if [ ! -f "$lima_ssh_key" ]; then
  echo "Lima SSH key not found at ${lima_ssh_key}. Start a Lima VM first."
  exit 1
fi

limactl_no_agent() {
  env SSH_AUTH_SOCK= limactl "$@"
}

k3sup_no_agent() {
  env SSH_AUTH_SOCK= "${k3sup_bin}" "$@"
}

lima_exec() {
  local name="$1"; shift
  limactl_no_agent shell "$name" -- "$@"
}

configure_k3s_registries() {
  local name="$1"
  local service_name="$2"
  local payload=""

  payload="$(k3s_registries_render \
    --image-list "${image_list_file}" \
    --cache-host "${local_image_cache_host}" \
    --cache-scheme "${local_image_cache_scheme}" \
    --gitea-host "${gitea_registry_host}" \
    --gitea-scheme "${gitea_registry_scheme}")"

  [ -n "${payload}" ] || return 0

  lima_exec "$name" sudo mkdir -p /etc/rancher/k3s
  lima_exec "$name" bash -lc "cat <<'EOF' | sudo tee /tmp/registries.yaml >/dev/null
$(printf '%b' "${payload}")
EOF"

  if ! lima_exec "$name" sudo cmp -s /tmp/registries.yaml /etc/rancher/k3s/registries.yaml; then
    lima_exec "$name" sudo mv /tmp/registries.yaml /etc/rancher/k3s/registries.yaml
    if lima_exec "$name" systemctl is-active "${service_name}" >/dev/null 2>&1; then
      lima_exec "$name" sudo systemctl restart "${service_name}"
      for _ in $(seq 1 60); do
        if lima_exec "$name" systemctl is-active "${service_name}" >/dev/null 2>&1; then
          break
        fi
        sleep 2
      done
    fi
  else
    lima_exec "$name" sudo rm -f /tmp/registries.yaml
  fi
}

get_vm_ssh_port() {
  local name="$1"
  limactl_no_agent list 2>/dev/null | awk -v n="$name" '$1==n {split($3, parts, ":"); print parts[2]; exit}'
}

agent_can_reach_server_api() {
  local agent_name="$1"
  local server_ip="$2"
  limactl_no_agent shell "$agent_name" -- bash -lc "nc -z -w 3 ${server_ip} 6443 >/dev/null 2>&1"
}

get_vm_ip() {
  local name="$1"
  limactl_no_agent shell "$name" -- ip route get 1.1.1.1 2>/dev/null | awk '/src/ {print $7; exit}'
}

get_k3s_status() {
  local name="$1"
  lima_exec "$name" systemctl is-active k3s 2>/dev/null | tr -d '\n' || echo "inactive"
}

get_k3s_agent_status() {
  local name="$1"
  lima_exec "$name" systemctl is-active k3s-agent 2>/dev/null | tr -d '\n' || echo "inactive"
}

get_node_count() {
  local name="$1"
  local count
  if count="$(lima_exec "$name" sudo k3s kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d '[:space:]')" \
    && [[ "$count" =~ ^[0-9]+$ ]]; then
    echo "$count"
  else
    echo 0
  fi
}

reconcile_default_kubeconfig() {
  local source_kubeconfig="$1"
  local target_kubeconfig="$2"

  [ -x "$reconcile_kubeconfig" ] || return 0
  "$reconcile_kubeconfig" \
    --execute \
    --source-kubeconfig "$source_kubeconfig" \
    --target-kubeconfig "$target_kubeconfig" \
    --context "$k3sup_context" \
    --merge "$merge_kubeconfig_to_default" \
    --helper "$kubeconfig_helper" \
    --fallback-merge
}

write_kubeconfig_from_server() {
  local node_name="$1"
  local api_host="$2"
  local tmp_file rendered

  tmp_file="$(mktemp)"
  rendered="$(lima_exec "$node_name" sudo cat /etc/rancher/k3s/k3s.yaml 2>/dev/null || true)"
  if [ -z "${rendered}" ]; then
    rm -f "$tmp_file"
    return 1
  fi

  rendered="$(printf '%s\n' "${rendered}" | sed -E "s#https://127\\.0\\.0\\.1:6443#https://${api_host}:${k3s_api_host_port}#g")"
  printf '%s\n' "${rendered}" >"${tmp_file}"
  chmod 600 "${tmp_file}"
  mv "${tmp_file}" "${kubeconfig_path}"
  kubectl config rename-context default "${k3sup_context}" --kubeconfig "${kubeconfig_path}" >/dev/null 2>&1 || true
  kubectl config use-context "${k3sup_context}" --kubeconfig "${kubeconfig_path}" >/dev/null 2>&1 || true
}

echo "Resolving VM IPs..."
nodes=()
ips=()
for i in $(seq 1 "$DESIRED_NODES"); do
  name="${LIMA_INSTANCE_PREFIX}-${i}"
  ip="$(get_vm_ip "$name")"
  if [ -z "$ip" ] || [ "$ip" = "-" ]; then
    echo "Could not determine IP for ${name}"
    exit 1
  fi
  nodes+=("$name")
  ips+=("$ip")
  echo "  ${name}: ${ip}"
done

for i in "${!nodes[@]}"; do
  service_name="k3s-agent"
  if [ "$i" -eq 0 ]; then
    service_name="k3s"
  fi
  configure_k3s_registries "${nodes[$i]}" "${service_name}"
done

server_node="${nodes[0]}"
server_ip="${ips[0]}"
server_ssh_port="$(get_vm_ssh_port "$server_node")"
server_connect_host="$server_ip"
server_tls_san="$server_ip"

if [ "$DESIRED_NODES" = "1" ]; then
  server_connect_host="127.0.0.1"
  server_tls_san="127.0.0.1"
fi

if [[ "$server_extra_args" != *"--tls-san ${server_tls_san}"* ]] && [[ "$server_extra_args" != *"--tls-san=${server_tls_san}"* ]]; then
  server_extra_args="${server_extra_args} --tls-san ${server_tls_san}"
fi

read -r -a channel_args <<<"$(k3s_bootstrap_channel_args "$k3s_channel" "$k3s_version")"

mkdir -p "$(dirname "$kubeconfig_path")"

if [ "$(get_k3s_status "$server_node")" = "active" ]; then
  actual_count="$(get_node_count "$server_node")"
  if [ "${actual_count:-0}" -ge "$DESIRED_NODES" ]; then
    echo "k3s cluster already running on ${server_node} with ${actual_count}/${DESIRED_NODES} nodes. Refreshing kubeconfig."
    if ! write_kubeconfig_from_server "$server_node" "$server_connect_host"; then
      echo "Could not refresh kubeconfig from ${server_node}" >&2
      exit 1
    fi
    reconcile_default_kubeconfig "$kubeconfig_path" "$default_kubeconfig_path"
    echo "kubeconfig updated: KUBECONFIG=${kubeconfig_path}"
    kubectl get nodes -o wide --kubeconfig "$kubeconfig_path" 2>/dev/null || true
    exit 0
  fi
  echo "k3s server running but only ${actual_count:-0}/${DESIRED_NODES} nodes. Will attempt to join missing agents."
fi

if [ "$(get_k3s_status "$server_node")" != "active" ]; then
  echo "Installing k3s server on ${server_node} (${server_ip})"
  echo "Server extra args: ${server_extra_args}"
  install_cmd=(
    install
    --ip "$server_connect_host"
    --ssh-port "$server_ssh_port"
    --user "$lima_vm_user"
    --ssh-key "$lima_ssh_key"
    "${channel_args[@]}"
    --k3s-extra-args "$server_extra_args"
    --context "$k3sup_context"
    --local-path "$kubeconfig_path"
  )
  k3sup_no_agent "${install_cmd[@]}"
else
  echo "k3s server already active on ${server_node}, skipping install"
fi

for i in "${!nodes[@]}"; do
  [ "$i" -eq 0 ] && continue
  agent_node="${nodes[$i]}"
  agent_ip="${ips[$i]}"
  agent_ssh_port="$(get_vm_ssh_port "$agent_node")"

  if [ "$(get_k3s_agent_status "$agent_node")" = "active" ]; then
    echo "k3s-agent already active on ${agent_node}, skipping join"
    continue
  fi

  if ! agent_can_reach_server_api "$agent_node" "$server_ip"; then
    echo "Agent ${agent_node} cannot reach ${server_ip}:6443 on the current Lima network."
    echo "Use DESIRED_NODES=1 (default) or configure a shared/bridged Lima network for inter-VM k3s traffic."
    exit 1
  fi

  echo "Joining agent ${agent_node} (${agent_ip})"
  join_cmd=(
    join
    --ip "127.0.0.1"
    --ssh-port "$agent_ssh_port"
    --user "$lima_vm_user"
    --ssh-key "$lima_ssh_key"
    --server-ip "$server_ip"
    --server-user "$lima_vm_user"
    "${channel_args[@]}"
  )
  if [ -n "$agent_extra_args" ]; then
    join_cmd+=(--k3s-extra-args "$agent_extra_args")
  fi
  k3s_bootstrap_run_with_timeout 180 k3sup_no_agent "${join_cmd[@]}"
done

nodes_ready=0
for _ in $(seq 1 90); do
  node_count="$(get_node_count "$server_node")"
  if [ "${node_count:-0}" -ge "$DESIRED_NODES" ]; then
    nodes_ready=1
    break
  fi
  sleep 2
done
if [ "$nodes_ready" != "1" ]; then
  echo "Timed out waiting for all ${DESIRED_NODES} k3s nodes"
  lima_exec "$server_node" sudo k3s kubectl get nodes -o wide 2>/dev/null || true
  exit 1
fi

if ! write_kubeconfig_from_server "$server_node" "$server_connect_host"; then
  echo "Could not read kubeconfig back from ${server_node}" >&2
  exit 1
fi

reconcile_default_kubeconfig "$kubeconfig_path" "$default_kubeconfig_path"

echo "k3s cluster bootstrapped. KUBECONFIG=${kubeconfig_path}"
kubectl get nodes -o wide --kubeconfig "$kubeconfig_path" 2>/dev/null || true
