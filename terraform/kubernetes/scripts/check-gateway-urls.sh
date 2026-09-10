#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/../../.." && pwd)}"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/lib/shell-cli.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/operator-facts.sh"

FAILURES=0

fail() { echo "FAIL $*" >&2; exit 1; }
fail_soft() { echo "FAIL $*" >&2; FAILURES=$((FAILURES + 1)); }
warn() { echo "WARN $*"; }
ok() { echo "OK   $*"; }

usage() {
  cat <<'EOF' | sed "s|@SCRIPT_NAME@|${0##*/}|g"
Usage: @SCRIPT_NAME@ [--var-file PATH] [--host-port PORT] [--wait-seconds N] [--retry-interval-seconds N] [--extended]
                    [--enforce-admin-allowlist]
                    [--allowlist-allowed-origin ADDRESS] [--allowlist-denied-origin ADDRESS]

Checks the Gateway API + TLS path for public and admin gateway URLs.
Cilium is the only Gateway API implementation on kind.
Use --extended (or EXTENDED=1) for deeper pod/endpoint diagnostics.

--enforce-admin-allowlist runs a two-source matrix. It requires an origin that
must reach every admin route and a distinct origin that must receive HTTP 403;
both origins must still reach public routes. Set the two origins with the
matching flags or CHECK_GATEWAY_ALLOWLIST_* environment variables.
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
ALLOWLIST_ENFORCEMENT="${CHECK_GATEWAY_ALLOWLIST_ENFORCEMENT:-${ADMIN_ALLOWLIST_ENFORCEMENT:-0}}"
ALLOWLIST_ALLOWED_ORIGIN="${CHECK_GATEWAY_ALLOWLIST_ALLOWED_ORIGIN:-${ADMIN_ALLOWLIST_ALLOWED_ORIGIN:-}}"
ALLOWLIST_DENIED_ORIGIN="${CHECK_GATEWAY_ALLOWLIST_DENIED_ORIGIN:-${ADMIN_ALLOWLIST_DENIED_ORIGIN:-}}"
SEPARATE_ADMIN_DOMAIN=0
ADMIN_SUFFIX_IS_DISTINCT=0
ALLOWLIST_ADMIN_HOST_REGEXES=()
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
    --enforce-admin-allowlist|--allowlist-enforcement)
      ALLOWLIST_ENFORCEMENT=1
      shift
      ;;
    --allowlist-allowed-origin|--allowlist-allowed-source)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      ALLOWLIST_ALLOWED_ORIGIN="${2}"
      shift 2
      ;;
    --allowlist-denied-origin|--allowlist-denied-source)
      [[ $# -ge 2 ]] || fail "missing value for $1"
      ALLOWLIST_DENIED_ORIGIN="${2}"
      shift 2
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage "would check public and admin gateway URLs"

[[ "${WAIT_SECONDS}" =~ ^[0-9]+$ ]] || fail "--wait-seconds must be an integer >= 0"
[[ "${RETRY_INTERVAL_SECONDS}" =~ ^[0-9]+$ ]] || fail "--retry-interval-seconds must be an integer >= 0"
[[ "${ALLOWLIST_ENFORCEMENT}" == "0" || "${ALLOWLIST_ENFORCEMENT}" == "1" ]] || fail "admin allowlist enforcement must be 0 or 1"

if [[ "${#TFVARS_FILES[@]}" -gt 0 ]]; then
  for i in "${!TFVARS_FILES[@]}"; do
    if [[ -n "${TFVARS_FILES[i]}" && ! -f "${TFVARS_FILES[i]}" && -f "${STACK_DIR}/${TFVARS_FILES[i]}" ]]; then
      TFVARS_FILES[i]="${STACK_DIR}/${TFVARS_FILES[i]}"
    fi
  done
fi

operator_facts_load

PLATFORM_GATEWAY_SERVICE="cilium-gateway-platform-gateway"

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
      warn "Pod ${pod} Ready=$(reported_or_not "${ready}")"
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
  kubectl -n platform-gateway get svc ${PLATFORM_GATEWAY_SERVICE} -o wide || true
  selector=$(kubectl -n platform-gateway get svc ${PLATFORM_GATEWAY_SERVICE} -o jsonpath='{.spec.selector}' 2>/dev/null || true)
  if [[ -n "${selector}" ]]; then
    echo "Service selector: ${selector}"
  fi
  echo ""
  echo "Pods in platform-gateway:"
  kubectl -n platform-gateway get pods -o wide --show-labels || true
  echo ""
  echo "Pods labeled for gateway-name=platform-gateway (all namespaces):"
  kubectl get pods -A -l gateway.networking.k8s.io/gateway-name=platform-gateway -o wide --show-labels || true
  echo ""
  echo "EndpointSlices for ${PLATFORM_GATEWAY_SERVICE}:"
  kubectl -n platform-gateway get endpointslices -l kubernetes.io/service-name=${PLATFORM_GATEWAY_SERVICE} -o wide || true
  endpoints_detail=$(kubectl -n platform-gateway get endpointslices -l kubernetes.io/service-name=${PLATFORM_GATEWAY_SERVICE} -o jsonpath='{range .items[*].endpoints[*]}{.addresses[0]}{" ready="}{.conditions.ready}{" serving="}{.conditions.serving}{" terminating="}{.conditions.terminating}{"\n"}{end}' 2>/dev/null || true)
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
# Mirror separate_admin_domain_enabled in locals.tf: the flag means "an admin
# domain was configured", not "it differs from the public domain". Setting both
# tfvars to the same string still moves admin hosts off the .admin. infix, so
# deriving this from inequality classified every admin route as public.
if [[ -n "${PLATFORM_ADMIN_BASE_DOMAIN}" ]]; then
  SEPARATE_ADMIN_DOMAIN=1
else
  SEPARATE_ADMIN_DOMAIN=0
  PLATFORM_ADMIN_BASE_DOMAIN="${PLATFORM_BASE_DOMAIN}"
fi
# The named admin hosts follow the flag above, but the "anything under the admin
# suffix is admin" fallback cannot: when the two domains hold the same string
# that suffix also matches every public app host.
ADMIN_SUFFIX_IS_DISTINCT=0
if [[ "${PLATFORM_ADMIN_BASE_DOMAIN}" != "${PLATFORM_BASE_DOMAIN}" ]]; then
  ADMIN_SUFFIX_IS_DISTINCT=1
fi
ADMIN_ROUTE_ALLOWLIST_ENABLED=0
if [[ -n "$(tfvar_list_entries "" admin_route_allowlist_cidrs)" ]]; then
  ADMIN_ROUTE_ALLOWLIST_ENABLED=1
fi

admin_service_host() {
  local service="$1"

  if [[ "${SEPARATE_ADMIN_DOMAIN}" == "1" ]]; then
    printf '%s.%s\n' "${service}" "${PLATFORM_ADMIN_BASE_DOMAIN}"
  else
    printf '%s.admin.%s\n' "${service}" "${PLATFORM_BASE_DOMAIN}"
  fi
}

# is_cilium_admin_route_host in sync-gitea-policies.sh consults this same named
# service set before it falls back to the DNS suffixes, and honours the same
# overrides. The two have to agree: a host the renderer writes into the
# allowlist policy but this script calls public is one the enforcement matrix
# then demands the denied origin reach, turning a working restriction into a
# check failure.
ADMIN_GATEWAY_HOSTS=(
  "${ARGOCD_PUBLIC_HOST:-$(admin_service_host argocd)}"
  "${GITEA_PUBLIC_HOST:-$(admin_service_host gitea)}"
  "${GRAFANA_PUBLIC_HOST:-$(admin_service_host grafana)}"
  "${HEADLAMP_PUBLIC_HOST:-$(admin_service_host headlamp)}"
  "${HUBBLE_PUBLIC_HOST:-$(admin_service_host hubble)}"
  "${KYVERNO_PUBLIC_HOST:-$(admin_service_host kyverno)}"
  "${APIM_PUBLIC_HOST:-$(admin_service_host apim)}"
)
KEYCLOAK_GATEWAY_HOST="${KEYCLOAK_PUBLIC_HOST:-keycloak.${PLATFORM_ADMIN_BASE_DOMAIN}}"

is_admin_gateway_host() {
  local host="$1"

  # Keycloak is the public identity-provider endpoint used by SSO redirects;
  # it can share a separate admin DNS suffix without becoming an operator-only
  # route. The renderer excludes it first for the same reason.
  if [[ "${host}" == "${KEYCLOAK_GATEWAY_HOST}" ]]; then
    return 1
  fi

  if array_contains "${host}" "${ADMIN_GATEWAY_HOSTS[@]}"; then
    return 0
  fi

  if [[ "${host}" == *".admin.${PLATFORM_BASE_DOMAIN}" ]]; then
    return 0
  fi

  if [[ "${ADMIN_SUFFIX_IS_DISTINCT}" == "1" && "${host}" == *".${PLATFORM_ADMIN_BASE_DOMAIN}" ]]; then
    return 0
  fi

  return 1
}

# shellcheck disable=SC2016 # '$' is intentionally a regex anchor, not shell syntax.
gateway_host_regex() {
  # This must match the parsed value of the YAML emitted by
  # sync-gitea-policies.sh: the YAML double quotes turn the renderer's two
  # backslashes into one regex escape in the live object.
  printf '%s' "$1" | sed 's/[.[\\*^$()+?{|]/\\&/g'
}

gateway_route_kind() {
  if is_admin_gateway_host "$1"; then
    printf 'admin\n'
  else
    printf 'public\n'
  fi
}

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

reported_or_not() {
  local value="$1"
  if [[ -n "${value}" ]]; then
    printf '%s' "${value}"
  else
    printf 'not reported'
  fi
}

probe_https_url() {
  local host="$1"
  local url="$2"
  local route_kind="${3:-public}"
  local source_origin="${4:-}"
  local tmp_err curl_rc code err
  local -a curl_args=()

  PROBE_OK=0
  PROBE_CODE="000"
  PROBE_DETAIL=""

  if devcontainer_enabled; then
    curl_args=(--connect-to "${host}:${HOST_PORT}:${DEVCONTAINER_HOST_ALIAS}:${HOST_PORT}")
  else
    curl_args=(--resolve "${host}:${HOST_PORT}:127.0.0.1")
  fi
  if [[ -n "${source_origin}" ]]; then
    # Bind the real client socket. Do not use X-Forwarded-For here: Cilium's
    # policy decision must observe the source address that actually reaches
    # the listener.
    curl_args+=(--interface "${source_origin}")
  fi

  if [[ "${url}" == https://llm.*"/v1/chat/completions" ]]; then
    local models_url model_json model_name
    models_url="${url%/chat/completions}/models"
    model_json="$(curl -k -sS --max-time 5 "${curl_args[@]}" "${models_url}" 2>/dev/null || true)"
    model_name="$(printf '%s\n' "${model_json}" | sed -nE 's/.*"id"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' | head -n 1)"
    if [[ -z "${model_name}" ]]; then
      if printf '%s\n' "${model_json}" | grep -Fq "upstream call failed"; then
        PROBE_OK=1
        PROBE_CODE="503"
        PROBE_DETAIL="503 (agentgateway reached; OpenAI-compatible backend unavailable)"
        return 0
      fi
      PROBE_CODE="000"
      PROBE_DETAIL="000 (could not discover OpenAI-compatible model from ${models_url})"
      return 0
    fi
    curl_args+=(
      -X POST
      -H "Content-Type: application/json"
      --data "{\"model\":\"${model_name}\",\"messages\":[{\"role\":\"user\",\"content\":\"health\"}],\"max_tokens\":1}"
    )
  fi

  tmp_err="$(mktemp)"
  set +e
  code="$(curl -k -sS -o /dev/null -w "%{http_code}" --max-time 5 "${curl_args[@]}" "${url}" 2>"${tmp_err}")"
  curl_rc=$?
  set -e
  err="$(tr '\n' ' ' <"${tmp_err}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  rm -f "${tmp_err}"
  PROBE_CODE="${code:-000}"

  if [[ "${code}" =~ ^[23] ]]; then
    PROBE_OK=1
    PROBE_DETAIL="${code}"
    return 0
  fi

  # These are explicit application-level auth expectations, not allowlist
  # evidence. Keep them ahead of the admin-route branch so a machine endpoint
  # returning 403 is not mislabeled as a source-IP denial.
  if [[ "${url}" == https://mcp.*"/mcp" && ( "${code}" == "401" || "${code}" == "403" ) ]]; then
    PROBE_OK=1
    PROBE_DETAIL="${code} (MCP machine path requires bearer token)"
    return 0
  fi

  if [[ "${url}" == https://llm.*"/v1/chat/completions" && ( "${code}" == "401" || "${code}" == "403" || "${code}" == "429" ) ]]; then
    PROBE_OK=1
    PROBE_DETAIL="${code} (agentgateway reached OpenAI-compatible backend)"
    return 0
  fi

  if [[ "${url}" == https://llm.*"/v1/chat/completions" && "${code}" == "507" ]]; then
    PROBE_OK=1
    PROBE_DETAIL="${code} (agentgateway reached OpenAI-compatible backend; model unavailable or capacity-limited)"
    return 0
  fi

  if [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" == "1" && "${route_kind}" == "admin" && "${code}" == "403" ]]; then
    PROBE_OK=1
    PROBE_DETAIL="${code} (admin route blocked by configured allowlist from this source)"
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

  local entry host path url route_kind rest
  for entry in "${ROUTE_ENTRIES[@]}"; do
    host="${entry%%|*}"
    rest="${entry#*|}"
    path="${rest%%|*}"
    route_kind="${rest#*|}"
    [[ "${route_kind}" != "${rest}" ]] || route_kind="public"
    if [[ "${host}" == llm.* && "${path}" == "/v1" ]]; then
      path="/v1/chat/completions"
    fi
    url="https://${host}${port_suffix}${path}"

    probe_https_url "${host}" "${url}" "${route_kind}"
    if [[ "${PROBE_OK}" == "1" ]]; then
      HTTPS_RESULTS+=("OK|${url}|${PROBE_DETAIL}")
    else
      HTTPS_RESULTS+=("FAIL|${url}|${PROBE_DETAIL}")
      HTTPS_FAILURE_COUNT=$((HTTPS_FAILURE_COUNT + 1))
    fi
  done
}

check_allowlist_route_coverage() {
  [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" == "1" ]] || return 0

  if [[ "${#ALLOWLIST_ADMIN_HOST_REGEXES[@]}" -eq 0 ]]; then
    # The policy shape check below reports the missing rule. Keep this helper
    # quiet as well so one absent policy does not produce one failure per route.
    return 0
  fi

  local entry host rest route_kind expected
  local -a missing_hosts=()
  for entry in "${ROUTE_ENTRIES[@]}"; do
    host="${entry%%|*}"
    rest="${entry#*|}"
    route_kind="${rest#*|}"
    [[ "${route_kind}" != "${rest}" ]] || route_kind="public"
    [[ "${route_kind}" == "admin" ]] || continue

    expected="^$(gateway_host_regex "${host}")$"
    if ! array_contains "${expected}" "${ALLOWLIST_ADMIN_HOST_REGEXES[@]}"; then
      missing_hosts+=("${host}")
    fi
  done

  if [[ "${#missing_hosts[@]}" -eq 0 ]]; then
    ok "Cilium admin allowlist covers every discovered admin hostname"
  else
    fail_soft "Cilium admin allowlist is missing HTTP host rule(s) for: ${missing_hosts[*]}"
  fi
}

probe_tls_certificate() {
  local host="$1"
  local tmp_err cert_pem check_output check_rc err connect_host sans san suffix prefix

  TLS_CERT_OK=0
  TLS_CERT_DETAIL=""

  connect_host="$(probe_host_for_local_https)"
  tmp_err="$(mktemp)"

  set +e
  # No rc capture here: the pipeline's status is openssl x509's, and an empty
  # cert_pem is the condition actually tested below. The variable was assigned
  # and never read (SC2034), which shellcheck flags but `make lint` never sees --
  # lint-shell audits conventions, not correctness.
  cert_pem="$(openssl s_client -connect "${connect_host}:${HOST_PORT}" -servername "${host}" </dev/null 2>"${tmp_err}" | openssl x509 2>>"${tmp_err}")"
  set -e

  if [[ -z "${cert_pem}" ]]; then
    err="$(tr '\n' ' ' <"${tmp_err}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
    rm -f "${tmp_err}"
    TLS_CERT_DETAIL="certificate read failed${err:+: ${err}}"
    return 0
  fi

  if openssl x509 -help 2>&1 | grep -q -- "-checkhost"; then
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
    return 0
  fi

  sans="$(
    printf '%s\n' "${cert_pem}" \
      | openssl x509 -noout -text 2>>"${tmp_err}" \
      | awk '
          /Subject Alternative Name/ { getline; gsub(/,/, "\n"); print }
        ' \
      | sed -n 's/.*DNS:\([^[:space:]]*\).*/\1/p'
  )"
  err="$(tr '\n' ' ' <"${tmp_err}" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"
  rm -f "${tmp_err}"

  while IFS= read -r san; do
    [[ -n "${san}" ]] || continue
    if [[ "${san}" == "${host}" ]]; then
      TLS_CERT_OK=1
      TLS_CERT_DETAIL="hostname ${host} matches certificate SAN ${san}"
      return 0
    fi
    if [[ "${san}" == \*.* ]]; then
      suffix="${san#\*}"
      if [[ "${host}" == *"${suffix}" ]]; then
        prefix="${host%"${suffix}"}"
        if [[ -n "${prefix}" && "${prefix}" != *.* ]]; then
          TLS_CERT_OK=1
          TLS_CERT_DETAIL="hostname ${host} matches certificate SAN ${san}"
          return 0
        fi
      fi
    fi
  done <<< "${sans}"

  TLS_CERT_DETAIL="hostname mismatch${err:+ (${err})}"
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
    if array_contains "${host}" ${seen_hosts[@]+"${seen_hosts[@]}"}; then
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
# Cilium has no gateway deployment: Envoy runs inside the cilium-agent
# DaemonSet, so the GatewayClass is the thing that says the controller is live.
echo "Gateway controller (cilium):"
gwc_accepted=$(kubectl get gatewayclass cilium -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
if [[ "${gwc_accepted}" == "True" ]]; then
  ok "cilium GatewayClass Accepted=True"
else
  fail_soft "cilium GatewayClass Accepted=$(reported_or_not "${gwc_accepted}")"
fi

if [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" == "1" ]]; then
  # The policy attaches to Cilium's reserved:ingress endpoint, where the
  # original client CIDR still exists. Backends only see reserved:ingress, so
  # checking a backend policy here would prove nothing about the allowlist.
  allowlist_selector=$(kubectl get ccnp cilium-gateway-admin-allowlist -o jsonpath='{.spec.endpointSelector.matchExpressions[?(@.key=="reserved:ingress")].operator}' 2>/dev/null || true)
  if [[ "${allowlist_selector}" == "Exists" ]]; then
    ok "Cilium admin allowlist selects reserved:ingress"
  else
    fail_soft "Cilium admin allowlist policy is missing or does not select reserved:ingress"
  fi

  allowlist_cidrs=$(kubectl get ccnp cilium-gateway-admin-allowlist -o jsonpath='{.spec.ingress[0].fromCIDRSet[*].cidr}' 2>/dev/null || true)
  missing_cidrs=()
  while IFS= read -r configured_cidr; do
    [[ -z "${configured_cidr}" ]] && continue
    if [[ " ${allowlist_cidrs} " != *" ${configured_cidr} "* ]]; then
      missing_cidrs+=("${configured_cidr}")
    fi
  done < <(tfvar_list_entries "" admin_route_allowlist_cidrs)
  if [[ "${#missing_cidrs[@]}" -eq 0 ]]; then
    ok "Cilium admin allowlist contains every configured CIDR"
  else
    fail_soft "Cilium admin allowlist is missing configured CIDR(s): ${missing_cidrs[*]}"
  fi

  allowlist_host_regexes="$(kubectl get ccnp cilium-gateway-admin-allowlist -o jsonpath='{.spec.ingress[0].toPorts[0].rules.http[*].host}' 2>/dev/null || true)"
  ALLOWLIST_ADMIN_HOST_REGEXES=()
  while IFS= read -r host_regex; do
    [[ -n "${host_regex}" ]] || continue
    ALLOWLIST_ADMIN_HOST_REGEXES+=("${host_regex}")
  done < <(printf '%s\n' "${allowlist_host_regexes}" | tr ' ' '\n')
  if [[ "${#ALLOWLIST_ADMIN_HOST_REGEXES[@]}" -gt 0 ]]; then
    ok "Cilium admin allowlist contains ${#ALLOWLIST_ADMIN_HOST_REGEXES[@]} HTTP host rule(s)"
  else
    fail_soft "Cilium admin allowlist has no HTTP host rules"
  fi
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
    fail_soft "Gateway Programmed=$(reported_or_not "${programmed}")"
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
echo "Gateway Service (${PLATFORM_GATEWAY_SERVICE}):"
if kubectl -n platform-gateway get svc ${PLATFORM_GATEWAY_SERVICE} >/dev/null 2>&1; then
  node_port=$(kubectl -n platform-gateway get svc ${PLATFORM_GATEWAY_SERVICE} -o jsonpath='{.spec.ports[?(@.port==443)].nodePort}' 2>/dev/null || true)
  if [[ -n "${node_port}" ]]; then
    ok "NodePort: ${node_port}"
  else
    fail_soft "NodePort not found on service ${PLATFORM_GATEWAY_SERVICE}"
  fi
  # Cilium's gateway Service has no selector and no Endpoints object at all --
  # the listener is Envoy inside cilium-agent, not a pod. It publishes a
  # sentinel EndpointSlice (192.192.192.192:9999) purely so the Service looks
  # backed, so counting pod endpoints here would always fail. The Programmed
  # condition checked above is the real readiness signal in this mode.
  slice_count=$(kubectl -n platform-gateway get endpointslices -l "kubernetes.io/service-name=${PLATFORM_GATEWAY_SERVICE}" -o name 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${slice_count:-0}" -gt 0 ]]; then
    ok "Cilium gateway Service present (host-network Envoy; no pod endpoints by design)"
  else
    fail_soft "No EndpointSlice for service ${PLATFORM_GATEWAY_SERVICE}"
    if [[ "${EXTENDED}" -eq 1 ]]; then
      print_debug_context
    fi
  fi
else
  fail_soft "Service ${PLATFORM_GATEWAY_SERVICE} missing in namespace platform-gateway"
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
    fail_soft "Certificate Ready=$(reported_or_not "${cert_ready}")"
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
        fail_soft "HTTPRoute ${route} Accepted=$(reported_or_not "${accepted}") (${hostnames})"
      fi
      if [[ -n "${resolved}" && "${resolved}" != "True" ]]; then
        warn "HTTPRoute ${route} ResolvedRefs=${resolved}"
      fi

      hostnames_lines="$(printf '%s\n' "${hostnames}" | tr ' ' '\n' | awk 'NF > 0')"
      while IFS= read -r hostname; do
        [[ -n "${hostname}" ]] || continue
        route_entry="${hostname}|${route_path}|$(gateway_route_kind "${hostname}")"
        if [[ "${#ROUTE_ENTRIES[@]}" -eq 0 ]] || ! array_contains "${route_entry}" "${ROUTE_ENTRIES[@]}"; then
          ROUTE_ENTRIES+=("${route_entry}")
        fi
      done <<<"${hostnames_lines}"
    done <<<"${routes}"
  fi
else
  fail_soft "Namespace gateway-routes missing or no HTTPRoute support"
fi

check_allowlist_route_coverage

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

probe_allowlist_origin() {
  local source_origin="$1"
  local expected_admin_result="$2"
  local label="$3"
  local entry host rest path route_kind url

  for entry in "${ROUTE_ENTRIES[@]}"; do
    host="${entry%%|*}"
    rest="${entry#*|}"
    path="${rest%%|*}"
    route_kind="${rest#*|}"
    [[ "${route_kind}" != "${rest}" ]] || route_kind="public"
    if [[ "${host}" == llm.* && "${path}" == "/v1" ]]; then
      path="/v1/chat/completions"
    fi
    url="https://${host}${port_suffix}${path}"

    probe_https_url "${host}" "${url}" "${route_kind}" "${source_origin}"
    if [[ "${route_kind}" == "admin" ]]; then
      if [[ "${expected_admin_result}" == "allowed" && "${PROBE_CODE}" =~ ^[23] ]]; then
        ok "Admin allowlist ${label} origin ${source_origin}: admin ${url} -> ${PROBE_DETAIL}"
      elif [[ "${expected_admin_result}" == "denied" && "${PROBE_CODE}" == "403" ]]; then
        ok "Admin allowlist ${label} origin ${source_origin}: admin ${url} -> ${PROBE_DETAIL}"
      else
        fail_soft "Admin allowlist ${label} origin ${source_origin}: admin ${url} -> ${PROBE_DETAIL:-${PROBE_CODE}}"
      fi
    elif [[ "${PROBE_OK}" == "1" ]]; then
      ok "Admin allowlist ${label} origin ${source_origin}: public ${url} -> ${PROBE_DETAIL}"
    else
      fail_soft "Admin allowlist ${label} origin ${source_origin}: public ${url} -> ${PROBE_DETAIL:-${PROBE_CODE}}"
    fi
  done
}

check_admin_allowlist_enforcement() {
  if [[ "${ALLOWLIST_ENFORCEMENT}" != "1" ]]; then
    if [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" == "1" ]]; then
      warn "Admin allowlist enforcement: NOT VERIFIED (rerun with --enforce-admin-allowlist and two distinct origin addresses)"
    fi
    return 0
  fi

  if [[ "${ADMIN_ROUTE_ALLOWLIST_ENABLED}" != "1" ]]; then
    fail_soft "Admin allowlist enforcement NOT VERIFIED: admin_route_allowlist_cidrs is empty"
    return 0
  fi
  if [[ -z "${ALLOWLIST_ALLOWED_ORIGIN}" || -z "${ALLOWLIST_DENIED_ORIGIN}" ]]; then
    fail_soft "Admin allowlist enforcement NOT VERIFIED: both allowed and denied origin addresses are required"
    return 0
  fi
  if [[ "${ALLOWLIST_ALLOWED_ORIGIN}" == "${ALLOWLIST_DENIED_ORIGIN}" ]]; then
    fail_soft "Admin allowlist enforcement NOT VERIFIED: allowed and denied origins must be distinct"
    return 0
  fi
  if [[ "${#ROUTE_ENTRIES[@]}" -eq 0 ]]; then
    fail_soft "Admin allowlist enforcement NOT VERIFIED: no discovered routes are available"
    return 0
  fi

  echo ""
  echo "Admin allowlist enforcement matrix (real source sockets):"
  probe_allowlist_origin "${ALLOWLIST_ALLOWED_ORIGIN}" allowed allowed
  probe_allowlist_origin "${ALLOWLIST_DENIED_ORIGIN}" denied denied
}

check_admin_allowlist_enforcement

echo ""
# The NGINX path pinned TLS versions and ciphersuites declaratively, through
# nginx.org/ssl-protocols and a SnippetsPolicy ssl_conf_command. Cilium's Gateway
# API has no equivalent knob -- CiliumGatewayClassConfig exposes only
# serverHeaderTransformation, httpOptions, service and telemetry -- so the
# posture comes from Envoy's defaults instead of from configuration.
#
# Measured, those defaults match what the NGINX config asked for. But a default
# is not an enforcement: a Cilium or Envoy bump could move it with nothing to
# notice. So assert the outcome rather than the setting.
probe_tls_posture() {
  local connect_host probe_sni proto cipher
  local -a weak_ciphers=(RC4-SHA DES-CBC3-SHA AES128-SHA NULL-SHA)

  command -v openssl >/dev/null 2>&1 || { warn "openssl not found; skipping TLS posture checks"; return 0; }
  [[ "${#ROUTE_ENTRIES[@]}" -gt 0 ]] || return 0

  connect_host="$(probe_host_for_local_https)"
  probe_sni="${ROUTE_ENTRIES[0]%%|*}"

  # Establish that the endpoint reports a negotiated protocol at all before
  # asserting anything about it. Without this the whole battery fails whenever
  # openssl cannot speak to the listener -- and each probe would report its own
  # failure, turning one unreachable endpoint into eleven. A genuinely broken
  # TLS listener is already caught by the HTTPS route and certificate checks
  # above, so skipping here loses no coverage.
  if ! echo | openssl s_client -connect "${connect_host}:${HOST_PORT}" -servername "${probe_sni}" 2>/dev/null \
    | grep -qE "^ *Protocol *: *TLSv"; then
    warn "TLS posture: no negotiated protocol reported by ${connect_host}:${HOST_PORT}; skipping posture checks"
    return 0
  fi

  # Deprecated versions must be refused.
  for proto in tls1 tls1_1; do
    if echo | openssl s_client -connect "${connect_host}:${HOST_PORT}" -servername "${probe_sni}" "-${proto}" 2>/dev/null \
      | grep -qE "^ *Protocol *: *TLSv1(\.1)?$"; then
      fail_soft "TLS posture: ${proto} is accepted and must not be"
    else
      ok "TLS posture: ${proto} refused"
    fi
  done

  # Both modern versions must be available.
  for proto in tls1_2 tls1_3; do
    if echo | openssl s_client -connect "${connect_host}:${HOST_PORT}" -servername "${probe_sni}" "-${proto}" 2>/dev/null \
      | grep -qE "^ *Protocol *: *TLSv1\.[23]$"; then
      ok "TLS posture: ${proto} available"
    else
      fail_soft "TLS posture: ${proto} is not available"
    fi
  done

  # The three TLS 1.3 suites the gateway must keep offering. The retired NGF
  # SnippetsPolicy pinned exactly these via ssl_conf_command Ciphersuites; the
  # list is now the assertion rather than a copy of live configuration.
  for cipher in TLS_AES_128_GCM_SHA256 TLS_AES_256_GCM_SHA384 TLS_CHACHA20_POLY1305_SHA256; do
    if echo | openssl s_client -connect "${connect_host}:${HOST_PORT}" -servername "${probe_sni}" -tls1_3 -ciphersuites "${cipher}" 2>/dev/null \
      | grep -qE "^ *Protocol *: *TLSv1\.3$"; then
      ok "TLS posture: ${cipher} available"
    else
      fail_soft "TLS posture: ${cipher} is not available"
    fi
  done

  for cipher in "${weak_ciphers[@]}"; do
    if echo | openssl s_client -connect "${connect_host}:${HOST_PORT}" -servername "${probe_sni}" -tls1_2 -cipher "${cipher}" 2>&1 \
      | grep -qE "^ *Cipher *: *${cipher}$"; then
      fail_soft "TLS posture: weak cipher ${cipher} is accepted"
    else
      ok "TLS posture: weak cipher ${cipher} refused"
    fi
  done
}

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

echo ""
echo "TLS posture (host port ${HOST_PORT}):"
probe_tls_posture

if [[ "${FAILURES}" -gt 0 ]]; then
  echo ""
  fail "${FAILURES} check(s) failed"
fi
