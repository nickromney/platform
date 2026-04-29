#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"

FAILURES=0

fail() { echo "FAIL $*" >&2; exit 1; }
fail_soft() { echo "FAIL $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN $*"; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF' | sed "1s|@SCRIPT_NAME@|${0##*/}|"
Usage: @SCRIPT_NAME@ [--var-file PATH] [--host-port PORT] [--wait-seconds N] [--retry-interval-seconds N] [--extended]

Checks the NGINX Gateway Fabric + TLS path for public and admin gateway URLs.
Use --extended (or EXTENDED=1) for deeper pod/endpoint diagnostics.
EOF
  printf '\n%s\n' "$(shell_cli_standard_options)"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 not found in PATH"
}

have_cmd() {
  command -v "$1" >/dev/null 2>&1
}

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STACK_DIR=$(cd "${SCRIPT_DIR}/.." && pwd)

TFVARS_FILES=()
HOST_PORT=""
EXTENDED="${EXTENDED:-0}"
DEBUG_PRINTED=0
WAIT_SECONDS="${WAIT_SECONDS:-30}"
RETRY_INTERVAL_SECONDS="${RETRY_INTERVAL_SECONDS:-3}"
ROUTE_ENTRIES=()
DEVCONTAINER_HOST_ALIAS="${PLATFORM_DEVCONTAINER_HOST_ALIAS:-${KIND_DEVCONTAINER_HOST_ALIAS:-host.docker.internal}}"
shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --var-file)
      TFVARS_FILES+=("${2:-}")
      shift 2
      ;;
    --host-port)
      HOST_PORT="${2:-}"
      shift 2
      ;;
    --wait-seconds)
      WAIT_SECONDS="${2:-}"
      shift 2
      ;;
    --retry-interval-seconds)
      RETRY_INTERVAL_SECONDS="${2:-}"
      shift 2
      ;;
    -x|--extended|--debug)
      EXTENDED=1
      shift
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would check public and admin gateway URLs"

[[ "${WAIT_SECONDS}" =~ ^[0-9]+$ ]] || fail "--wait-seconds must be an integer >= 0"
[[ "${RETRY_INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] || fail "--retry-interval-seconds must be an integer >= 0"

if [[ "${#TFVARS_FILES[@]}" -gt 0 ]]; then
  for i in "${!TFVARS_FILES[@]}"; do
    if [[ -n "${TFVARS_FILES[i]}" && ! -f "${TFVARS_FILES[i]}" && -f "${STACK_DIR}/${TFVARS_FILES[i]}" ]]; then
      TFVARS_FILES[i]="${STACK_DIR}/${TFVARS_FILES[i]}"
    fi
  done
fi

tfvar_get() {
  local key="$2"
  local file value=""
  if [[ "${#TFVARS_FILES[@]}" -eq 0 ]]; then
    return 0
  fi
  for file in "${TFVARS_FILES[@]}"; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    value="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null | tail -n 1 | sed -E "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\"?([^\"#]+)\"?.*$/\1/" | xargs || true)"
    [[ -n "${value}" ]] || continue
  done
  echo "${value}"
}

tfvar_list_entries() {
  local key="$2"
  local file raw=""
  local entry=""
  local -a values=()

  if [[ "${#TFVARS_FILES[@]}" -eq 0 ]]; then
    return 0
  fi

  for file in "${TFVARS_FILES[@]}"; do
    [[ -n "${file}" && -f "${file}" ]] || continue
    raw="$(
      awk -v key="${key}" '
        !capture && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" { capture=1 }
        capture { print }
        capture && /\]/ { exit }
      ' "${file}" 2>/dev/null || true
    )"
    [[ -n "${raw}" ]] || continue
    values=()
    while IFS= read -r entry; do
      [[ -n "${entry}" ]] || continue
      values+=("${entry}")
    done < <(printf '%s\n' "${raw}" | grep -oE '"[^"]+"' | sed 's/^"//;s/"$//' || true)
  done

  if [[ "${#values[@]}" -gt 0 ]]; then
    printf '%s\n' "${values[@]}"
  fi
}

