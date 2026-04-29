#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=./stack-env.sh
source "$ROOT_DIR/scripts/stack-env.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/lib/shell-cli.sh"

usage() {
  cat <<'EOF'
Usage: run-stacked-make.sh [--dry-run] [--execute] <stack-slot> <make-target> [extra make args...]

Run a root make target with STACK_SLOT and STACK_SLOT_WIDTH isolated from the
caller environment.

Options:
  --dry-run  Show the make invocation and exit before running it
  --execute  Run the make invocation
  -h, --help Show this message
EOF
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --)
      shift
      break
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
done

if [[ "$#" -lt 2 ]]; then
  if [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
    usage
    echo "INFO dry-run: would run make for an isolated stack after stack slot and target are provided"
    exit 0
  fi

  usage >&2
  exit 2
fi

STACK_SLOT="$1"
target="$2"
shift 2
STACK_SLOT_WIDTH="${STACK_SLOT_WIDTH:-100}"

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 || "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_command make "$target" STACK_SLOT="$STACK_SLOT" STACK_SLOT_WIDTH="$STACK_SLOT_WIDTH" "$@"
  exit 0
fi

unset \
  PORT_OFFSET STACK_INSTANCE_SUFFIX \
  APIM_GATEWAY_PORT GRAFANA_PORT OTEL_GRPC_PORT OTEL_HTTP_PORT KEYCLOAK_PORT OPERATOR_CONSOLE_PORT EDGE_HTTP_PORT EDGE_TLS_HTTP_PORT EDGE_TLS_PORT TODO_FRONTEND_PORT VITE_DEV_PORT \
  APIM_BASE_URL APIM_LOOPBACK_BASE_URL GRAFANA_BASE_URL KEYCLOAK_BASE_URL OIDC_ISSUER_EXTERNAL OPERATOR_CONSOLE_URL \
  TODO_FRONTEND_BASE_URL TODO_FRONTEND_BROWSER_URL TODO_FRONTEND_ORIGIN_LOCALHOST TODO_FRONTEND_ORIGIN_LOOPBACK TODO_APIM_BASE_URL TODO_APIM_PUBLIC_BASE_URL TODO_GRAFANA_BASE_URL TODO_OBSERVABILITY_DASHBOARD_URL \
  APIM_ALLOWED_ORIGIN_BROWSER_LOCALHOST APIM_ALLOWED_ORIGIN_OPERATOR_CONSOLE APIM_ALLOWED_ORIGIN_VITE APIM_ALLOWED_ORIGIN_GATEWAY \
  EDGE_HTTP_BASE_URL EDGE_TLS_BASE_URL \
  SMOKE_HELLO_BASE_URL SMOKE_HELLO_KEYCLOAK_BASE_URL SMOKE_OIDC_BASE_URL SMOKE_OIDC_KEYCLOAK_BASE_URL SMOKE_MCP_URL SMOKE_EDGE_BASE_URL

export STACK_SLOT STACK_SLOT_WIDTH
stack_env_init

cd "$ROOT_DIR"
exec make "$target" STACK_SLOT="$STACK_SLOT" STACK_SLOT_WIDTH="$STACK_SLOT_WIDTH" "$@"
