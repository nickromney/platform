#!/usr/bin/env bash
set -euo pipefail

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

for attempt in $(seq 1 30); do
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
  if [[ "${attempt}" -lt 30 ]]; then
    sleep 4
  fi
done

fail "Failed to capture Gitea SSH public keys after ${attempt} attempts"
