#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: hubble-capture-flows.sh [options] [-- <extra hubble observe args>]

Capture Hubble flows as `jsonpb` so they can be piped into
`hubble-summarise-flows.sh` or saved for later policy analysis.
The `jsonpb` output is newline-delimited JSON on stdout, not JSONP.

If you do not pass any namespace or pod filters, the script defaults to the
namespaces currently under review for policy work:

  argocd
  dev
  kyverno
  nginx-gateway
  observability

If you do not pass `--server`, the script defaults to Hubble CLI port-forward
mode. In this repo, if `~/.kube/kind-kind-local.yaml` exists and `KUBECONFIG`
is not already set, that kubeconfig is used automatically so the local kind
cluster works out of the box.

Options:
  -o, --output FILE
      Write flow JSON lines to FILE instead of stdout.

  --since DURATION
      Capture flows since DURATION. Default: 10m

  --last N
      Request the last N flows instead of using --since.

  -f, --follow
      Follow flows.

  --namespace NS
      Repeatable filter for flows where either side is in NS.

  --from-namespace NS
      Repeatable source namespace filter.

  --to-namespace NS
      Repeatable destination namespace filter.

  --pod POD
      Repeatable filter for flows related to POD.

  --from-pod POD
      Repeatable source pod filter.

  --to-pod POD
      Repeatable destination pod filter.

  --protocol PROTO
      Repeatable protocol filter passed through to `hubble observe`.

  --verdict VERDICT
      Repeatable verdict filter, for example FORWARDED or DROPPED.

  --type TYPE[:SUBTYPE]
      Repeatable event type filter, for example `drop` or `policy-verdict`.

  --world-only
      Restrict the capture to flows touching `reserved:world`.

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
      For this cluster specifically, the shipped relay surfaces are:
      - in-cluster: `hubble-relay.kube-system.svc.cluster.local:4245`
      - host-side: `localhost:4245` via `--port-forward` or manual port-forward

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

  --no-default-namespaces
      Disable the default argocd/dev/kyverno/nginx-gateway/observability
      namespace set.

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
      Print the final `hubble observe ...` command to stderr before execution.

  --dry-run
      Print the final command to stderr and exit without running Hubble.

  -h, --help
      Show this help text.

Examples:
  # Examples below assume you are already in terraform/kubernetes/scripts/.
  # This cluster: bare invocation auto-port-forwards via ~/.kube/kind-kind-local.yaml
  ./hubble-capture-flows.sh \
    --since 15m --namespace observability

  # This cluster: explicit port-forward mode also works
  ./hubble-capture-flows.sh -P --kubeconfig ~/.kube/kind-kind-local.yaml \
    --since 15m --namespace observability

  # This cluster: manual relay port-forward on the host first
  kubectl -n kube-system port-forward service/hubble-relay 4245:4245
  ./hubble-capture-flows.sh --server localhost:4245 --since 15m \
    --namespace dev --namespace observability

  # Generic remote relay examples for work systems
  ./hubble-capture-flows.sh --server https://relay.example.com \
    --since 15m --namespace observability

  ./hubble-capture-flows.sh --server https://hubble.tailnet.ts.net:4443 \
    --tls-server-name hubble.tailnet.ts.net --since 15m --namespace argocd

  ./hubble-capture-flows.sh -P --kubeconfig ~/.kube/kind-kind-local.yaml --since 10m \
    --from-namespace dev --to-namespace observability \
    | ./hubble-summarise-flows.sh \
        --report edges --aggregate-by workload --direction egress

  ./hubble-capture-flows.sh -P --kubeconfig ~/.kube/kind-kind-local.yaml \
    --from-namespace dev --to-namespace observability --last 100
EOF
}

