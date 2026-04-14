#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "${script_dir}/../../.." && pwd)"
run_dir="${RUN_DIR:-$(cd "${script_dir}/.." && pwd)/.run}"
# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: bootstrap-k3s-slicer.sh [--dry-run] [--execute]

Bootstraps or reconciles the Slicer-backed k3s cluster and refreshes the
managed kubeconfig output.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would bootstrap or reconcile the Slicer k3s cluster and refresh kubeconfig" "$@"

slicer_socket="${SLICER_URL:-${SLICER_SOCKET:-}}"
[ -n "${slicer_socket}" ] || { echo "ERROR: SLICER_URL or SLICER_SOCKET must be set" >&2; exit 1; }

kubeconfig_helper="${KUBECONFIG_HELPER:-${repo_root}/terraform/kubernetes/scripts/manage-kubeconfig.sh}"
server_vm="${SLICER_VM_NAME:-slicer-1}"
slicer_vm_user="${SLICER_VM_USER:-ubuntu}"
k3sup_context="${K3SUP_CONTEXT:-slicer-k3s}"
kubeconfig_path="${KUBECONFIG_PATH:-${HOME}/.kube/${k3sup_context}.yaml}"
default_kubeconfig_path="${DEFAULT_KUBECONFIG_PATH:-${HOME}/.kube/config}"
k3s_version="${K3S_VERSION:-}"
k3s_channel="${K3S_CHANNEL:-stable}"
server_extra_args="${K3S_SERVER_EXTRA_ARGS:---flannel-backend=none --disable-network-policy --disable=traefik --disable=servicelb}"
merge_kubeconfig_to_default="${MERGE_KUBECONFIG_TO_DEFAULT:-0}"
swap_size="${SLICER_SWAP_SIZE:-4G}"
allow_existing_k3s="${SLICER_ALLOW_EXISTING_K3S:-0}"
image_list_file="${IMAGE_LIST_FILE:-}"
local_image_cache_host="${LOCAL_IMAGE_CACHE_HOST:-}"
local_image_cache_scheme="${LOCAL_IMAGE_CACHE_SCHEME:-http}"
bootstrap_key="${K3SUP_BOOTSTRAP_KEY:-${run_dir}/${server_vm}-k3sup-bootstrap}"
bootstrap_pub="${bootstrap_key}.pub"

[[ "${allow_existing_k3s}" =~ ^(0|1)$ ]] || { echo "ERROR: SLICER_ALLOW_EXISTING_K3S must be 0 or 1" >&2; exit 1; }

find_bootstrap_client() {
  local candidate

  for candidate in \
    "${K3SUP_PRO_BIN:-}" \
    "$(command -v k3sup-pro 2>/dev/null || true)" \
    "${K3SUP_BIN:-}" \
    "$(command -v k3sup 2>/dev/null || true)" \
    "$HOME/.arkade/bin/k3sup"; do
    [ -n "$candidate" ] || continue
    [ -x "$candidate" ] || continue
    echo "$candidate"
    return 0
  done

  return 1
}

desired_network_profile() {
  if [[ "${server_extra_args}" == *"--flannel-backend=none"* ]]; then
    echo "cilium"
  else
    echo "default"
  fi
}

vm_exec() {
  local vm="$1"; shift
  SLICER_URL="$slicer_socket" slicer vm exec "$vm" -- "$@"
}

run_with_timeout() {
  local seconds="$1"
  shift
  local pid=""
  local start=""
  local elapsed=""
  local rc=0

  if command -v timeout >/dev/null 2>&1; then
    timeout "${seconds}" "$@"
    return $?
  fi

  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${seconds}" "$@"
    return $?
  fi

  "$@" &
  pid=$!
  start="$(date +%s)"

  while kill -0 "${pid}" >/dev/null 2>&1; do
    elapsed=$(( $(date +%s) - start ))
    if [ "${elapsed}" -ge "${seconds}" ]; then
      kill "${pid}" >/dev/null 2>&1 || true
      wait "${pid}" >/dev/null 2>&1 || true
      return 124
    fi
    sleep 1
  done

  wait "${pid}" || rc=$?
  return "${rc}"
}

