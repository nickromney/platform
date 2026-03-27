#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: hubble-check-connection.sh [options]

Check whether a Hubble relay is reachable and explain common failure modes.

If you do not pass `--server`, the script defaults to Hubble CLI port-forward
mode. In this repo, if `~/.kube/kind-kind-local.yaml` exists and `KUBECONFIG`
is not already set, that kubeconfig is used automatically so the local kind
cluster works out of the box.

Options:
  --server HOST:PORT
      Connect to a Hubble relay endpoint. Supported forms:
      - local relay via an existing port-forward: `localhost:4245`
      - in-cluster service: `hubble-relay.kube-system.svc.cluster.local:4245`
      - TLS relay: `tls://relay.example.com:443`
      - HTTPS front door: `https://relay.example.com` or
        `https://relay.example.com:4443`
      HTTPS input is normalised to `tls://HOST:PORT` for the Hubble CLI.
      The endpoint must speak the Hubble Relay gRPC API. In this repo,
      `https://hubble.admin.127.0.0.1.sslip.io` is the Hubble UI/admin route,
      not the relay.

  -P, --port-forward
      Ask Hubble CLI to port-forward to relay automatically.

  --port-forward-port PORT
      Local port for Hubble port-forward mode. Default: 4245

  --kubeconfig FILE
      Kubeconfig used only when --port-forward is set.

  --kube-context NAME
      Kube context used only when --port-forward is set.

  --kube-namespace NS
      Namespace where Hubble relay runs when --port-forward is set.
      Default: kube-system

  --tls
      Enable TLS without rewriting the server address.

  --tls-server-name NAME
      Override the TLS server name used for certificate verification.

  --tls-ca-cert-file FILE
      Repeatable CA certificate file passed to Hubble.

  --tls-client-cert-file FILE
      Client certificate file for mTLS.

  --tls-client-key-file FILE
      Client private key file for mTLS.

  --tls-allow-insecure
      Skip TLS certificate verification.

  --print-command
      Print the final `hubble status ...` command to stderr before execution.

  --dry-run
      Print the final command to stderr and exit without running Hubble.

  -h, --help
      Show this help text.

Examples:
  # This repo: bare invocation auto-port-forwards via ~/.kube/kind-kind-local.yaml
  ./hubble-check-connection.sh

  # This repo: explicit Hubble CLI port-forward
  ./hubble-check-connection.sh -P --kubeconfig ~/.kube/kind-kind-local.yaml

  # This repo: manual relay port-forward already in place
  kubectl -n kube-system port-forward service/hubble-relay 4245:4245
  ./hubble-check-connection.sh --server localhost:4245

  # Remote relay exposed directly over TLS
  ./hubble-check-connection.sh --server https://relay.example.com

  # A Hubble UI route will be called out explicitly as the wrong endpoint
  ./hubble-check-connection.sh --server https://hubble.admin.127.0.0.1.sslip.io
EOF
}

fail() {
  echo "hubble-check-connection.sh: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

extract_host_and_port() {
  local value="$1"
  local host=""
  local port=""

  if [[ "${value}" =~ ^\[([0-9A-Fa-f:]+)\]:(.+)$ ]]; then
    host="${BASH_REMATCH[1]}"
    port="${BASH_REMATCH[2]}"
  elif [[ "${value}" =~ ^\[([0-9A-Fa-f:]+)\]$ ]]; then
    host="${BASH_REMATCH[1]}"
  elif [[ "${value}" == *:* ]]; then
    host="${value%%:*}"
    port="${value##*:}"
  else
    host="${value}"
  fi

  PARSED_HOST="${host}"
  PARSED_PORT="${port}"
}

normalise_server_input() {
  local input="$1"
  local scheme=""
  local authority=""
  local host=""
  local port=""

  case "${input}" in
    https://*)
      scheme="https"
      authority="${input#https://}"
      authority="${authority%%/*}"
      ;;
    http://*)
      scheme="http"
      authority="${input#http://}"
      authority="${authority%%/*}"
      ;;
    tls://*)
      scheme="tls"
      authority="${input#tls://}"
      authority="${authority%%/*}"
      ;;
    *)
      SERVER_VALUE="${input}"
      SERVER_TLS_HOST=""
      SERVER_SCHEME=""
      return 0
      ;;
  esac

  [[ -n "${authority}" ]] || fail "server URL is missing a host: ${input}"

  extract_host_and_port "${authority}"
  host="${PARSED_HOST}"
  port="${PARSED_PORT}"

  [[ -n "${host}" ]] || fail "server URL is missing a host: ${input}"

  case "${scheme}" in
    https)
      if [[ -z "${port}" ]]; then
        port="443"
      fi
      SERVER_VALUE="tls://${host}:${port}"
      SERVER_TLS_HOST="${host}"
      SERVER_SCHEME="${scheme}"
      ;;
    http)
      if [[ -z "${port}" ]]; then
        port="80"
      fi
      SERVER_VALUE="${host}:${port}"
      SERVER_TLS_HOST=""
      SERVER_SCHEME="${scheme}"
      ;;
    tls)
      if [[ -z "${port}" ]]; then
        fail "tls:// server URLs must include an explicit port"
      fi
      SERVER_VALUE="tls://${host}:${port}"
      SERVER_TLS_HOST="${host}"
      SERVER_SCHEME="${scheme}"
      ;;
  esac
}

