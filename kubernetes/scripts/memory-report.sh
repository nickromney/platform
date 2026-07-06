#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Summarize local platform memory pressure from Docker and Kubernetes metrics.

$(shell_cli_standard_options)
EOF
}

warn() {
  printf 'WARN %s\n' "$*"
}

bytes_to_gib() {
  awk -v bytes="$1" 'BEGIN { if (bytes > 0) printf "%.2fGiB", bytes / 1024 / 1024 / 1024; else printf "unknown" }'
}

print_docker_daemon_memory() {
  local mem_total operating_system

  printf '\nDocker daemon\n'
  if ! command -v docker >/dev/null 2>&1; then
    warn "docker not found in PATH"
    return 0
  fi

  if ! docker info >/dev/null 2>&1; then
    warn "docker daemon not reachable"
    return 0
  fi

  mem_total="$(docker info --format '{{.MemTotal}}' 2>/dev/null || true)"
  operating_system="$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)"

  case "${mem_total}" in
    ''|'<no value>'|*[!0-9]*)
      printf '  Memory budget: unknown\n'
      ;;
    *)
      printf '  Memory budget: %s (%s bytes)\n' "$(bytes_to_gib "${mem_total}")" "${mem_total}"
      ;;
  esac

  if [[ -n "${operating_system}" && "${operating_system}" != "<no value>" ]]; then
    printf '  Runtime: %s\n' "${operating_system}"
  fi
}

print_kind_node_stats() {
  local names

  printf '\nKind node containers\n'
  if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
    warn "docker unavailable; skipping kind node container stats"
    return 0
  fi

  names="$(docker ps --format '{{.Names}}' 2>/dev/null | grep '^kind-local-' || true)"
  if [[ -z "${names}" ]]; then
    printf '  No running kind-local node containers found.\n'
    return 0
  fi

  # Docker container names are whitespace-free; shell splitting is intentional here.
  # shellcheck disable=SC2086
  docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}\t{{.MemPerc}}\t{{.CPUPerc}}' ${names} || \
    warn "docker stats failed for kind-local containers"
}

print_kubectl_top() {
  local err_file status

  printf '\nKubernetes pod memory\n'
  if ! command -v kubectl >/dev/null 2>&1; then
    warn "kubectl not found in PATH; skipping pod metrics"
    return 0
  fi

  if [[ -n "${KUBECONFIG_PATH:-}" && -z "${KUBECONFIG:-}" ]]; then
    export KUBECONFIG="${KUBECONFIG_PATH}"
  fi
  err_file="$(mktemp)"
  set +e
  if [[ -n "${KUBECONFIG_CONTEXT:-}" ]]; then
    kubectl --context "${KUBECONFIG_CONTEXT}" top pods -A 2>"${err_file}"
  else
    kubectl top pods -A 2>"${err_file}"
  fi
  status=$?
  set -e
  if [[ "${status}" -eq 0 ]]; then
    rm -f "${err_file}"
    return 0
  fi

  warn "kubectl top pods -A unavailable; metrics-server may not be ready"
  if [[ -s "${err_file}" ]]; then
    sed 's/^/  /' "${err_file}" >&2
  fi
  rm -f "${err_file}"
  return 0
}

main() {
  shell_cli_parse_standard_only usage "$@" || exit 1
  if [[ "${SHELL_CLI_ARG_COUNT}" -gt 0 ]]; then
    shell_cli_require_no_args "${SHELL_CLI_ARGS[@]}" || exit 1
  fi
  shell_cli_maybe_execute_or_preview_summary usage "would summarize Docker memory, kind node usage, and kubectl pod metrics"

  printf 'Local platform memory report\n'
  print_docker_daemon_memory
  print_kind_node_stats
  print_kubectl_top
}

main "$@"
