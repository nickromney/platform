#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/../../../scripts/lib/shell-cli.sh"

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
Port-forward mode requires Kubernetes API access to `get services`, `get pods`,
and `create pods/portforward` in the relay namespace.

Options:
  -o, --output FILE
      Write flow JSON lines to FILE instead of stdout.

  --capture-strategy since|last|adaptive
      Capture using a time window, a bounded last-N sample, or an adaptive
      recent-sample-first strategy. Default: since

  --since DURATION
      Capture flows since DURATION. Default: 10m

  --last N
      Request the last N flows instead of using --since.

  --sample-target N
      Target sample size used by `--capture-strategy last|adaptive`.
      Default: 1000

  --sample-min N
      Minimum non-reply usable flow count for adaptive capture before it stops
      escalating. Default: 200

  --field-mask-profile full|policy-observe
      Request a reduced Hubble field set when supported. Default: full

  -f, --follow
      Follow flows.

  --namespace NS
      Repeatable filter for flows where either side is in NS.

  --from-namespace NS
      Repeatable source namespace filter.

  --to-namespace NS
      Repeatable destination namespace filter.
      This filters only the destination side of the flow. It is normal to pair
      this with `hubble-summarise-flows.sh --direction egress` when you want
      to study workloads sending traffic into NS.

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
  # This cluster: explicit execution auto-port-forwards via ~/.kube/kind-kind-local.yaml
  ./hubble-capture-flows.sh --execute \
    --since 15m --namespace observability

  # This cluster: explicit port-forward mode also works
  ./hubble-capture-flows.sh --execute -P --kubeconfig ~/.kube/kind-kind-local.yaml \
    --since 15m --namespace observability

  # This cluster: manual relay port-forward on the host first
  kubectl -n kube-system port-forward service/hubble-relay 4245:4245
  ./hubble-capture-flows.sh --execute --server localhost:4245 --since 15m \
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
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

fail() {
  echo "hubble-capture-flows.sh: $*" >&2
  exit 1
}

info() {
  echo "hubble-capture-flows.sh: $*" >&2
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

filter_non_reply_capture() {
  local input_file="$1"
  local output_file="$2"

  jq -c 'select((((.flow // .).is_reply) // false) != true)' "${input_file}" > "${output_file}"
}

count_capture_lines() {
  local input_file="$1"

  awk 'END { print NR + 0 }' "${input_file}"
}

adaptive_last_steps() {
  local target="$1"
  local -a steps=()
  local step=""

  if [[ "${target}" -le 100 ]]; then
    steps=("${target}")
  elif [[ "${target}" -le 300 ]]; then
    steps=(100 "${target}")
  else
    steps=(100 300 "${target}")
  fi

  for step in "${steps[@]}"; do
    [[ -n "${step}" ]] || continue
    [[ "${step}" -gt 0 ]] || continue
    printf '%s\n' "${step}"
  done | awk '!seen[$0]++'
}

supports_experimental_field_mask() {
  if [[ -n "${SUPPORTS_EXPERIMENTAL_FIELD_MASK:-}" ]]; then
    [[ "${SUPPORTS_EXPERIMENTAL_FIELD_MASK}" == "1" ]]
    return $?
  fi

  if hubble observe --help 2>/dev/null | grep -q -- "--experimental-field-mask"; then
    SUPPORTS_EXPERIMENTAL_FIELD_MASK="1"
    return 0
  fi

  SUPPORTS_EXPERIMENTAL_FIELD_MASK="0"
  return 1
}

policy_observe_field_mask() {
  printf '%s\n' \
    "verdict,traffic_direction,is_reply,source,destination,source_names,destination_names,IP,l4,l7.dns"
}

has_experimental_field_mask_arg() {
  local arg=""

  for arg in "$@"; do
    if [[ "${arg}" == "--experimental-field-mask" ]]; then
      return 0
    fi
  done

  return 1
}

strip_experimental_field_mask_args() {
  local skip_next=0
  local arg=""

  STRIPPED_OBSERVE_ARGS=()
  for arg in "$@"; do
    if [[ "${skip_next}" -eq 1 ]]; then
      skip_next=0
      continue
    fi
    if [[ "${arg}" == "--experimental-field-mask" ]]; then
      skip_next=1
      continue
    fi
    STRIPPED_OBSERVE_ARGS+=("${arg}")
  done
}

append_field_mask_args() {
  case "${field_mask_profile}" in
    full)
      ;;
    policy-observe)
      if [[ "${DISABLE_EXPERIMENTAL_FIELD_MASK:-0}" -ne 1 ]] && supports_experimental_field_mask; then
        observe_args+=(--experimental-field-mask "$(policy_observe_field_mask)")
      fi
      ;;
  esac
}

