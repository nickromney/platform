#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL $*" >&2; exit 1; }

kubeconfig_path="${KUBECONFIG_PATH:-${KUBECONFIG:-}}"
kubeconfig_context="${KUBECONFIG_CONTEXT:-}"
attempts="${KUBECTL_REACHABILITY_ATTEMPTS:-10}"
delay_seconds="${KUBECTL_REACHABILITY_DELAY_SECONDS:-3}"

[[ -n "${kubeconfig_path}" ]] || fail "KUBECONFIG_PATH or KUBECONFIG must be set"
command -v kubectl >/dev/null 2>&1 || fail "kubectl not found in PATH"

kubectl_args=(get nodes --request-timeout=5s)
if [[ -n "${kubeconfig_context}" ]]; then
  kubectl_args=(--context "${kubeconfig_context}" "${kubectl_args[@]}")
fi

for _ in $(seq 1 "${attempts}"); do
  if KUBECONFIG="${kubeconfig_path}" kubectl "${kubectl_args[@]}" >/dev/null 2>&1; then
    exit 0
  fi
  sleep "${delay_seconds}"
done

exit 1