server_value_host_and_port() {
  local value="$1"
  local authority="${value}"

  if [[ "${authority}" == tls://* ]]; then
    authority="${authority#tls://}"
  fi

  extract_host_and_port "${authority}"
}

is_local_host() {
  case "$1" in
    localhost|127.0.0.1|::1)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

check_local_listener() {
  local host="$1"
  local port="$2"

  if command -v nc >/dev/null 2>&1; then
    nc -z "${host}" "${port}" >/dev/null 2>&1
    return $?
  fi

  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  return 2
}

explain_probable_ui_route_error() {
  local hubble_error="$1"

  if [[ "${hubble_error}" == *"unexpected HTTP status code received from server:"* ]] \
    || [[ "${hubble_error}" == *"missing HTTP content-type"* ]]; then
    cat >&2 <<EOF
hubble-check-connection.sh: the server did not behave like a Hubble Relay gRPC endpoint.
hubble-check-connection.sh: this usually means --server is pointing at a browser/UI route or auth proxy instead of hubble-relay.
hubble-check-connection.sh: in this repo, https://hubble.admin.127.0.0.1.sslip.io is the Hubble UI route, not the relay API.
hubble-check-connection.sh: use localhost:4245, --port-forward, or a Cloudflare/Tailscale endpoint that exposes hubble-relay itself.
EOF
  fi
}

explain_probable_local_port_forward_error() {
  local host="$1"
  local port="$2"

  cat >&2 <<EOF
hubble-check-connection.sh: ${host}:${port} is not listening on this machine.
hubble-check-connection.sh: on this cluster, that usually means no local port-forward is running yet.
hubble-check-connection.sh: either rerun with --port-forward, or start:
hubble-check-connection.sh:   kubectl -n kube-system port-forward service/hubble-relay ${port}:4245
EOF
}

server=""
port_forward=0
port_forward_port=""
kubeconfig=""
kube_context=""
kube_namespace="kube-system"
print_command=0
dry_run=0
tls_enabled=0
tls_allow_insecure=0
tls_server_name=""
tls_client_cert_file=""
tls_client_key_file=""
SERVER_VALUE=""
SERVER_TLS_HOST=""
SERVER_SCHEME=""
PARSED_HOST=""
PARSED_PORT=""
DEFAULT_KIND_KUBECONFIG="${HOME}/.kube/kind-kind-local.yaml"

declare -a tls_ca_cert_files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)
      server="${2:-}"
      shift 2
      ;;
    -P|--port-forward)
      port_forward=1
      shift
      ;;
    --port-forward-port)
      port_forward_port="${2:-}"
      shift 2
      ;;
    --kubeconfig)
      kubeconfig="${2:-}"
      shift 2
      ;;
    --kube-context)
      kube_context="${2:-}"
      shift 2
      ;;
    --kube-namespace)
      kube_namespace="${2:-}"
      shift 2
      ;;
    --tls)
      tls_enabled=1
      shift
      ;;
    --tls-server-name)
      tls_server_name="${2:-}"
      shift 2
      ;;
    --tls-ca-cert-file)
      tls_ca_cert_files+=("${2:-}")
      shift 2
      ;;
    --tls-client-cert-file)
      tls_client_cert_file="${2:-}"
      shift 2
      ;;
    --tls-client-key-file)
      tls_client_key_file="${2:-}"
      shift 2
      ;;
    --tls-allow-insecure)
      tls_allow_insecure=1
      shift
      ;;
    --print-command)
      print_command=1
      shift
      ;;
    --dry-run)
      dry_run=1
      print_command=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

require_cmd hubble

if [[ -n "${server}" && "${port_forward}" -eq 1 ]]; then
  fail "--server and --port-forward cannot be combined"