vm_exec_retry() {
  local vm="$1" cmd="$2" max="${3:-8}" wait="${4:-3}"
  local output
  for _ in $(seq 1 "$max"); do
    output="$(SLICER_URL="$slicer_socket" slicer vm exec "$vm" -- "$cmd" 2>&1)" && { printf '%s\n' "$output"; return 0; }
    if printf '%s' "$output" | grep -Eiq '502 Bad Gateway|transport|EOF|i/o timeout|Connection reset|timed out'; then
      sleep "$wait"
      continue
    fi
    printf '%s\n' "$output" >&2
    return 1
  done
  printf '%s\n' "$output" >&2
  return 1
}

vm_cp() {
  local src="$1" dst="$2" max="${3:-5}" wait="${4:-3}"
  for _ in $(seq 1 "$max"); do
    SLICER_URL="$slicer_socket" slicer vm cp "$src" "$dst" >/dev/null 2>&1 && return 0
    sleep "$wait"
  done
  return 1
}

wait_for_vm() {
  echo "Waiting for ${server_vm}..."
  SLICER_URL="$slicer_socket" slicer vm ready "$server_vm" --timeout 180s >/dev/null
}

get_vm_ip() {
  SLICER_URL="$slicer_socket" slicer vm list --json | jq -r --arg vm "${server_vm}" '.[] | select(.hostname == $vm) | .ip'
}

wait_for_kube_api() {
  local attempts="${1:-45}" delay="${2:-2}"
  for _ in $(seq 1 "$attempts"); do
    if KUBECONFIG="$kubeconfig_path" kubectl --context "$k3sup_context" --request-timeout=5s get --raw=/version >/dev/null 2>&1; then
      return 0
    fi
    sleep "$delay"
  done
  return 1
}

remote_k3s_api_ready() {
  local max="${1:-8}" wait="${2:-3}"
  vm_exec_retry \
    "$server_vm" \
    "sudo test -x /usr/local/bin/k3s && sudo test -f /etc/rancher/k3s/k3s.yaml && sudo /usr/local/bin/k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml get --raw=/version" \
    "$max" \
    "$wait" >/dev/null
}

existing_k3s_network_profile() {
  local execstart
  execstart="$(vm_exec_retry "$server_vm" "sudo systemctl show -p ExecStart --value k3s" 3 2 | tr -d '\r' || true)"
  if [[ -z "${execstart}" ]]; then
    echo ""
    return 0
  fi

  if [[ "${execstart}" == *"--flannel-backend=none"* ]]; then
    echo "cilium"
  else
    echo "default"
  fi
}

validate_existing_k3s_network_profile() {
  local desired_profile current_profile
  desired_profile="$(desired_network_profile)"
  current_profile="$(existing_k3s_network_profile)"

  [[ -n "${current_profile}" ]] || return 0

  if [[ "${desired_profile}" != "${current_profile}" ]]; then
    echo "ERROR: existing k3s on ${server_vm} uses networking profile=${current_profile}, but requested profile=${desired_profile}." >&2
    echo "Reset the VM before switching SLICER_NETWORK_PROFILE or K3S_SERVER_EXTRA_ARGS." >&2
    exit 1
  fi
}

fix_vm_dns() {
  local gw
  local current_nameserver=""
  gw="$(vm_exec_retry "$server_vm" "ip -4 route list 0/0 | awk '{print \$3}' | head -n1" 5 2 | tr -d '\r' | head -n1 || true)"
  if [ -z "$gw" ]; then
    echo "WARN: unable to detect gateway for ${server_vm}; skipping DNS override" >&2
    return 0
  fi
  echo "==> Setting ${server_vm} DNS to gateway resolver (${gw})"
  if ! vm_exec_retry "$server_vm" "sudo chattr -i /etc/resolv.conf || true; printf 'nameserver ${gw}\noptions timeout:1 attempts:2\n' | sudo tee /etc/resolv.conf >/dev/null; sudo chattr +i /etc/resolv.conf || true" 5 2 >/dev/null; then
    current_nameserver="$(vm_exec_retry "$server_vm" "awk '/^nameserver[[:space:]]+/ {print \$2; exit}' /etc/resolv.conf" 2 1 | tr -d '\r' | head -n1 || true)"
    if [ "${current_nameserver}" = "${gw}" ]; then
      echo "INFO: ${server_vm} already points at gateway resolver ${gw}; continuing" >&2
    else
      echo "INFO: could not pin ${server_vm} DNS to gateway resolver ${gw}; continuing with the guest default resolver (${current_nameserver:-unknown})" >&2
    fi
  fi
}

