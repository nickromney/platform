#!/usr/bin/env bash
set -euo pipefail

FAILURES=0

fail() { echo "FAIL $*" >&2; exit 1; }
fail_soft() { echo "FAIL $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN $*"; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF'
Usage: check-gateway-urls.sh [--var-file PATH] [--host-port PORT] [--extended]

Checks the NGINX Gateway Fabric + TLS path for public and admin gateway URLs.
Use --extended (or EXTENDED=1) for deeper pod/endpoint diagnostics.
EOF
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
while [[ $# -gt 0 ]]; do
  case "$1" in
    --var-file)
      TFVARS_FILES+=("${2:-}")
      shift 2
      ;;
    --host-port)
      HOST_PORT="${2:-}"
      shift 2
      ;;
    -x|--extended|--debug)
      EXTENDED=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

for i in "${!TFVARS_FILES[@]}"; do
  if [[ -n "${TFVARS_FILES[i]}" && ! -f "${TFVARS_FILES[i]}" && -f "${STACK_DIR}/${TFVARS_FILES[i]}" ]]; then
    TFVARS_FILES[i]="${STACK_DIR}/${TFVARS_FILES[i]}"
  fi
done

tfvar_get() {
  local key="$2"
  local file value=""
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

  printf '%s\n' "${values[@]}"
}

admin_host() {
  local app="$1"
  if [[ "${SEPARATE_ADMIN_DOMAIN}" == "1" ]]; then
    printf '%s.%s\n' "${app}" "${PLATFORM_ADMIN_BASE_DOMAIN}"
  else
    printf '%s.admin.%s\n' "${app}" "${PLATFORM_BASE_DOMAIN}"
  fi
}

dex_host() {
  printf 'dex.%s\n' "${PLATFORM_ADMIN_BASE_DOMAIN}"
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
SEPARATE_ADMIN_DOMAIN=0
if [[ -n "${PLATFORM_ADMIN_BASE_DOMAIN}" ]]; then
  SEPARATE_ADMIN_DOMAIN=1
else
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
    warn "Certificate Ready=${cert_ready:-unknown}"
  fi
  if kubectl -n platform-gateway get secret platform-gateway-tls >/dev/null 2>&1; then
    ok "TLS secret exists: platform-gateway-tls"
  else
    fail_soft "TLS secret missing: platform-gateway-tls"
  fi
else
  warn "Certificate platform-gateway-tls not found"
fi

echo ""
echo "HTTPRoutes (gateway-routes):"
if kubectl -n gateway-routes get httproute >/dev/null 2>&1; then
  routes=$(kubectl -n gateway-routes get httproute -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)
  if [[ -z "${routes}" ]]; then
    warn "No HTTPRoutes found in namespace gateway-routes"
  else
    while IFS= read -r route; do
      [[ -z "${route}" ]] && continue
      hostnames=$(kubectl -n gateway-routes get httproute "${route}" -o jsonpath='{range .spec.hostnames[*]}{.}{" "}{end}' 2>/dev/null || true)
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
    done <<<"${routes}"
  fi
else
  warn "Namespace gateway-routes missing or no HTTPRoute support"
fi

echo ""
echo "Local HTTPS checks (host port ${HOST_PORT}):"
port_suffix=""
if [[ "${HOST_PORT}" != "443" ]]; then
  port_suffix=":${HOST_PORT}"
fi

if have_cmd nc; then
  if nc -z -w 2 127.0.0.1 "${HOST_PORT}" >/dev/null 2>&1; then
    ok "Host port open: 127.0.0.1:${HOST_PORT}"
  else
    warn "Host port not reachable: 127.0.0.1:${HOST_PORT}"
  fi
fi

if have_cmd curl; then
  declare -a hosts=(
    "$(admin_host argocd):/"
    "$(admin_host gitea):/"
    "$(admin_host hubble):/"
    "$(admin_host headlamp):/"
    "$(admin_host signoz):/"
    "$(admin_host kyverno):/"
    "$(dex_host):/dex"
  )
  for entry in "${hosts[@]}"; do
    host="${entry%%:*}"
    path="${entry#*:}"
    url="https://${host}${port_suffix}${path}"
    code=$(curl -k -sS -o /dev/null -w "%{http_code}" --max-time 3 "${url}" 2>/dev/null || true)
    if [[ "${code}" =~ ^[23] ]]; then
      ok "HTTPS ${url} -> ${code}"
    elif [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" == "1" && "${code}" == "403" ]]; then
      ok "HTTPS ${url} -> ${code} (blocked by admin allowlist from this source)"
    else
      warn "HTTPS ${url} -> ${code:-error}"
    fi
  done
else
  warn "curl not found; skipping HTTPS checks"
fi

if [[ "${FAILURES}" -gt 0 ]]; then
  echo ""
  fail "${FAILURES} check(s) failed"
fi