fail() {
  echo "hubble-capture-flows.sh: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

explain_probable_ui_route_error() {
  local hubble_error="$1"

  if [[ "${hubble_error}" == *"unexpected HTTP status code received from server:"* ]] \
    || [[ "${hubble_error}" == *"missing HTTP content-type"* ]]; then
    cat >&2 <<EOF
hubble-capture-flows.sh: the server did not behave like a Hubble Relay gRPC endpoint.
hubble-capture-flows.sh: this usually means --server is pointing at a browser/UI route or auth proxy instead of hubble-relay.
hubble-capture-flows.sh: in this repo, https://hubble.admin.127.0.0.1.sslip.io is the Hubble UI route, not the relay API.
hubble-capture-flows.sh: use localhost:4245, --port-forward, or a Cloudflare/Tailscale endpoint that exposes hubble-relay itself.
EOF
  fi
}

explain_probable_local_port_forward_error() {
  local hubble_error="$1"
  local server_value="$2"

  if [[ "${hubble_error}" == *"connect: connection refused"* ]] \
    && [[ "${server_value}" == "localhost:4245" || "${server_value}" == "127.0.0.1:4245" ]]; then
    cat >&2 <<EOF
hubble-capture-flows.sh: localhost:4245 refused the connection.
hubble-capture-flows.sh: on this cluster, that usually means no local port-forward is running yet.
hubble-capture-flows.sh: the relay Service is exposed in-cluster on port 4245; host-side 4245 exists only if you create it.
hubble-capture-flows.sh: either rerun with --port-forward, or start:
hubble-capture-flows.sh:   kubectl -n kube-system port-forward service/hubble-relay 4245:4245
EOF
  fi
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

output_path=""
since_value="10m"
last_value=""
since_set=0
last_set=0
follow=0
server=""
port_forward=0
port_forward_port=""
kubeconfig=""
kube_context=""
kube_namespace="kube-system"
world_only=0
use_default_namespaces=1
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

declare -a namespaces=()
declare -a from_namespaces=()
declare -a to_namespaces=()
declare -a pods=()
declare -a from_pods=()
declare -a to_pods=()
declare -a protocols=()
declare -a verdicts=()
declare -a types=()
declare -a passthrough=()
declare -a tls_ca_cert_files=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      output_path="${2:-}"
      shift 2
      ;;
    --since)
      since_value="${2:-}"
      since_set=1
      shift 2
      ;;
    --last)
      last_value="${2:-}"
      last_set=1
      shift 2
      ;;
    -f|--follow)
      follow=1
      shift
      ;;
    --namespace)
      namespaces+=("${2:-}")
      shift 2
      ;;
    --from-namespace)
      from_namespaces+=("${2:-}")
      shift 2
      ;;
    --to-namespace)
      to_namespaces+=("${2:-}")
      shift 2
      ;;
    --pod)
      pods+=("${2:-}")
      shift 2
      ;;
    --from-pod)
      from_pods+=("${2:-}")
      shift 2
      ;;
    --to-pod)
      to_pods+=("${2:-}")
      shift 2
      ;;
    --protocol)
      protocols+=("${2:-}")
      shift 2
      ;;
    --verdict)
      verdicts+=("${2:-}")
      shift 2
      ;;
    --type)
      types+=("${2:-}")
      shift 2
      ;;
    --world-only)
      world_only=1
      shift
      ;;
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
    --no-default-namespaces)
      use_default_namespaces=0
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
    --)
      shift
      passthrough+=("$@")
      break
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

require_cmd hubble

if [[ "${since_set}" -eq 1 && "${last_set}" -eq 1 ]]; then
  fail "--since and --last cannot be combined"
fi

if [[ "${since_set}" -eq 0 && "${last_set}" -eq 0 ]]; then
  since_value="10m"
elif [[ "${last_set}" -eq 1 ]]; then
  since_value=""
fi

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

if [[ "${use_default_namespaces}" -eq 1 \
   && "${#namespaces[@]}" -eq 0 \
   && "${#from_namespaces[@]}" -eq 0 \
   && "${#to_namespaces[@]}" -eq 0 \
   && "${#pods[@]}" -eq 0 \
   && "${#from_pods[@]}" -eq 0 \
   && "${#to_pods[@]}" -eq 0 ]]; then
  namespaces=(argocd dev kyverno nginx-gateway observability)
fi

observe_args=(observe --output jsonpb)

if [[ -n "${last_value}" ]]; then
  observe_args+=(--last "${last_value}")
else
  observe_args+=(--since "${since_value}")
fi

if [[ "${follow}" -eq 1 ]]; then
  observe_args+=(--follow)
fi

if [[ -n "${server}" ]]; then
  observe_args+=(--server "${server}")
fi

if [[ "${tls_enabled}" -eq 1 ]]; then
  observe_args+=(--tls)
fi

if [[ -n "${tls_server_name}" ]]; then
  observe_args+=(--tls-server-name "${tls_server_name}")
fi

