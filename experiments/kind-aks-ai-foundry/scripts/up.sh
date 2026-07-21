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

Starts the external simulators and applies the AKS-shaped Kind resources.

$(shell_cli_standard_options)
EOF
}

preview() {
  printf 'path: auth-chat-aks-sim -> agentgateway -> apim-simulator -> aifoundry-simulator\n'
  printf 'INFO dry-run: would start external APIM and AI Foundry containers\n'
  printf 'INFO dry-run: would apply AKS-shaped Kind resources\n'
}

shell_cli_parse_standard_only usage "$@" || exit 1
if [[ "${SHELL_CLI_ARG_COUNT}" -gt 0 ]]; then
  shell_cli_require_no_args "${SHELL_CLI_ARGS[@]}" || exit 1
fi
shell_cli_maybe_execute_or_preview usage preview

kubeconfig_path="${KUBECONFIG_PATH:-${HOME}/.kube/kind-kind-local.yaml}"
kubeconfig_context="${KUBECONFIG_CONTEXT:-kind-kind-local}"
kind_cluster_name="${KIND_CLUSTER_NAME:-kind-local}"
auth_chat_image="platform-auth-chat:kind-aks-ai-foundry"
network_probe_image="docker.io/curlimages/curl:8.19.0"

printf 'path: auth-chat-aks-sim -> agentgateway -> apim-simulator -> aifoundry-simulator\n'
for command_name in docker docker-credential-platform-file kind kubectl make; do
  command -v "${command_name}" >/dev/null 2>&1 || {
    printf 'error: %s is required\n' "${command_name}" >&2
    exit 1
  }
done
[[ -f "${kubeconfig_path}" ]] || {
  printf 'error: Kind kubeconfig not found: %s\n' "${kubeconfig_path}" >&2
  exit 1
}
kubectl_args=(--kubeconfig "${kubeconfig_path}" --context "${kubeconfig_context}")
kubectl "${kubectl_args[@]}" get gateway/agentgateway-ai-gateway \
  -n agentgateway-system >/dev/null 2>&1 || {
  printf 'error: agentgateway-ai-gateway is not available; apply the Kind stage-900 stack first\n' >&2
  exit 1
}

docker_config_dir="${experiment_root}/.run/docker"
docker_cli_plugin_source_dir="${HOME}/.docker/cli-plugins"
mkdir -p "${docker_config_dir}/cli-plugins"
printf '%s\n' '{"credHelpers":{"dhi.io":"platform-file"}}' >"${docker_config_dir}/config.json"
for docker_cli_plugin in docker-buildx docker-compose; do
  [[ -x "${docker_cli_plugin_source_dir}/${docker_cli_plugin}" ]] || {
    printf 'error: Docker CLI plugin not found: %s\n' "${docker_cli_plugin_source_dir}/${docker_cli_plugin}" >&2
    exit 1
  }
  ln -sfn "${docker_cli_plugin_source_dir}/${docker_cli_plugin}" "${docker_config_dir}/cli-plugins/${docker_cli_plugin}"
done
export DOCKER_CONFIG="${docker_config_dir}"

printf 'starting external APIM and AI Foundry containers\n'
docker compose --project-directory "${experiment_root}" -f "${experiment_root}/compose.yml" up \
  --build --detach --force-recreate --wait

printf 'building and loading the isolated auth-chat workload image\n'
make -C "${repo_root}/apps/auth-chat/app" build-linux
docker build --tag "${auth_chat_image}" "${repo_root}/apps/auth-chat/app"
kind load docker-image --name "${kind_cluster_name}" "${auth_chat_image}"
if ! docker image inspect "${network_probe_image}" >/dev/null 2>&1; then
  docker pull "${network_probe_image}"
fi
kind load docker-image --name "${kind_cluster_name}" "${network_probe_image}"

worker_nodes="$(kubectl "${kubectl_args[@]}" get nodes -l '!node-role.kubernetes.io/control-plane' -o name)"
[[ -n "${worker_nodes}" ]] || {
  printf 'error: Kind cluster has no worker nodes to model an AKS agent pool\n' >&2
  exit 1
}
while IFS= read -r worker_node; do
  kubectl "${kubectl_args[@]}" label "${worker_node}" \
    kubernetes.azure.com/agentpool=experiment \
    kubernetes.azure.com/cluster=kind-aks-sim \
    topology.kubernetes.io/region=uksouth \
    topology.kubernetes.io/zone=uksouth-1 \
    --overwrite
done <<<"${worker_nodes}"

printf 'applying AKS-shaped Kind resources\n'
kubectl "${kubectl_args[@]}" apply -f "${experiment_root}/kubernetes/all.yaml"
kubectl "${kubectl_args[@]}" wait --for=condition=Accepted \
  agentgatewaybackend/external-apim-ai-foundry -n agentgateway-system --timeout=60s
route_accepted=""
route_refs_resolved=""
for _attempt in $(seq 1 30); do
  route_accepted="$(kubectl "${kubectl_args[@]}" get httproute/external-apim-ai-foundry \
    -n agentgateway-system -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}')"
  route_refs_resolved="$(kubectl "${kubectl_args[@]}" get httproute/external-apim-ai-foundry \
    -n agentgateway-system -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}')"
  if [[ "${route_accepted}" == "True" && "${route_refs_resolved}" == "True" ]]; then
    break
  fi
  sleep 2
done
[[ "${route_accepted}" == "True" && "${route_refs_resolved}" == "True" ]] || {
  printf 'error: external APIM HTTPRoute was not accepted with resolved references\n' >&2
  exit 1
}
kubectl "${kubectl_args[@]}" wait --for=condition=Available deployment/auth-chat-aks-sim -n aks-sim --timeout=180s

printf 'experiment ready\n'
printf 'run: make -C %s check\n' "${experiment_root}"