array_contains() {
  local needle="$1"
  shift || true

  local entry
  for entry in "$@"; do
    if [[ "${entry}" == "${needle}" ]]; then
      return 0
    fi
  done

  return 1
}

devcontainer_enabled() {
  [[ "${PLATFORM_DEVCONTAINER:-0}" == "1" ]]
}

probe_host_for_local_https() {
  if devcontainer_enabled; then
    printf '%s\n' "${DEVCONTAINER_HOST_ALIAS}"
    return 0
  fi

  printf '%s\n' "127.0.0.1"
}

debug_gateway_pods() {
  local pods
  pods=$(kubectl -n platform-gateway get pods -l gateway.networking.k8s.io/gateway-name=platform-gateway -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ -z "${pods}" ]]; then
    warn "No platform-gateway data-plane pods found"
    return 0
  fi
  while IFS= read -r pod; do
    [[ -z "${pod}" ]] && continue
    ready=$(kubectl -n platform-gateway get pod "${pod}" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    statuses=$(kubectl -n platform-gateway get pod "${pod}" -o jsonpath='{range .status.containerStatuses[*]}{.name}{": ready="}{.ready}{" restarts="}{.restartCount}{" waiting="}{.state.waiting.reason}{" terminated="}{.state.terminated.reason}{"\n"}{end}' 2>/dev/null || true)
    if [[ "${ready}" == "True" ]]; then
      ok "Pod ${pod} Ready=True"
    else
      warn "Pod ${pod} Ready=${ready:-unknown}"
    fi
    if [[ -n "${statuses}" ]]; then
      echo "${statuses}"
    fi
    echo "Pod ${pod} events:"
    kubectl -n platform-gateway describe pod "${pod}" 2>/dev/null | sed -n '/Events:/,$p' || true
    containers=$(kubectl -n platform-gateway get pod "${pod}" -o jsonpath='{range .spec.containers[*]}{.name}{"\n"}{end}' 2>/dev/null || true)
    if [[ -n "${containers}" ]]; then
      while IFS= read -r c; do
        [[ -z "${c}" ]] && continue
        echo "Logs (${pod}/${c}) last 80 lines:"
        kubectl -n platform-gateway logs "${pod}" -c "${c}" --tail=80 2>/dev/null || true
      done <<<"${containers}"
    fi
  done <<<"${pods}"
}

print_debug_context() {
  if [[ "${DEBUG_PRINTED}" -eq 1 ]]; then
    return 0
  fi
  DEBUG_PRINTED=1
  echo ""
  echo "Debug context (service/pods/labels):"
  kubectl -n platform-gateway get svc platform-gateway-nginx -o wide || true
  selector=$(kubectl -n platform-gateway get svc platform-gateway-nginx -o jsonpath='{.spec.selector}' 2>/dev/null || true)
  if [[ -n "${selector}" ]]; then
    echo "Service selector: ${selector}"
  fi
  echo ""
  echo "Pods in platform-gateway:"
  kubectl -n platform-gateway get pods -o wide --show-labels || true
  echo ""
  echo "Pods in nginx-gateway:"
  kubectl -n nginx-gateway get pods -o wide --show-labels || true
  echo ""
  echo "Pods labeled for gateway-name=platform-gateway (all namespaces):"
  kubectl get pods -A -l gateway.networking.k8s.io/gateway-name=platform-gateway -o wide --show-labels || true
  echo ""
  echo "EndpointSlices for platform-gateway-nginx:"
  kubectl -n platform-gateway get endpointslices -l kubernetes.io/service-name=platform-gateway-nginx -o wide || true
  endpoints_detail=$(kubectl -n platform-gateway get endpointslices -l kubernetes.io/service-name=platform-gateway-nginx -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" ready="}{.conditions.ready}{" serving="}{.conditions.serving}{" terminating="}{.conditions.terminating}{"\n"}{end}' 2>/dev/null || true)
  if [[ -n "${endpoints_detail}" ]]; then
    echo "EndpointSlice details:"
    echo "${endpoints_detail}"
  fi
  debug_gateway_pods
}

require_cmd kubectl
require_cmd curl
require_cmd openssl

if [[ -z "${HOST_PORT}" ]]; then
  HOST_PORT=$(tfvar_get "" gateway_https_host_port)
