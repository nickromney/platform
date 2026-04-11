#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

usage() {
  cat <<EOF
Usage: delete-kind-cluster.sh --name <cluster-name> [--retries N] [--delay-seconds N] [--dry-run] [--execute]

Retries transient Docker Desktop delete failures where the daemon reports that it
did not receive a container exit event.
$(shell_cli_standard_options)
EOF
}

cluster_name=""
retries="${KIND_DELETE_RETRIES:-3}"
delay_seconds="${KIND_DELETE_RETRY_DELAY_SECONDS:-5}"
shell_cli_init_standard_flags

while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --name)
      cluster_name="${2:-}"
      shift 2
      ;;
    --retries)
      retries="${2:-}"
      shift 2
      ;;
    --delay-seconds)
      delay_seconds="${2:-}"
      shift 2
      ;;
    *)
      usage >&2
      echo "delete-kind-cluster: unknown argument '$1'" >&2
      exit 64
      ;;
  esac
done

summary_name="${cluster_name:-<required --name>}"
shell_cli_maybe_execute_or_preview_summary usage \
  "would delete kind cluster ${summary_name} with up to ${retries} retries and ${delay_seconds}s delay"

if [[ -z "${cluster_name}" ]]; then
  usage >&2
  echo "delete-kind-cluster: --name is required" >&2
  exit 64
fi

if ! [[ "${retries}" =~ ^[0-9]+$ ]] || [[ "${retries}" -lt 1 ]]; then
  echo "delete-kind-cluster: --retries must be a positive integer" >&2
  exit 64
fi

if ! [[ "${delay_seconds}" =~ ^[0-9]+$ ]]; then
  echo "delete-kind-cluster: --delay-seconds must be a non-negative integer" >&2
  exit 64
fi

show_cluster_container_state() {
  docker ps -a \
    --filter "label=io.x-k8s.kind.cluster=${cluster_name}" \
    --format '{{.Names}}\t{{.Status}}' 2>/dev/null || true
}

is_retryable_delete_error() {
  grep -qiE 'did not receive an exit event|could not kill container|context deadline exceeded'
}

attempt=1
while (( attempt <= retries )); do
  set +e
  output="$(kind delete cluster --name "${cluster_name}" 2>&1)"
  rc=$?
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    [[ -n "${output}" ]] && printf '%s\n' "${output}"
    exit 0
  fi

  if ! printf '%s\n' "${output}" | is_retryable_delete_error; then
    printf '%s\n' "${output}" >&2
    echo "delete-kind-cluster: non-retryable failure on attempt ${attempt}/${retries}" >&2
    exit "${rc}"
  fi

  printf '%s\n' "${output}" >&2
  echo "delete-kind-cluster: transient delete failure on attempt ${attempt}/${retries}" >&2
  state="$(show_cluster_container_state)"
  if [[ -n "${state}" ]]; then
    echo "delete-kind-cluster: current kind container state:" >&2
    printf '%s\n' "${state}" >&2
  fi

  if (( attempt == retries )); then
    echo "delete-kind-cluster: giving up after ${retries} attempts; restart Docker Desktop if this persists" >&2
    exit "${rc}"
  fi

  sleep "${delay_seconds}"
  attempt=$((attempt + 1))
done
