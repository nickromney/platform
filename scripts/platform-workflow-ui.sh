#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

HOST="console.127.0.0.1.sslip.io"
PORT="8443"
HTTP_MODE="h2"
TLS_CERT_FILE=""
TLS_KEY_FILE=""
TLS_CERT_DIR=""

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--host HOST] [--port PORT] [--http http1|h2] [--tls-cert-file PATH] [--tls-key-file PATH] [--dry-run] [--execute]

Serves the browser workflow chooser backed by scripts/platform-workflow.sh.

HTTPS over HTTP/2 is the default. Use --http http1 for the plain local HTTP
server. If no certificate is supplied, the script generates a local mkcert
certificate under .run/workflow-ui.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

require_value() {
  local flag="$1"
  local value="${2-}"

  if [[ -z "${value}" ]]; then
    shell_cli_missing_value "$(shell_cli_script_name)" "${flag}"
    exit 2
  fi
}

fail() {
  printf '%s\n' "$*" >&2
  exit 2
}

cert_name_for_host() {
  printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9._-' '-'
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --host)
      require_value "$1" "${2-}"
      HOST="$2"
      shift 2
      ;;
    --port)
      require_value "$1" "${2-}"
      PORT="$2"
      shift 2
      ;;
    --http)
      require_value "$1" "${2-}"
      HTTP_MODE="$2"
      shift 2
      ;;
    --tls-cert-file)
      require_value "$1" "${2-}"
      TLS_CERT_FILE="$2"
      shift 2
      ;;
    --tls-key-file)
      require_value "$1" "${2-}"
      TLS_KEY_FILE="$2"
      shift 2
      ;;
    --tls-cert-dir)
      require_value "$1" "${2-}"
      TLS_CERT_DIR="$2"
      shift 2
      ;;
    *)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      exit 2
      ;;
  esac
done

case "${HTTP_MODE}" in
  http1|h2) ;;
  *) fail "Invalid --http '${HTTP_MODE}'. Expected http1 or h2" ;;
esac

scheme="http"
if [[ "${HTTP_MODE}" = "h2" ]]; then
  scheme="https"
fi

shell_cli_maybe_execute_or_preview_summary usage "would serve platform workflow UI on ${scheme}://${HOST}:${PORT} (${HTTP_MODE})"

if [[ "${PORT}" =~ ^[0-9]+$ && "${PORT}" -lt 1024 && "${EUID}" -ne 0 ]]; then
  echo "Port ${PORT} requires elevated privileges on this host." >&2
  echo "Use WORKFLOW_UI_PORT=8443, or run an explicit privileged bind/proxy if you really need :${PORT}." >&2
  exit 1
fi

if ! command -v uv >/dev/null 2>&1; then
  echo "uv is required for the FastAPI workflow UI." >&2
  echo "Install uv, or use make tui for the terminal workflow." >&2
  exit 1
fi

export PLATFORM_REPO_ROOT="${REPO_ROOT}"

if [[ "${HTTP_MODE}" = "http1" ]]; then
  echo "Open ${scheme}://${HOST}:${PORT}"
  exec uv run --project "${REPO_ROOT}/tools/platform-workflow-ui" \
    uvicorn platform_workflow_ui.main:app \
    --host "${HOST}" \
    --port "${PORT}"
fi

if [[ -z "${TLS_CERT_FILE}" || -z "${TLS_KEY_FILE}" ]]; then
  if ! command -v mkcert >/dev/null 2>&1; then
    echo "mkcert is required for --http h2 unless --tls-cert-file and --tls-key-file are supplied." >&2
    exit 1
  fi
  TLS_CERT_DIR="${TLS_CERT_DIR:-${REPO_ROOT}/.run/workflow-ui}"
  mkdir -p "${TLS_CERT_DIR}"
  TLS_CERT_NAME="$(cert_name_for_host "${HOST}")"
  TLS_CERT_FILE="${TLS_CERT_DIR}/workflow-ui-${TLS_CERT_NAME}.pem"
  TLS_KEY_FILE="${TLS_CERT_DIR}/workflow-ui-${TLS_CERT_NAME}-key.pem"
  if [[ ! -s "${TLS_CERT_FILE}" || ! -s "${TLS_KEY_FILE}" ]]; then
    mkcert -cert-file "${TLS_CERT_FILE}" -key-file "${TLS_KEY_FILE}" "${HOST}" localhost 127.0.0.1 ::1 >/dev/null
  fi
fi

echo "Open ${scheme}://${HOST}:${PORT}"
exec uv run --project "${REPO_ROOT}/tools/platform-workflow-ui" \
  hypercorn platform_workflow_ui.main:app \
  --bind "${HOST}:${PORT}" \
  --certfile "${TLS_CERT_FILE}" \
  --keyfile "${TLS_KEY_FILE}"