build_common_observe_args() {
  observe_args=(observe --output jsonpb)

  append_field_mask_args

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
}

run_hubble_with_args() {
  local output_file="$1"
  shift

  local hubble_status=0
  local retry_status=0

  if [[ "${print_command}" -eq 1 ]]; then
    {
      printf 'hubble'
      printf ' %q' "$@"
      printf '\n'
    } >&2
  fi

  if [[ "${dry_run}" -eq 1 ]]; then
    return 0
  fi

  hubble "$@" > "${output_file}" 2> "${tmp_hubble_err}" || hubble_status=$?

  if [[ "${hubble_status}" -ne 0 ]]; then
    hubble_error="$(cat "${tmp_hubble_err}")"
    if [[ "${hubble_error}" == *"failed to construct field mask"* ]] && has_experimental_field_mask_arg "$@"; then
      DISABLE_EXPERIMENTAL_FIELD_MASK=1
      strip_experimental_field_mask_args "$@"
      info "experimental field mask was rejected by this Hubble version; retrying without it"
      : > "${tmp_hubble_err}"
      retry_status=0
      hubble "${STRIPPED_OBSERVE_ARGS[@]}" > "${output_file}" 2> "${tmp_hubble_err}" || retry_status=$?
      if [[ "${retry_status}" -eq 0 ]]; then
        if [[ -s "${tmp_hubble_err}" ]]; then
          cat "${tmp_hubble_err}" >&2
          : > "${tmp_hubble_err}"
        fi
        return 0
      fi
      hubble_status="${retry_status}"
      hubble_error="$(cat "${tmp_hubble_err}")"
    fi

    if [[ -n "${hubble_error}" ]]; then
      explain_probable_ui_route_error "${hubble_error}"
      explain_probable_local_port_forward_error "${hubble_error}" "${server}"
      printf '%s\n' "${hubble_error}" >&2
    fi
    return "${hubble_status}"
  fi

  if [[ -s "${tmp_hubble_err}" ]]; then
    cat "${tmp_hubble_err}" >&2
    : > "${tmp_hubble_err}"
  fi
}

run_single_capture() {
  local query_kind="$1"
  local query_value="$2"
  local output_file="$3"

  build_common_observe_args
  case "${query_kind}" in
    last)
      observe_args+=(--last "${query_value}")
      ;;
    since)
      observe_args+=(--since "${query_value}")
      ;;
    *)
      fail "unsupported capture query kind: ${query_kind}"
      ;;
  esac

  run_hubble_with_args "${output_file}" "${observe_args[@]}"
}

