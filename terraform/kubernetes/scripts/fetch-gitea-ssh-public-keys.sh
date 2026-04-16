#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

fail() {
  jq -n --arg error "$1" '{error:$error}'
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

require_cmd jq
require_cmd kubectl
require_cmd base64
require_cmd shasum

wait_for_gitea_ssh() {
  local namespace="$1"
  local timeout_seconds="${2:-300}"
  local deadline=$((SECONDS + timeout_seconds))
  local pod_name=""
  local ssh_target_port=""

  if ! kubectl "${kubectl_args[@]}" -n "${namespace}" get deployment gitea >/dev/null 2>&1; then
    fail "Gitea deployment not found in namespace ${namespace}"
  fi

  kubectl "${kubectl_args[@]}" -n "${namespace}" rollout status deployment/gitea --timeout="${timeout_seconds}s" >/dev/null 2>&1 || true

  while (( SECONDS < deadline )); do
    pod_name="$(
      kubectl "${kubectl_args[@]}" -n "${namespace}" get pods \
        -l app.kubernetes.io/name=gitea \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
    )"
    ssh_target_port="$(
      kubectl "${kubectl_args[@]}" -n "${namespace}" get endpoints gitea-ssh \
        -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null || true
    )"

    if [[ -n "${pod_name}" && -n "${ssh_target_port}" ]] && kubectl "${kubectl_args[@]}" -n "${namespace}" exec "${pod_name}" -- sh -c '
      ssh_target_port="$1"
      if command -v ss >/dev/null 2>&1; then
        ss -ltn | grep -qE "[[:space:]]:${ssh_target_port}[[:space:]]"
      elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep -qE "[.:]${ssh_target_port}[[:space:]]"
      else
        exit 1
      fi
    ' sh "${ssh_target_port}" >/dev/null 2>&1; then
      return 0
    fi

    sleep 5
  done

  fail "Timed out waiting for Gitea SSH listener to become ready"
}

usage() {
  cat <<EOF
Usage: fetch-gitea-ssh-public-keys.sh [--dry-run] [--execute]

Reads a JSON request from stdin and returns the Gitea SSH public keys and
service metadata as JSON.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would fetch Gitea SSH public keys from the current cluster using JSON request data from stdin" "$@"

payload="$(cat)"

gitea_namespace="$(jq -r '.gitea_namespace // empty' <<<"${payload}")"
kubeconfig_path="$(jq -r '.kubeconfig_path // empty' <<<"${payload}")"
kubeconfig_context="$(jq -r '.kubeconfig_context // empty' <<<"${payload}")"

[[ -n "${gitea_namespace}" ]] || fail "gitea_namespace is required"
[[ -n "${kubeconfig_path}" ]] || fail "kubeconfig_path is required"

export KUBECONFIG="${kubeconfig_path}"

kubectl_args=()
if [[ -n "${kubeconfig_context}" ]]; then
  kubectl_args+=(--context "${kubeconfig_context}")
fi

wait_for_gitea_ssh "${gitea_namespace}" 300

for attempt in $(seq 1 60); do
  raw="$(
    # shellcheck disable=SC2016
    kubectl "${kubectl_args[@]}" -n "${gitea_namespace}" exec deploy/gitea -- sh -c '
      found=0
      for f in /data/ssh/*.pub; do
        [ -f "$f" ] || continue
        cat "$f"
        found=1
      done
      [ "$found" -eq 1 ]
    ' 2>/dev/null || true
  )"
  keys="$(printf '%s\n' "${raw}" | grep -E '^ssh-' || true)"
  if [[ -n "${keys}" ]]; then
    cluster_ip="$(
      kubectl "${kubectl_args[@]}" -n "${gitea_namespace}" get svc gitea-ssh \
        -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true
    )"
    if [[ "${cluster_ip}" == "None" ]]; then
      cluster_ip=""
    fi
    keys_b64="$(printf '%s\n' "${keys}" | base64 | tr -d '\n')"
    keys_sha1="$(printf '%s\n' "${keys}" | shasum -a 1 | awk '{print $1}')"
    jq -n \
      --arg cluster_ip "${cluster_ip}" \
      --arg keys_b64 "${keys_b64}" \
      --arg keys_sha1 "${keys_sha1}" \
      '{cluster_ip:$cluster_ip,keys_b64:$keys_b64,keys_sha1:$keys_sha1}'
    exit 0
  fi
  if [[ "${attempt}" -lt 60 ]]; then
    sleep 5
  fi
done

fail "Failed to capture Gitea SSH public keys after ${attempt} attempts"
