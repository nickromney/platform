#!/usr/bin/env bash
# Wait until the Gitea SSH listener is accepting connections inside the cluster.
#
# Modes (WAIT_FOR_GITEA_SSH_MODE):
#   strict       fail if Gitea is missing or the listener never comes up
#   best-effort  warn and return 0 (used before Argo CD app refresh)
#
# May be sourced (defines wait_for_gitea_ssh) or executed with --execute.
set -euo pipefail

if [[ -z "${REPO_ROOT:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

gitea_ssh_kubectl() {
  if [[ -n "${KUBE_CONTEXT:-}" ]]; then
    kubectl --context "${KUBE_CONTEXT}" "$@"
  else
    kubectl "$@"
  fi
}

wait_for_gitea_ssh() {
  local mode="${WAIT_FOR_GITEA_SSH_MODE:-strict}"
  local gitea_ns="${GITEA_NAMESPACE:-gitea}"
  local timeout="${GITEA_SSH_TIMEOUT_SECONDS:?GITEA_SSH_TIMEOUT_SECONDS is required}"
  local deadline=$((SECONDS + timeout))
  local pod_name=""
  local ssh_target_port=""
  local quiet="${WAIT_FOR_GITEA_SSH_QUIET:-0}"

  if ! gitea_ssh_kubectl -n "${gitea_ns}" get deployment gitea >/dev/null 2>&1; then
    if [[ "${mode}" == "best-effort" ]]; then
      return 0
    fi
    echo "Gitea deployment not found in namespace ${gitea_ns}" >&2
    return 1
  fi

  if [[ "${mode}" == "best-effort" ]]; then
    gitea_ssh_kubectl -n "${gitea_ns}" rollout status deployment/gitea --timeout="${timeout}s" >/dev/null 2>&1 || true
  else
    # stdout belongs to the caller: fetch-gitea-ssh-public-keys.sh is a Terraform
    # `data "external"` program, whose stdout must be nothing but a JSON object.
    # kubectl prints `deployment "gitea" successfully rolled out` on success, which
    # made the data source fail with `invalid character 'd'`. Keep the diagnostic,
    # send it to stderr like every other message in this file.
    gitea_ssh_kubectl -n "${gitea_ns}" rollout status deployment/gitea --timeout="${timeout}s" >&2
  fi

  while (( SECONDS < deadline )); do
    pod_name="$(gitea_ssh_kubectl -n "${gitea_ns}" get pods -l app.kubernetes.io/name=gitea -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
    ssh_target_port="$(gitea_ssh_kubectl -n "${gitea_ns}" get endpoints gitea-ssh -o jsonpath='{.subsets[0].ports[0].port}' 2>/dev/null || true)"
    # shellcheck disable=SC2016 # remote sh -c body; ssh_target_port is $1 inside the pod
    if [[ -n "${pod_name}" && -n "${ssh_target_port}" ]] && gitea_ssh_kubectl -n "${gitea_ns}" exec "${pod_name}" -- sh -c '
      ssh_target_port="$1"
      if command -v ss >/dev/null 2>&1; then
        ss -ltn | grep -qE "[[:space:]]:$ssh_target_port[[:space:]]"
      elif command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | grep -qE "[.:]$ssh_target_port[[:space:]]"
      else
        exit 1
      fi
    ' sh "${ssh_target_port}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 5
  done

  if [[ "${mode}" == "best-effort" ]]; then
    echo "WARN gitea SSH listener did not become ready before Argo refresh" >&2
    return 0
  fi

  echo "Timed out waiting for Gitea SSH listener to become ready" >&2
  if [[ "${quiet}" != "1" ]]; then
    gitea_ssh_kubectl -n "${gitea_ns}" get pods,svc,endpoints gitea gitea-ssh -o wide 2>/dev/null || true
  fi
  return 1
}

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0
fi

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Wait for the in-cluster Gitea SSH listener. WAIT_FOR_GITEA_SSH_MODE selects
strict (fail) or best-effort (warn and continue).
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would wait for the Gitea SSH listener (${WAIT_FOR_GITEA_SSH_MODE:-strict})" "$@"

command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH" >&2; exit 1; }
wait_for_gitea_ssh