if [[ "${#tls_ca_cert_files[@]}" -gt 0 ]]; then
  for value in "${tls_ca_cert_files[@]}"; do
    observe_args+=(--tls-ca-cert-files "${value}")
  done
fi

if [[ -n "${tls_client_cert_file}" ]]; then
  observe_args+=(--tls-client-cert-file "${tls_client_cert_file}")
fi

if [[ -n "${tls_client_key_file}" ]]; then
  observe_args+=(--tls-client-key-file "${tls_client_key_file}")
fi

if [[ "${tls_allow_insecure}" -eq 1 ]]; then
  observe_args+=(--tls-allow-insecure)
fi

if [[ "${port_forward}" -eq 1 ]]; then
  observe_args+=(--port-forward)
  if [[ -n "${port_forward_port}" ]]; then
    observe_args+=(--port-forward-port "${port_forward_port}")
  fi
  if [[ -n "${kubeconfig}" ]]; then
    observe_args+=(--kubeconfig "${kubeconfig}")
  fi
  if [[ -n "${kube_context}" ]]; then
    observe_args+=(--kube-context "${kube_context}")
  fi
  observe_args+=(--kube-namespace "${kube_namespace}")
fi

if [[ "${#namespaces[@]}" -gt 0 ]]; then
  for value in "${namespaces[@]}"; do
    observe_args+=(--namespace "${value}")
  done
fi

if [[ "${#from_namespaces[@]}" -gt 0 ]]; then
  for value in "${from_namespaces[@]}"; do
    observe_args+=(--from-namespace "${value}")
  done
fi

if [[ "${#to_namespaces[@]}" -gt 0 ]]; then
  for value in "${to_namespaces[@]}"; do
    observe_args+=(--to-namespace "${value}")
  done
fi

if [[ "${#pods[@]}" -gt 0 ]]; then
  for value in "${pods[@]}"; do
    observe_args+=(--pod "${value}")
  done
fi

if [[ "${#from_pods[@]}" -gt 0 ]]; then
  for value in "${from_pods[@]}"; do
    observe_args+=(--from-pod "${value}")
  done
fi

if [[ "${#to_pods[@]}" -gt 0 ]]; then
  for value in "${to_pods[@]}"; do
    observe_args+=(--to-pod "${value}")
  done
fi

if [[ "${#protocols[@]}" -gt 0 ]]; then
  for value in "${protocols[@]}"; do
    observe_args+=(--protocol "${value}")
  done
fi

if [[ "${#verdicts[@]}" -gt 0 ]]; then
  for value in "${verdicts[@]}"; do
    observe_args+=(--verdict "${value}")
  done
fi

if [[ "${#types[@]}" -gt 0 ]]; then
  for value in "${types[@]}"; do
    observe_args+=(--type "${value}")
  done
fi

if [[ "${world_only}" -eq 1 ]]; then
  observe_args+=(--label reserved:world)
fi

if [[ "${#passthrough[@]}" -gt 0 ]]; then
  observe_args+=("${passthrough[@]}")
fi

if [[ "${print_command}" -eq 1 ]]; then
  printf 'hubble'
  printf ' %q' "${observe_args[@]}"
  printf '\n' >&2
fi

if [[ "${dry_run}" -eq 1 ]]; then
  exit 0
fi

tmp_hubble_err="$(mktemp "${TMPDIR:-/tmp}/hubble-capture.err.XXXXXX")"
trap 'rm -f "${tmp_hubble_err}"' EXIT

hubble_status=0
if [[ -n "${output_path}" ]]; then
  mkdir -p "$(dirname "${output_path}")"
  hubble "${observe_args[@]}" > "${output_path}" 2> "${tmp_hubble_err}" || hubble_status=$?
else
  hubble "${observe_args[@]}" 2> "${tmp_hubble_err}" || hubble_status=$?
fi

if [[ "${hubble_status}" -ne 0 ]]; then
  hubble_error="$(cat "${tmp_hubble_err}")"
  if [[ -n "${hubble_error}" ]]; then
    explain_probable_ui_route_error "${hubble_error}"
    explain_probable_local_port_forward_error "${hubble_error}" "${server}"
    printf '%s\n' "${hubble_error}" >&2
  fi
  exit "${hubble_status}"
fi

if [[ -s "${tmp_hubble_err}" ]]; then
  cat "${tmp_hubble_err}" >&2
fi
