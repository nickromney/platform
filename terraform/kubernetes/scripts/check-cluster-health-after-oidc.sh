#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -z "${REPO_ROOT:-}" ]]; then
  REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
fi

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

HEALTH_SCRIPT="${HEALTH_SCRIPT:-${SCRIPT_DIR}/check-cluster-health.sh}"
RETRY_SLEEP_SECONDS="${RETRY_SLEEP_SECONDS:-60}"

# shellcheck disable=SC2329 # invoked by name through the shell_cli_* helpers
usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--dry-run] [--execute]

Assemble --var-file arguments from the kind/operator tfvars env and retry
check-cluster-health.sh twice after an OIDC apiserver restart.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

shell_cli_handle_standard_no_args usage "would retry cluster health after OIDC" "$@"

: "${KUBECONFIG:?KUBECONFIG is required}"

KIND_STAGE_TFVARS_FILE="${KIND_STAGE_TFVARS_FILE:-}"
KIND_TARGET_TFVARS_FILE="${KIND_TARGET_TFVARS_FILE:-}"
KIND_OPERATOR_OVERRIDES_FILE="${KIND_OPERATOR_OVERRIDES_FILE:-}"
PLATFORM_TFVARS_FILE="${PLATFORM_TFVARS:-}"

check_args=()
if [[ -n "${KIND_STAGE_TFVARS_FILE}" && -f "${KIND_STAGE_TFVARS_FILE}" ]]; then
  check_args+=(--var-file "${KIND_STAGE_TFVARS_FILE}")
fi
if [[ -n "${KIND_TARGET_TFVARS_FILE}" && -f "${KIND_TARGET_TFVARS_FILE}" ]]; then
  check_args+=(--var-file "${KIND_TARGET_TFVARS_FILE}")
fi
if [[ -n "${PLATFORM_TFVARS_FILE}" && -f "${PLATFORM_TFVARS_FILE}" ]]; then
  check_args+=(--var-file "${PLATFORM_TFVARS_FILE}")
fi
if [[ -n "${KIND_OPERATOR_OVERRIDES_FILE}" && -f "${KIND_OPERATOR_OVERRIDES_FILE}" ]]; then
  check_args+=(--var-file "${KIND_OPERATOR_OVERRIDES_FILE}")
fi

for attempt in 1 2; do
  if "${HEALTH_SCRIPT}" --execute "${check_args[@]}"; then
    exit 0
  fi
  if [[ "${attempt}" -lt 2 ]]; then
    echo "Post-OIDC cluster health check failed; retrying once in ${RETRY_SLEEP_SECONDS}s..." >&2
    sleep "${RETRY_SLEEP_SECONDS}"
  fi
done
exit 1