fi
if [[ -z "${HOST_PORT}" ]]; then
  HOST_PORT="443"
fi

PLATFORM_BASE_DOMAIN="$(tfvar_get "" platform_base_domain)"
if [[ -z "${PLATFORM_BASE_DOMAIN}" ]]; then
  PLATFORM_BASE_DOMAIN="127.0.0.1.sslip.io"
fi
PLATFORM_ADMIN_BASE_DOMAIN="$(tfvar_get "" platform_admin_base_domain)"
if [[ -z "${PLATFORM_ADMIN_BASE_DOMAIN}" ]]; then
  PLATFORM_ADMIN_BASE_DOMAIN="${PLATFORM_BASE_DOMAIN}"
fi
ADMIN_ROUTE_ALLOWLIST_ENABLED=0
if [[ -n "$(tfvar_list_entries "" admin_route_allowlist_cidrs)" ]]; then
  ADMIN_ROUTE_ALLOWLIST_ENABLED=1
fi

EXPECTED_CLUSTER_NAME="$(tfvar_get "" cluster_name)"
EXPECT_KIND_PROVISIONING="$(tfvar_get "" provision_kind_cluster)"
[ -n "${EXPECTED_CLUSTER_NAME}" ] || EXPECTED_CLUSTER_NAME="kind-local"
[ -n "${EXPECT_KIND_PROVISIONING}" ] || EXPECT_KIND_PROVISIONING="true"