run_adaptive_capture() {
  local final_output="$1"
  local attempt=""
  local capture_file=""
  local usable_file=""
  local usable_count=0
  local selected_file=""
  local fallback_file=""
  local -a attempt_files=()

  while IFS= read -r attempt; do
    [[ -n "${attempt}" ]] || continue
    capture_file="$(mktemp "${TMPDIR:-/tmp}/hubble-capture.last.${attempt}.XXXXXX")"
    usable_file="$(mktemp "${TMPDIR:-/tmp}/hubble-capture.last-usable.${attempt}.XXXXXX")"
    attempt_files+=("${capture_file}" "${usable_file}")

    info "adaptive capture: trying last ${attempt}"
    if ! run_single_capture "last" "${attempt}" "${capture_file}"; then
      rm -f "${attempt_files[@]}"
      return 1
    fi

    if [[ "${dry_run}" -eq 1 ]]; then
      continue
    fi

    filter_non_reply_capture "${capture_file}" "${usable_file}"
    usable_count="$(count_capture_lines "${usable_file}")"
    info "adaptive capture: last ${attempt} produced ${usable_count} non-reply flows"

    if [[ "${usable_count}" -ge "${sample_min}" ]]; then
      selected_file="${capture_file}"
      break
    fi
  done < <(adaptive_last_steps "${sample_target}")

  if [[ "${dry_run}" -eq 1 ]]; then
    return 0
  fi

  if [[ -z "${selected_file}" ]]; then
    fallback_file="$(mktemp "${TMPDIR:-/tmp}/hubble-capture.since.XXXXXX")"
    attempt_files+=("${fallback_file}")
    info "adaptive capture: recent sample too sparse; falling back to since ${since_value}"
    if ! run_single_capture "since" "${since_value}" "${fallback_file}"; then
      rm -f "${attempt_files[@]}"
      return 1
    fi
    selected_file="${fallback_file}"
  fi

  cat "${selected_file}" > "${final_output}"
  rm -f "${attempt_files[@]}"
}

kubectl_can_i() {
  local verb="$1"
  local resource="$2"
  local namespace="${3:-}"
  local args=(auth can-i "${verb}" "${resource}")
  local output=""

  if [[ -n "${namespace}" ]]; then
    args+=(-n "${namespace}")
  fi

  if ! output="$("${KUBECTL_BASE[@]}" "${args[@]}" 2>/dev/null)"; then
    CAN_I_ERROR_MSG="failed to query Kubernetes access with: kubectl ${args[*]}"
    return 2
  fi

  output="${output##*$'\n'}"
  output="${output//[[:space:]]/}"

  case "${output}" in
    yes)
      return 0
      ;;
    no)
      return 1
      ;;
    *)
      CAN_I_ERROR_MSG="unexpected output from kubectl ${args[*]}: ${output}"
      return 2
      ;;
  esac
}

require_kubectl_permission() {
  local verb="$1"
  local resource="$2"
  local namespace="$3"
  local reason="$4"
  local scope_msg=""
  local scope_cmd=""
  local status=0

  if [[ -n "${namespace}" ]]; then
    scope_msg=" in namespace ${namespace}"
    scope_cmd=" -n ${namespace}"
  fi

  if kubectl_can_i "${verb}" "${resource}" "${namespace}"; then
    return 0
  fi
  status=$?

  if [[ "${status}" -eq 2 ]]; then
    fail "${CAN_I_ERROR_MSG}"
  fi

  fail "missing required Kubernetes permission to ${reason}: cannot ${verb} ${resource}${scope_msg}. Check: kubectl auth can-i ${verb} ${resource}${scope_cmd}"
}

preflight_port_forward_permissions() {
  require_kubectl_permission "get" "services" "${kube_namespace}" "look up the Hubble relay Service for port-forward mode"
  require_kubectl_permission "get" "pods" "${kube_namespace}" "locate the Hubble relay pod for port-forward mode"
  require_kubectl_permission "create" "pods/portforward" "${kube_namespace}" "open a Hubble relay port-forward"
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
capture_strategy="since"
since_value="10m"
last_value=""
since_set=0
last_set=0
sample_target="1000"
sample_min="200"
field_mask_profile="full"
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

shell_cli_init_standard_flags

while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    -o|--output)
      output_path="${2:-}"
      shift 2
      ;;
    --capture-strategy)
      capture_strategy="${2:-}"
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
    --sample-target)
      sample_target="${2:-}"
      shift 2
      ;;
    --sample-min)
      sample_min="${2:-}"
      shift 2
      ;;
    --field-mask-profile)
      field_mask_profile="${2:-}"
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