fi

if [[ -z "${server}" && "${port_forward}" -eq 0 ]]; then
  port_forward=1
  if [[ -z "${kubeconfig}" && -z "${KUBECONFIG:-}" && -f "${DEFAULT_KIND_KUBECONFIG}" ]]; then
    kubeconfig="${DEFAULT_KIND_KUBECONFIG}"
  fi
fi

if [[ -n "${server}" ]]; then
  normalise_server_input "${server}"
  server="${SERVER_VALUE}"
  if [[ -z "${tls_server_name}" && -n "${SERVER_TLS_HOST}" ]]; then
    tls_server_name="${SERVER_TLS_HOST}"
  fi
  if [[ "${SERVER_SCHEME}" == "https" || "${SERVER_SCHEME}" == "tls" ]]; then
    tls_enabled=1
  fi
fi

status_args=(status)

if [[ -n "${server}" ]]; then
  status_args+=(--server "${server}")
fi

if [[ "${tls_enabled}" -eq 1 ]]; then
  status_args+=(--tls)
fi

if [[ -n "${tls_server_name}" ]]; then
  status_args+=(--tls-server-name "${tls_server_name}")
fi

if [[ "${#tls_ca_cert_files[@]}" -gt 0 ]]; then
  for value in "${tls_ca_cert_files[@]}"; do
    status_args+=(--tls-ca-cert-files "${value}")
  done
fi

if [[ -n "${tls_client_cert_file}" ]]; then
  status_args+=(--tls-client-cert-file "${tls_client_cert_file}")
fi

if [[ -n "${tls_client_key_file}" ]]; then
  status_args+=(--tls-client-key-file "${tls_client_key_file}")
fi

if [[ "${tls_allow_insecure}" -eq 1 ]]; then
  status_args+=(--tls-allow-insecure)
fi

if [[ "${port_forward}" -eq 1 ]]; then
  status_args+=(--port-forward)
  if [[ -n "${port_forward_port}" ]]; then
    status_args+=(--port-forward-port "${port_forward_port}")
  fi
  if [[ -n "${kubeconfig}" ]]; then
    status_args+=(--kubeconfig "${kubeconfig}")
  fi
  if [[ -n "${kube_context}" ]]; then
    status_args+=(--kube-context "${kube_context}")
  fi
  status_args+=(--kube-namespace "${kube_namespace}")
fi

if [[ "${print_command}" -eq 1 ]]; then
  printf 'hubble'
  printf ' %q' "${status_args[@]}"
  printf '\n' >&2
fi

if [[ "${dry_run}" -eq 1 ]]; then
  exit 0
fi

if [[ -n "${server}" ]]; then
  server_value_host_and_port "${server}"
  if [[ -n "${PARSED_HOST}" && -n "${PARSED_PORT}" ]] && is_local_host "${PARSED_HOST}"; then
    listener_status=2
    if check_local_listener "${PARSED_HOST}" "${PARSED_PORT}"; then
      echo "hubble-check-connection.sh: local listener detected on ${PARSED_HOST}:${PARSED_PORT}" >&2
    else
      listener_status=$?
      if [[ "${listener_status}" -eq 1 ]]; then
        explain_probable_local_port_forward_error "${PARSED_HOST}" "${PARSED_PORT}"
        exit 1
      fi
      echo "hubble-check-connection.sh: could not verify whether ${PARSED_HOST}:${PARSED_PORT} is listening locally" >&2
    fi
  fi
fi

tmp_hubble_out="$(mktemp "${TMPDIR:-/tmp}/hubble-check.out.XXXXXX")"
tmp_hubble_err="$(mktemp "${TMPDIR:-/tmp}/hubble-check.err.XXXXXX")"
trap 'rm -f "${tmp_hubble_out}" "${tmp_hubble_err}"' EXIT

hubble_status=0
hubble "${status_args[@]}" > "${tmp_hubble_out}" 2> "${tmp_hubble_err}" || hubble_status=$?

if [[ "${hubble_status}" -ne 0 ]]; then
  hubble_error="$(cat "${tmp_hubble_err}")"
  if [[ -n "${hubble_error}" ]]; then
    explain_probable_ui_route_error "${hubble_error}"
    printf '%s\n' "${hubble_error}" >&2
  fi
  exit "${hubble_status}"
fi

if [[ -s "${tmp_hubble_err}" ]]; then
  cat "${tmp_hubble_err}" >&2
fi

cat "${tmp_hubble_out}"