remove_context_from_default_kubeconfig() {
  [ -e "${default_kubeconfig_path}" ] || return 0
  [ -x "${kubeconfig_helper}" ] || return 0

  "${kubeconfig_helper}" --execute --action ensure-valid --kubeconfig "${default_kubeconfig_path}"
  "${kubeconfig_helper}" \
    --execute \
    --action delete-context \
    --kubeconfig "${default_kubeconfig_path}" \
    --context "${k3sup_context}" \
    --cluster "${k3sup_context}" \
    --user "${k3sup_context}"
}

refresh_kubeconfig() {
  local vm_ip="$1"
  local tmp_path="${kubeconfig_path}.tmp"

  mkdir -p "$(dirname "$kubeconfig_path")"
  vm_cp "${server_vm}:/etc/rancher/k3s/k3s.yaml" "$tmp_path" 10 2

  sed -e "s/127\\.0\\.0\\.1/${vm_ip}/g" -e "s/localhost/${vm_ip}/g" "$tmp_path" > "$kubeconfig_path"
  rm -f "$tmp_path"
  chmod 600 "$kubeconfig_path" || true

  if command -v kubectl >/dev/null 2>&1; then
    local current_ctx
    current_ctx="$(KUBECONFIG="$kubeconfig_path" kubectl config current-context 2>/dev/null || true)"
    if [ -n "$current_ctx" ] && [ "$current_ctx" != "$k3sup_context" ]; then
      KUBECONFIG="$kubeconfig_path" kubectl config rename-context "$current_ctx" "$k3sup_context" >/dev/null 2>&1 || true
    fi
    KUBECONFIG="$kubeconfig_path" kubectl config use-context "$k3sup_context" >/dev/null 2>&1 || true
    if [ "$merge_kubeconfig_to_default" = "1" ]; then
      mkdir -p "$(dirname "$default_kubeconfig_path")"
      if [ -x "$kubeconfig_helper" ]; then
        if ! "$kubeconfig_helper" \
          --execute \
          --action merge \
          --source-kubeconfig "$kubeconfig_path" \
          --target-kubeconfig "$default_kubeconfig_path" \
          --context "$k3sup_context"; then
          echo "WARN: failed to merge ${kubeconfig_path} into ${default_kubeconfig_path}" >&2
        fi
      else
        local merged_kubeconfig
        merged_kubeconfig="${default_kubeconfig_path}.merged.$$"
        if [ -s "$default_kubeconfig_path" ]; then
          if KUBECONFIG="${default_kubeconfig_path}:${kubeconfig_path}" kubectl config view --flatten > "$merged_kubeconfig"; then
            chmod 600 "$merged_kubeconfig" || true
            mv "$merged_kubeconfig" "$default_kubeconfig_path"
          else
            rm -f "$merged_kubeconfig"
            echo "WARN: failed to merge ${kubeconfig_path} into ${default_kubeconfig_path}" >&2
          fi
        else
          cp "$kubeconfig_path" "$default_kubeconfig_path"
        fi
      fi
      kubectl config use-context "$k3sup_context" >/dev/null 2>&1 || true
    else
      remove_context_from_default_kubeconfig
    fi
  fi
}