if [[ "${SHELL_CLI_DRY_RUN}" -eq 1 ]]; then
  dry_run=1
  print_command=1
elif [[ "${SHELL_CLI_EXECUTE}" -ne 1 ]]; then
  usage
  shell_cli_print_dry_run_summary "would capture Hubble flows using strategy=${capture_strategy}"
  dry_run=1
  print_command=1
fi

if [[ "${dry_run}" -eq 0 ]]; then
  require_cmd hubble
fi

if [[ "${since_set}" -eq 1 && "${last_set}" -eq 1 ]]; then
  fail "--since and --last cannot be combined"
fi

case "${capture_strategy}" in
  since|last|adaptive) ;;
  *)
    fail "--capture-strategy must be one of: since, last, adaptive"
    ;;
esac

case "${field_mask_profile}" in
  full|policy-observe) ;;
  *)
    fail "--field-mask-profile must be one of: full, policy-observe"
    ;;
esac

[[ "${sample_target}" =~ ^[0-9]+$ ]] || fail "--sample-target must be a non-negative integer"
[[ "${sample_min}" =~ ^[0-9]+$ ]] || fail "--sample-min must be a non-negative integer"
[[ "${sample_target}" -gt 0 ]] || fail "--sample-target must be greater than zero"

if [[ "${capture_strategy}" == "adaptive" && "${dry_run}" -eq 0 ]]; then
  require_cmd jq
fi

if [[ "${since_set}" -eq 0 && "${last_set}" -eq 0 ]]; then
  case "${capture_strategy}" in
    since)
      since_value="10m"
      ;;
    last)
      last_value="${sample_target}"
      last_set=1
      since_value=""
      ;;
    adaptive)
      :
      ;;
  esac
elif [[ "${last_set}" -eq 1 ]]; then
  if [[ "${capture_strategy}" == "adaptive" ]]; then
    sample_target="${last_value}"
  fi
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

if [[ "${port_forward}" -eq 1 ]]; then
  require_cmd kubectl
  KUBECTL_BASE=(kubectl)
  if [[ -n "${kubeconfig}" ]]; then
    KUBECTL_BASE+=(--kubeconfig "${kubeconfig}")
  fi
  if [[ -n "${kube_context}" ]]; then
    KUBECTL_BASE+=(--context "${kube_context}")
  fi

  if [[ "${dry_run}" -eq 0 ]]; then
    preflight_port_forward_permissions
  fi
fi

tmp_hubble_err="$(mktemp "${TMPDIR:-/tmp}/hubble-capture.err.XXXXXX")"
trap 'rm -f "${tmp_hubble_err}"' EXIT

tmp_capture_out="$(mktemp "${TMPDIR:-/tmp}/hubble-capture.out.XXXXXX")"
trap 'rm -f "${tmp_hubble_err}" "${tmp_capture_out}"' EXIT

case "${capture_strategy}" in
  since)
    query_kind="since"
    query_value="${since_value}"
    if [[ -n "${last_value}" ]]; then
      query_kind="last"
      query_value="${last_value}"
    fi
    run_single_capture "${query_kind}" "${query_value}" "${tmp_capture_out}" || exit $?
    ;;
  last)
    run_single_capture "last" "${last_value}" "${tmp_capture_out}" || exit $?
    ;;
  adaptive)
    run_adaptive_capture "${tmp_capture_out}" || exit $?
    ;;
esac

if [[ "${dry_run}" -eq 1 ]]; then
  exit 0
fi

if [[ -n "${output_path}" ]]; then
  mkdir -p "$(dirname "${output_path}")"
  cat "${tmp_capture_out}" > "${output_path}"
else
  cat "${tmp_capture_out}"
fi
