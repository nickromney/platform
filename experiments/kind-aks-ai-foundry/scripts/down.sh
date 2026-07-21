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

Removes only the experiment-owned Kubernetes and Docker Compose state.

$(shell_cli_standard_options)
EOF
}

preview() {
  printf 'INFO dry-run: would delete only kind-aks-ai-foundry Kubernetes resources\n'
  printf 'INFO dry-run: would remove AKS simulation labels from experiment workers\n'
  printf 'INFO dry-run: would stop the external APIM and AI Foundry containers\n'
}

shell_cli_parse_standard_only usage "$@" || exit 1
if [[ "${SHELL_CLI_ARG_COUNT}" -gt 0 ]]; then
  shell_cli_require_no_args "${SHELL_CLI_ARGS[@]}" || exit 1
fi
shell_cli_maybe_execute_or_preview usage preview

kubeconfig_path="${KUBECONFIG_PATH:-${HOME}/.kube/kind-kind-local.yaml}"
kubeconfig_context="${KUBECONFIG_CONTEXT:-kind-kind-local}"

kubectl_args=(--kubeconfig "${kubeconfig_path}" --context "${kubeconfig_context}")
if [[ -f "${kubeconfig_path}" ]]; then
  kubectl "${kubectl_args[@]}" delete -f "${experiment_root}/kubernetes/egress-probe.yaml" \
    --ignore-not-found=true --wait=true >/dev/null
  kubectl "${kubectl_args[@]}" delete -f "${experiment_root}/kubernetes/all.yaml" \
    --ignore-not-found=true --wait=true --timeout=120s

  experiment_nodes="$(kubectl "${kubectl_args[@]}" get nodes \
    -l 'kubernetes.azure.com/cluster=kind-aks-sim' -o name)"
  if [[ -n "${experiment_nodes}" ]]; then
    while IFS= read -r experiment_node; do
      kubectl "${kubectl_args[@]}" label "${experiment_node}" \
        kubernetes.azure.com/agentpool- \
        kubernetes.azure.com/cluster- \
        topology.kubernetes.io/region- \
        topology.kubernetes.io/zone-
    done <<<"${experiment_nodes}"
  fi
else
  printf 'warning: skipping Kubernetes cleanup; kubeconfig not found: %s\n' "${kubeconfig_path}" >&2
fi

docker compose --project-directory "${experiment_root}" -f "${experiment_root}/compose.yml" \
  down --remove-orphans
printf 'experiment-owned state removed\n'