registry_for_image_ref() {
  local ref="${1%%@*}"
  local first

  if [[ "${ref}" != */* ]]; then
    echo "docker.io"
    return 0
  fi

  first="${ref%%/*}"
  if [[ "${first}" == *.* || "${first}" == *:* || "${first}" == "localhost" ]]; then
    echo "${first}"
  else
    echo "docker.io"
  fi
}

default_endpoint_for_registry() {
  case "$1" in
    docker.io)
      echo "https://registry-1.docker.io"
      ;;
    *)
      echo "https://$1"
      ;;
  esac
}

platform_mirror_registries() {
  [ -n "${image_list_file}" ] || return 0
  [ -f "${image_list_file}" ] || return 0

  while IFS= read -r image; do
    [[ -z "${image}" || "${image}" =~ ^# ]] && continue
    registry_for_image_ref "${image}"
  done < "${image_list_file}" | awk 'NF { print }' | sort -u
}

configure_k3s_registries() {
  local payload=""
  local registry=""
  local tmp_file

  [ -n "${local_image_cache_host}" ] || return 0

  append_mirror_entry() {
    local mirror_name="$1"
    shift

    if [[ "${payload}" != mirrors:* ]]; then
      payload+="mirrors:\n"
    fi

    payload+="  \"${mirror_name}\":\n"
    payload+="    endpoint:\n"
    while [[ $# -gt 0 ]]; do
      payload+="      - \"$1\"\n"
      shift
    done
  }

  append_mirror_entry "${local_image_cache_host}" "${local_image_cache_scheme}://${local_image_cache_host}"
  while IFS= read -r registry; do
    [[ -n "${registry}" ]] || continue
    append_mirror_entry \
      "${registry}" \
      "${local_image_cache_scheme}://${local_image_cache_host}" \
      "$(default_endpoint_for_registry "${registry}")"
  done < <(platform_mirror_registries)

  tmp_file="$(mktemp)"
  printf '%b' "${payload}" > "${tmp_file}"
  vm_cp "${tmp_file}" "${server_vm}:/tmp/registries.yaml" 10 2
  rm -f "${tmp_file}"

  vm_exec_retry "${server_vm}" "sudo mkdir -p /etc/rancher/k3s; if ! sudo cmp -s /tmp/registries.yaml /etc/rancher/k3s/registries.yaml 2>/dev/null; then sudo mv /tmp/registries.yaml /etc/rancher/k3s/registries.yaml; sudo systemctl is-active --quiet k3s && sudo systemctl restart k3s || true; else rm -f /tmp/registries.yaml; fi" 5 2 >/dev/null
}

ensure_bootstrap_keypair() {
  mkdir -p "${run_dir}"

  if [ -f "${bootstrap_key}" ] && [ -f "${bootstrap_pub}" ]; then
    return 0
  fi

  rm -f "${bootstrap_key}" "${bootstrap_pub}"
  ssh-keygen -t ed25519 -N "" -f "${bootstrap_key}" -C "k3sup bootstrap for ${server_vm}" >/dev/null
  chmod 600 "${bootstrap_key}" || true
}

authorize_bootstrap_key() {
  vm_exec_retry "${server_vm}" "sudo install -d -m 700 -o ${slicer_vm_user} -g ${slicer_vm_user} /home/${slicer_vm_user}/.ssh && sudo touch /home/${slicer_vm_user}/.ssh/authorized_keys && sudo chmod 600 /home/${slicer_vm_user}/.ssh/authorized_keys && sudo chown ${slicer_vm_user}:${slicer_vm_user} /home/${slicer_vm_user}/.ssh/authorized_keys" 5 2 >/dev/null
  vm_cp "${bootstrap_pub}" "${server_vm}:/tmp/k3sup-bootstrap.pub" 10 2
  vm_exec_retry "${server_vm}" "sudo -u ${slicer_vm_user} bash -lc 'grep -qxF \"\$(cat /tmp/k3sup-bootstrap.pub)\" ~/.ssh/authorized_keys || cat /tmp/k3sup-bootstrap.pub >> ~/.ssh/authorized_keys'" 5 2 >/dev/null
  vm_exec_retry "${server_vm}" "rm -f /tmp/k3sup-bootstrap.pub" 3 1 >/dev/null || true
}

ensure_ssh_service() {
  vm_exec_retry "${server_vm}" "sudo systemctl is-active --quiet ssh || sudo systemctl restart ssh || sudo systemctl restart sshd" 5 2 >/dev/null
  vm_exec_retry "${server_vm}" "sudo systemctl is-active --quiet ssh || sudo systemctl is-active --quiet sshd" 10 2 >/dev/null
}

install_k3s_via_k3sup() {
  local k3sup_bin="$1"
  local channel_args=()
  local install_cmd=()

  channel_args=(--k3s-channel "${k3s_channel}")
  if [ -n "${k3s_version}" ]; then
    channel_args=(--k3s-version "${k3s_version}")
  fi

  mkdir -p "$(dirname "${kubeconfig_path}")"

  install_cmd=(
    "${k3sup_bin}" install
    --ip "${server_ip}"
    --user "${slicer_vm_user}"
    --ssh-key "${bootstrap_key}"
    --ssh-port 22
    --context "${k3sup_context}"
    --local-path "${kubeconfig_path}"
    --tls-san "${server_ip}"
    "${channel_args[@]}"
  )
  if [ -n "${server_extra_args}" ]; then
    install_cmd+=(--k3s-extra-args "${server_extra_args}")
  fi

  for _ in 1 2 3; do
    if run_with_timeout 300 "${install_cmd[@]}"; then
      return 0
    fi
    sleep 5
  done

  return 1
}

wait_for_vm
server_ip="$(get_vm_ip)"
[ -n "${server_ip}" ] || { echo "ERROR: could not determine IP for ${server_vm}" >&2; exit 1; }

if [ -z "${local_image_cache_host}" ]; then
  gateway_ip="$(vm_exec_retry "$server_vm" "ip -4 route list 0/0 | awk '{print \$3}' | head -n1" 5 2 | tr -d '\r' | head -n1 || true)"
  if [ -n "${gateway_ip}" ]; then
    local_image_cache_host="${gateway_ip}:5002"
  fi
fi

fix_vm_dns
configure_k3s_registries

if remote_k3s_api_ready 2 2; then
  validate_existing_k3s_network_profile
  if [ "${allow_existing_k3s}" != "1" ]; then
    echo "ERROR: existing k3s detected on ${server_vm}; stage 100 refuses to silently reuse a provisioned cluster." >&2
    echo "Reset or recreate ${server_vm} for a fresh bootstrap, or rerun with SLICER_ALLOW_EXISTING_K3S=1 to refresh kubeconfig against the existing cluster." >&2
    exit 1
  fi
  echo "==> Existing k3s detected on ${server_vm}; refreshing kubeconfig only (SLICER_ALLOW_EXISTING_K3S=1)"
  refresh_kubeconfig "${server_ip}"
  KUBECONFIG="$kubeconfig_path" kubectl --context "$k3sup_context" get nodes -o wide || true
  exit 0
fi

echo "==> Ensuring swap is enabled inside ${server_vm}"
vm_exec_retry "$server_vm" "swapon --show | grep -q /swapfile || { sudo fallocate -l ${swap_size} /swapfile && sudo chmod 600 /swapfile && sudo mkswap /swapfile && sudo swapon /swapfile && grep -q /swapfile /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab; }" 3 3 >/dev/null

echo "==> Checking for ext4 filesystem errors"
vm_exec_retry "$server_vm" "dmesg | grep -i 'ext4.*error' && echo 'WARNING: ext4 errors detected in dmesg' || true" 2 2 || true

command -v ssh-keygen >/dev/null 2>&1 || { echo "ERROR: ssh-keygen is required for host-side k3sup bootstrap" >&2; exit 1; }
k3sup_bin="$(find_bootstrap_client || true)"
if [ -z "${k3sup_bin}" ]; then
  echo "ERROR: neither k3sup-pro nor k3sup was found. Install one with brew or arkade." >&2
  exit 1
fi
bootstrap_client_name="$(basename "${k3sup_bin}")"
if [ "${bootstrap_client_name}" = "k3sup-pro" ]; then
  echo "==> Using k3sup-pro for bootstrap"
else
  echo "==> Using k3sup for bootstrap"
fi

ensure_ssh_service
ensure_bootstrap_keypair
authorize_bootstrap_key

echo "==> Installing k3s on ${server_vm} via ${bootstrap_client_name}"
if ! install_k3s_via_k3sup "${k3sup_bin}"; then
  echo "WARN: ${bootstrap_client_name} install did not complete cleanly; checking k3s service state..." >&2
  if ! remote_k3s_api_ready 10 2; then
    echo "ERROR: ${bootstrap_client_name} install failed and k3s API is not reachable" >&2
    exit 1
  fi
fi

configure_k3s_registries

echo "==> Ensuring k3s service is active on ${server_vm}"
vm_exec_retry "$server_vm" "sudo systemctl daemon-reload || true; sudo systemctl is-active --quiet k3s || sudo systemctl restart k3s" 8 3 >/dev/null
vm_exec_retry "$server_vm" "timeout 120s sudo systemctl is-active --quiet k3s" 20 3 >/dev/null
remote_k3s_api_ready 30 2

echo "==> Retrieving kubeconfig from ${server_vm}"
refresh_kubeconfig "${server_ip}"

echo "==> Waiting for Kubernetes API (${server_ip}:6443)"
if ! wait_for_kube_api 45 2; then
  echo "ERROR: Kubernetes API did not become reachable via ${server_ip}:6443" >&2
  vm_exec_retry "$server_vm" "sudo systemctl status k3s --no-pager -l | tail -n 40" 2 2 >&2 || true
  vm_exec_retry "$server_vm" "sudo journalctl -u k3s --no-pager -n 60" 2 2 >&2 || true
  exit 1
fi

echo ""
echo "==> Cluster bootstrapped via ${bootstrap_client_name}"
echo "    kubeconfig: KUBECONFIG=${kubeconfig_path}  context=${k3sup_context}"
KUBECONFIG="$kubeconfig_path" kubectl --context "$k3sup_context" get nodes -o wide || true
