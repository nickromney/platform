#!/usr/bin/env bash
set -eu

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

# macOS does not ship GNU timeout(1). Prefer timeout, then gtimeout, then
# perl alarm — the same fallback k3s_bootstrap_run_with_timeout uses.
run_with_timeout() {
  _seconds="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    command timeout "$_seconds" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$_seconds" "$@"
    return $?
  fi
  perl -e 'alarm shift; exec @ARGV' "$_seconds" "$@"
}

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Restart containerd on every kind node after registry host.toml changes, then
wait for nodes to register (CNI-disabled) or become Ready.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would restart containerd on kind nodes and wait for Ready" "$@"

: "${CLUSTER_NAME:?CLUSTER_NAME is required}"
: "${EXPECTED_KIND_NODE_COUNT:?EXPECTED_KIND_NODE_COUNT is required}"
: "${KIND_DISABLE_DEFAULT_CNI:?KIND_DISABLE_DEFAULT_CNI is required}"
: "${KUBECONFIG:?KUBECONFIG is required}"
: "${NODE_READY_WRAP_SECONDS:?NODE_READY_WRAP_SECONDS is required}"
: "${NODE_READY_TIMEOUT_SECONDS:?NODE_READY_TIMEOUT_SECONDS is required}"
export EXPECTED_KIND_NODE_COUNT KIND_DISABLE_DEFAULT_CNI KUBECONFIG

kind get nodes --name "${CLUSTER_NAME}" | while IFS= read -r node; do
  [ -n "${node}" ] || continue
  echo "Restarting containerd on ${node}..."
  run_with_timeout 60 docker exec "${node}" sh -lc 'set -eu; systemctl restart containerd; systemctl is-active containerd >/dev/null'
done

if [ "${KIND_DISABLE_DEFAULT_CNI}" = "true" ]; then
  echo "Default CNI disabled; waiting for kind nodes to register before CNI install..."
  # shellcheck disable=SC2016 # child shell expands EXPECTED_KIND_NODE_COUNT from the exported env
  run_with_timeout 120 sh -eu -c '
    while :; do
      node_count="$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d " ")"
      if [ "${node_count}" -ge "${EXPECTED_KIND_NODE_COUNT}" ]; then
        exit 0
      fi
      sleep 2
    done
  '
else
  echo "Waiting for nodes to become Ready..."
  run_with_timeout "${NODE_READY_WRAP_SECONDS}" kubectl wait --for=condition=Ready nodes --all --timeout="${NODE_READY_TIMEOUT_SECONDS}s" >/dev/null
fi