normalize_route_path() {
  local path="${1:-/}"

  if [[ -z "${path}" ]]; then
    path="/"
  fi

  if [[ "${path}" != /* ]]; then
    path="/${path}"
  fi

  printf '%s\n' "${path}"
}

probe_https_url() {
  local host="$1"
  local url="$2"
  local tmp_err curl_rc code err
  local -a curl_args=()

  PROBE_OK=0
  PROBE_DETAIL=""

  if devcontainer_enabled; then
    curl_args=(--connect-to "${host}:${HOST_PORT}:${DEVCONTAINER_HOST_ALIAS}:${HOST_PORT}")
  else
    curl_args=(--resolve "${host}:${HOST_PORT}:127.0.0.1")
  fi

  tmp_err="$(mktemp)"
  set +e
  code="$(curl -k -sS -o /dev/null -w "%{http_code}" --max-time 5 "${curl_args[@]}" "${url}" 2>"${tmp_err}")"
  curl_rc=$?
  set -e
  err="$(tr '\n' ' ' <"${tmp_err}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  rm -f "${tmp_err}"

  if [[ "${code}" =~ ^[23] ]]; then
    PROBE_OK=1
    PROBE_DETAIL="${code}"
    return 0
  fi

  if [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" == "1" && "${code}" == "403" ]]; then
    PROBE_OK=1
    PROBE_DETAIL="${code} (blocked by admin allowlist from this source)"
    return 0
  fi

  if [[ "${url}" == https://mcp.*"/mcp" && ( "${code}" == "401" || "${code}" == "403" ) ]]; then
    PROBE_OK=1
    PROBE_DETAIL="${code} (MCP machine path requires bearer token)"
    return 0
  fi

  if [[ -n "${code}" && "${code}" != "000" ]]; then
    PROBE_DETAIL="${code}"
    return 0
  fi

  PROBE_DETAIL="000"
  if [[ "${curl_rc}" -ne 0 ]]; then
    PROBE_DETAIL="${PROBE_DETAIL} (curl exit ${curl_rc}${err:+: ${err}})"
  fi
}

probe_route_urls() {
  HTTPS_FAILURE_COUNT=0
  HTTPS_RESULTS=()

  if [[ "${#ROUTE_ENTRIES[@]}" -eq 0 ]]; then
    return 0
  fi

  local entry host path url
  for entry in "${ROUTE_ENTRIES[@]}"; do
    host="${entry%%|*}"
    path="${entry#*|}"
    url="https://${host}${port_suffix}${path}"

    probe_https_url "${host}" "${url}"
    if [[ "${PROBE_OK}" == "1" ]]; then
      HTTPS_RESULTS+=("OK|${url}|${PROBE_DETAIL}")
    else
      HTTPS_RESULTS+=("FAIL|${url}|${PROBE_DETAIL}")
      HTTPS_FAILURE_COUNT=$((HTTPS_FAILURE_COUNT + 1))
    fi
  done
}

probe_tls_certificate() {
  local host="$1"
  local tmp_err cert_pem check_output rc check_rc err connect_host

  TLS_CERT_OK=0
  TLS_CERT_DETAIL=""

  connect_host="$(probe_host_for_local_https)"
  tmp_err="$(mktemp)"

  set +e
  cert_pem="$(openssl s_client -connect "${connect_host}:${HOST_PORT}" -servername "${host}" </dev/null 2>"${tmp_err}" | openssl x509 2>>"${tmp_err}")"
  rc=$?
  set -e

  if [[ "${rc}" -ne 0 || -z "${cert_pem}" ]]; then
    err="$(tr '\n' ' ' <"${tmp_err}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    rm -f "${tmp_err}"
    TLS_CERT_DETAIL="certificate read failed${err:+: ${err}}"
    return 0
  fi

  set +e
  check_output="$(printf '%s\n' "${cert_pem}" | openssl x509 -noout -checkhost "${host}" 2>>"${tmp_err}")"
  check_rc=$?
  set -e
  err="$(tr '\n' ' ' <"${tmp_err}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  rm -f "${tmp_err}"

  if [[ "${check_rc}" -eq 0 ]]; then
    TLS_CERT_OK=1
    TLS_CERT_DETAIL="${check_output}"
  else
    TLS_CERT_DETAIL="${check_output:-hostname mismatch}${err:+ (${err})}"
  fi
}

probe_route_certificates() {
  TLS_CERT_FAILURE_COUNT=0
  TLS_CERT_RESULTS=()

  if [[ "${#ROUTE_ENTRIES[@]}" -eq 0 ]]; then
    return 0
  fi

  local entry host
  local -a seen_hosts=()
  for entry in "${ROUTE_ENTRIES[@]}"; do
    host="${entry%%|*}"
    if array_contains "${host}" "${seen_hosts[@]}"; then
      continue
    fi
    seen_hosts+=("${host}")

    probe_tls_certificate "${host}"
    if [[ "${TLS_CERT_OK}" == "1" ]]; then
      TLS_CERT_RESULTS+=("OK|${host}|${TLS_CERT_DETAIL}")
    else
      TLS_CERT_RESULTS+=("FAIL|${host}|${TLS_CERT_DETAIL}")
      TLS_CERT_FAILURE_COUNT=$((TLS_CERT_FAILURE_COUNT + 1))
    fi
  done
}

if [[ "${EXPECT_KIND_PROVISIONING}" == "true" ]]; then
  require_cmd kind
  echo "Checking kind cluster..."
  if ! kind get clusters 2>/dev/null | grep -qx "${EXPECTED_CLUSTER_NAME}"; then
    fail "${EXPECTED_CLUSTER_NAME} cluster not found"
  fi
  ok "${EXPECTED_CLUSTER_NAME} cluster exists"
else
  echo "Checking Kubernetes cluster..."
  ok "Using existing kubeconfig-backed cluster (${EXPECTED_CLUSTER_NAME})"
fi

kubectl get nodes >/dev/null 2>&1 || fail "kubectl cannot reach the cluster"
ok "kubectl can reach the cluster"

echo ""
echo "Gateway controller (nginx-gateway):"
if kubectl -n nginx-gateway get deploy nginx-gateway >/dev/null 2>&1; then
  desired=$(kubectl -n nginx-gateway get deploy nginx-gateway -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
  ready=$(kubectl -n nginx-gateway get deploy nginx-gateway -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
  if [[ -n "${ready}" && -n "${desired}" && "${ready}" == "${desired}" ]]; then
    ok "nginx-gateway ready (${ready}/${desired})"
  else
    warn "nginx-gateway not fully ready (ready=${ready:-0} desired=${desired:-unknown})"
  fi
else
  fail_soft "nginx-gateway deployment missing in namespace nginx-gateway"
fi

echo ""
echo "Gateway resource (platform-gateway):"
if kubectl -n platform-gateway get gateway platform-gateway >/dev/null 2>&1; then
  programmed=$(kubectl -n platform-gateway get gateway platform-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
  accepted=$(kubectl -n platform-gateway get gateway platform-gateway -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
  addresses=$(kubectl -n platform-gateway get gateway platform-gateway -o jsonpath='{range .status.addresses[*]}{.value}{" "}{end}' 2>/dev/null || true)
  if [[ "${programmed}" == "True" ]]; then
    ok "Gateway Programmed=True"
  else
    fail_soft "Gateway Programmed=${programmed:-unknown}"
  fi
  if [[ -n "${accepted}" && "${accepted}" != "True" ]]; then
    warn "Gateway Accepted=${accepted}"
  fi
  if [[ -n "${addresses}" ]]; then
    ok "Gateway addresses: ${addresses}"
  else
    warn "Gateway addresses empty"
  fi
else
  fail_soft "Gateway platform-gateway missing in namespace platform-gateway"
fi

echo ""
echo "Gateway Service (platform-gateway-nginx):"
if kubectl -n platform-gateway get svc platform-gateway-nginx >/dev/null 2>&1; then
  node_port=$(kubectl -n platform-gateway get svc platform-gateway-nginx -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}' 2>/dev/null || true)
  if [[ -n "${node_port}" ]]; then
    ok "NodePort: ${node_port}"
  else
    fail_soft "NodePort not found on service platform-gateway-nginx"
  fi
  endpoints=$(kubectl -n platform-gateway get endpoints platform-gateway-nginx -o jsonpath='{range .subsets[*].addresses[*]}{.ip}{" "}{end}' 2>/dev/null || true)
  if [[ -n "${endpoints}" ]]; then
    ok "Endpoints: ${endpoints}"
  else
    fail_soft "No endpoints for service platform-gateway-nginx"
    if [[ "${EXTENDED}" -eq 1 ]]; then
      print_debug_context
    fi
  fi
else
  fail_soft "Service platform-gateway-nginx missing in namespace platform-gateway"
  if [[ "${EXTENDED}" -eq 1 ]]; then
    print_debug_context
  fi
fi

if [[ "${EXTENDED}" -eq 1 ]]; then
  print_debug_context
fi

echo ""
echo "Certificate (platform-gateway-tls):"
if kubectl -n platform-gateway get certificate platform-gateway-tls >/dev/null 2>&1; then
  cert_ready=$(kubectl -n platform-gateway get certificate platform-gateway-tls -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if [[ "${cert_ready}" == "True" ]]; then
    ok "Certificate Ready=True"
  else
    fail_soft "Certificate Ready=${cert_ready:-unknown}"
  fi
  if kubectl -n platform-gateway get secret platform-gateway-tls >/dev/null 2>&1; then
    ok "TLS secret exists: platform-gateway-tls"
  else
    fail_soft "TLS secret missing: platform-gateway-tls"
  fi
else
  fail_soft "Certificate platform-gateway-tls not found"
fi

echo ""
echo "HTTPRoutes (gateway-routes):"
if kubectl -n gateway-routes get httproute >/dev/null 2>&1; then
  routes=$(kubectl -n gateway-routes get httproute -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ -z "${routes}" ]]; then
    fail_soft "No HTTPRoutes found in namespace gateway-routes"
  else
    while IFS= read -r route; do
      [[ -z "${route}" ]] && continue
      route_path_lines=$(kubectl -n gateway-routes get httproute "${route}" -o jsonpath='{range .spec.rules[*].matches[*]}{.path.value}{"\n"}{end}' 2>/dev/null || true)
      route_path="$(printf '%s\n' "${route_path_lines}" | awk 'length > 0 { print; exit }')"
      route_path="$(normalize_route_path "${route_path}")"
      hostnames=$(kubectl -n gateway-routes get httproute "${route}" -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null || true)
      accepted=$(kubectl -n gateway-routes get httproute "${route}" -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
      resolved=$(kubectl -n gateway-routes get httproute "${route}" -o jsonpath='{.status.parents[0].conditions[?(@.type=="ResolvedRefs")].status}' 2>/dev/null || true)
      if [[ "${accepted}" == "True" ]]; then
        ok "HTTPRoute ${route} Accepted=True (${hostnames})"
      else
        fail_soft "HTTPRoute ${route} Accepted=${accepted:-unknown} (${hostnames})"
      fi
      if [[ -n "${resolved}" && "${resolved}" != "True" ]]; then
        warn "HTTPRoute ${route} ResolvedRefs=${resolved}"
      fi

      hostnames_lines="$(printf '%s\n' "${hostnames}" | tr ' ' '\n' | awk 'NF > 0')"
      while IFS= read -r hostname; do
        [[ -n "${hostname}" ]] || continue
        route_entry="${hostname}|${route_path}"
        if [[ "${#ROUTE_ENTRIES[@]}" -eq 0 ]] || ! array_contains "${route_entry}" "${ROUTE_ENTRIES[@]}"; then
          ROUTE_ENTRIES+=("${route_entry}")
        fi
      done <<<"${hostnames_lines}"
    done <<<"${routes}"
  fi
else
  fail_soft "Namespace gateway-routes missing or no HTTPRoute support"
fi

echo ""
echo "Local HTTPS checks (host port ${HOST_PORT}):"
port_suffix=""
if [[ "${HOST_PORT}" != "443" ]]; then
  port_suffix=":${HOST_PORT}"
fi

local_https_probe_host="$(probe_host_for_local_https)"
if have_cmd nc; then
  if nc -z -w 2 "${local_https_probe_host}" "${HOST_PORT}" >/dev/null 2>&1; then
    ok "Host port open: ${local_https_probe_host}:${HOST_PORT}"
  else
    fail_soft "Host port not reachable: ${local_https_probe_host}:${HOST_PORT}"
  fi
fi

if [[ "${#ROUTE_ENTRIES[@]}" -eq 0 ]]; then
  fail_soft "No gateway route hostnames available to probe"
else
  deadline=$((SECONDS + WAIT_SECONDS))
  probe_route_urls
  while [[ "${HTTPS_FAILURE_COUNT}" -gt 0 && "${SECONDS}" -lt "${deadline}" ]]; do
    warn "HTTPS routes not ready yet (${HTTPS_FAILURE_COUNT} failing); retrying in ${RETRY_INTERVAL_SECONDS}s"
    sleep "${RETRY_INTERVAL_SECONDS}"
    probe_route_urls
  done

  if [[ "${#HTTPS_RESULTS[@]}" -gt 0 ]]; then
    for result in "${HTTPS_RESULTS[@]}"; do
      status="${result%%|*}"
      rest="${result#*|}"
      url="${rest%%|*}"
      detail="${rest#*|}"
      if [[ "${status}" == "OK" ]]; then
        ok "HTTPS ${url} -> ${detail}"
      else
        fail_soft "HTTPS ${url} -> ${detail}"
      fi
    done
  fi
fi

echo ""
echo "TLS certificate hostname checks (host port ${HOST_PORT}):"
if [[ "${#ROUTE_ENTRIES[@]}" -eq 0 ]]; then
  fail_soft "No gateway route hostnames available to check certificate SAN coverage"
else
  probe_route_certificates
  while [[ "${TLS_CERT_FAILURE_COUNT}" -gt 0 && "${SECONDS}" -lt "${deadline}" ]]; do
    warn "TLS certificate hostnames not ready yet (${TLS_CERT_FAILURE_COUNT} failing); retrying in ${RETRY_INTERVAL_SECONDS}s"
    sleep "${RETRY_INTERVAL_SECONDS}"
    probe_route_certificates
  done

  if [[ "${#TLS_CERT_RESULTS[@]}" -gt 0 ]]; then
    for result in "${TLS_CERT_RESULTS[@]}"; do
      status="${result%%|*}"
      rest="${result#*|}"
      host="${rest%%|*}"
      detail="${rest#*|}"
      if [[ "${status}" == "OK" ]]; then
        ok "TLS certificate ${host} -> ${detail}"
      else
        fail_soft "TLS certificate ${host} -> ${detail}"
      fi
    done
  fi
fi

if [[ "${FAILURES}" -gt 0 ]]; then
  echo ""
  fail "${FAILURES} check(s) failed"
fi
