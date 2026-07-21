#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
experiment_root="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${experiment_root}/../.." && pwd)"
# shellcheck source=/dev/null
source "${repo_root}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Verifies the live brokered request path and direct-egress denial.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage \
  "would verify the live brokered request path and direct-egress denial" "$@"

kubeconfig_path="${KUBECONFIG_PATH:-${HOME}/.kube/kind-kind-local.yaml}"
kubeconfig_context="${KUBECONFIG_CONTEXT:-kind-kind-local}"
apim_gateway_port="${APIM_GATEWAY_PORT:-8100}"
foundry_port="${FOUNDRY_PORT:-8020}"
kubectl_args=(--kubeconfig "${kubeconfig_path}" --context "${kubeconfig_context}")

curl -fsS "http://127.0.0.1:${foundry_port}/foundry/health" >/dev/null
curl -fsS "http://127.0.0.1:${apim_gateway_port}/apim/health" >/dev/null

pod_node="$(kubectl "${kubectl_args[@]}" get pod -n aks-sim -l app.kubernetes.io/name=auth-chat-aks-sim -o jsonpath='{.items[0].spec.nodeName}')"
agentpool="$(kubectl "${kubectl_args[@]}" get node "${pod_node}" -o jsonpath='{.metadata.labels.kubernetes\.azure\.com/agentpool}')"
region="$(kubectl "${kubectl_args[@]}" get node "${pod_node}" -o jsonpath='{.metadata.labels.topology\.kubernetes\.io/region}')"
[[ "${agentpool}" == "experiment" && "${region}" == "uksouth" ]]
printf 'AKS-shaped worker placement: ok (%s, %s)\n' "${agentpool}" "${region}"

missing_key_status="$(curl -sS -o /dev/null -w '%{http_code}' \
  -H 'Content-Type: application/json' \
  -d '{"model":"gpt-demo","messages":[{"role":"user","content":"missing subscription"}]}' \
  "http://127.0.0.1:${apim_gateway_port}/foundry/v1/chat/completions")"
[[ "${missing_key_status}" == "401" ]]
printf 'APIM rejects missing subscription key: %s\n' "${missing_key_status}"

probe_name="aks-ai-direct-egress-probe"
kubectl "${kubectl_args[@]}" delete pod "${probe_name}" -n aks-sim --ignore-not-found --wait=true >/dev/null
kubectl "${kubectl_args[@]}" apply -f "${experiment_root}/kubernetes/egress-probe.yaml" >/dev/null
probe_phase=""
for _attempt in $(seq 1 20); do
  probe_phase="$(kubectl "${kubectl_args[@]}" get pod "${probe_name}" -n aks-sim -o jsonpath='{.status.phase}')"
  case "${probe_phase}" in
    Succeeded | Failed) break ;;
  esac
  sleep 1
done
probe_output="$(kubectl "${kubectl_args[@]}" logs "${probe_name}" -n aks-sim)"
kubectl "${kubectl_args[@]}" delete pod "${probe_name}" -n aks-sim --wait=true >/dev/null
[[ "${probe_phase}" == "Succeeded" ]]
[[ "${probe_output}" == *"direct external egress from workload: denied"* ]]
printf '%s\n' "${probe_output}"

port_forward_log="$(mktemp "${TMPDIR:-/tmp}/kind-aks-ai-foundry-port-forward.XXXXXX")"
kubectl "${kubectl_args[@]}" -n aks-sim port-forward service/auth-chat-aks-sim 18087:8080 >"${port_forward_log}" 2>&1 &
port_forward_pid=$!
cleanup() {
  kill "${port_forward_pid}" >/dev/null 2>&1 || true
  wait "${port_forward_pid}" >/dev/null 2>&1 || true
  rm -f "${port_forward_log}"
}
trap cleanup EXIT

for _attempt in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:18087/health >/dev/null 2>&1; then
    break
  fi
  sleep 1
done
curl -fsS http://127.0.0.1:18087/health >/dev/null

chat_response="$(curl -fsS \
  -H 'Content-Type: application/json' \
  -d '{"message":"Explain the verified local egress path in one sentence.","model":"gpt-demo"}' \
  http://127.0.0.1:18087/chat)"
model_status="$(jq -r '.model.status' <<<"${chat_response}")"
usage_total="$(jq -r '.usage.total_tokens // 0' <<<"${chat_response}")"
[[ "${model_status}" == "ok" ]]
[[ "${usage_total}" =~ ^[0-9]+$ && "${usage_total}" -gt 0 ]]
printf 'auth-chat model status: %s (usage total_tokens=%s)\n' "${model_status}" "${usage_total}"

traces="$(curl -fsS -H 'X-Apim-Tenant-Key: local-dev-tenant-key' \
  "http://127.0.0.1:${apim_gateway_port}/apim/management/traces")"
upstream_url="$(jq -r '.items[0].upstream_url // empty' <<<"${traces}")"
expected_upstream='http://aifoundry-simulator:8000/openai/v1/chat/completions'
[[ "${upstream_url}" == "${expected_upstream}" ]]
printf 'APIM trace upstream: %s\n' "${upstream_url}"
