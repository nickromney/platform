#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-gateway-urls.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"

  cat >"${TEST_BIN}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "get" && "${2:-}" == "clusters" ]]; then
  printf 'kind-local\n'
  exit 0
fi
exit 99
EOF
  chmod +x "${TEST_BIN}/kind"

  cat >"${TEST_BIN}/nc" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${PLATFORM_DEVCONTAINER:-0}" == "1" ]]; then
  if [[ "${*}" != *"host.docker.internal"* ]]; then
    echo "expected devcontainer nc probe to use host.docker.internal" >&2
    exit 98
  fi
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/nc"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${PLATFORM_DEVCONTAINER:-0}" == "1" ]]; then
  if [[ "${*}" != *"--connect-to"* || "${*}" != *"host.docker.internal"* ]]; then
    echo "expected devcontainer curl probe to use host.docker.internal" >&2
    exit 98
  fi
fi

url=""
interface_origin=""
while [[ $# -gt 0 ]]; do
  case "${1}" in
    --interface)
      interface_origin="${2:-}"
      shift 2
      continue
      ;;
    https://*)
      url="${1}"
      ;;
  esac
  shift
done

if [[ -n "${interface_origin}" ]]; then
  case "${interface_origin}:${url}" in
    127.0.0.2:https://headlamp.admin.127.0.0.1.sslip.io/)
      printf '302'
      exit 0
      ;;
    127.0.0.3:https://headlamp.admin.127.0.0.1.sslip.io/)
      printf '403'
      exit 0
      ;;
    127.0.0.[23]:https://subnetcalc.uat.127.0.0.1.sslip.io/)
      printf '200'
      exit 0
      ;;
    127.0.0.[23]:https://keycloak.127.0.0.1.sslip.io/)
      printf '200'
      exit 0
      ;;
  esac
fi

case "${MOCK_GATEWAY_FAILURE:-0}:${url}" in
  0:https://llm.127.0.0.1.sslip.io/v1/models)
    if [[ "${MOCK_LLM_BACKEND_CAPACITY_LIMITED:-0}" == "1" ]]; then
      printf '{"object":"list","data":[{"id":"big-local-model"}]}'
      exit 0
    fi
    if [[ "${MOCK_LLM_BACKEND_UNAVAILABLE:-0}" == "1" ]]; then
      printf 'upstream call failed: Connect: Connection refused (os error 111)'
      exit 0
    fi
    echo "unexpected llm model discovery without MOCK_LLM_BACKEND_UNAVAILABLE=1" >&2
    exit 99
    ;;
  0:https://llm.127.0.0.1.sslip.io/v1/chat/completions)
    if [[ "${MOCK_LLM_BACKEND_CAPACITY_LIMITED:-0}" == "1" ]]; then
      printf '507'
      exit 0
    fi
    echo "unexpected llm chat completion without MOCK_LLM_BACKEND_CAPACITY_LIMITED=1" >&2
    exit 99
    ;;
  0:https://headlamp.admin.127.0.0.1.sslip.io/)
    if [[ "${MOCK_ADMIN_FORBIDDEN:-0}" == "1" ]]; then
      printf '403'
      exit 0
    fi
    printf '302'
    exit 0
    ;;
  0:https://subnetcalc.uat.127.0.0.1.sslip.io/)
    if [[ "${MOCK_PUBLIC_FORBIDDEN:-0}" == "1" ]]; then
      printf '403'
      exit 0
    fi
    printf '200'
    exit 0
    ;;
  0:https://keycloak.127.0.0.1.sslip.io/)
    printf '200'
    exit 0
    ;;
  1:https://headlamp.admin.127.0.0.1.sslip.io/)
    printf '000'
    echo "tls reset" >&2
    exit 35
    ;;
  1:https://subnetcalc.uat.127.0.0.1.sslip.io/)
    printf '200'
    exit 0
    ;;
  1:https://keycloak.127.0.0.1.sslip.io/)
    printf '200'
    exit 0
    ;;
  *)
    echo "unexpected url ${url}" >&2
    exit 99
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/curl"

  cat >"${TEST_BIN}/openssl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  s_client)
    printf '%s\n' '-----BEGIN CERTIFICATE-----' 'stub' '-----END CERTIFICATE-----'
    exit 0
    ;;
  x509)
    if [[ "${*}" == *"-help"* ]]; then
      printf '%s\n' 'Usage: x509 -checkhost host'
      exit 0
    fi
    if [[ "${*}" == *"-checkhost"* ]]; then
      printf '%s\n' 'Hostname matches certificate'
      exit 0
    fi
    cat >/dev/null
    printf '%s\n' '-----BEGIN CERTIFICATE-----' 'stub' '-----END CERTIFICATE-----'
    exit 0
    ;;
esac
echo "unexpected openssl invocation: $*" >&2
exit 99
EOF
  chmod +x "${TEST_BIN}/openssl"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"

if [[ "${args}" == "get nodes" ]]; then
  printf 'kind-local-control-plane Ready\n'
  exit 0
fi

if [[ "${args}" == *"get gatewayclass cilium -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="Accepted"'; then
  printf 'True'
  exit 0
fi

if [[ "${args}" == *"get ccnp cilium-gateway-admin-allowlist -o jsonpath="* ]]; then
  if printf '%s' "${args}" | grep -Fq 'reserved:ingress'; then
    printf 'Exists'
    exit 0
  fi
  if printf '%s' "${args}" | grep -Fq 'fromCIDRSet[*].cidr'; then
    printf '10.0.0.0/8'
    exit 0
  fi
  if printf '%s' "${args}" | grep -Fq 'rules.http[*].host'; then
    printf '^headlamp\.admin\.127\.0\.0\.1\.sslip\.io$'
    exit 0
  fi
fi

if [[ "${args}" == "-n platform-gateway get gateway platform-gateway" ]]; then
  exit 0
fi
if [[ "${args}" == *"-n platform-gateway get gateway platform-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="Programmed"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n platform-gateway get gateway platform-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="Accepted"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n platform-gateway get gateway platform-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.status.addresses'; then
  printf '10.96.178.212 '
  exit 0
fi

if [[ "${args}" == "-n platform-gateway get svc cilium-gateway-platform-gateway" ]]; then
  exit 0
fi
if [[ "${args}" == *"-n platform-gateway get svc cilium-gateway-platform-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.nodePort'; then
  printf '30070'
  exit 0
fi
if [[ "${args}" == *"get endpointslices -l kubernetes.io/service-name=cilium-gateway-platform-gateway"* ]]; then
  printf 'endpointslice.discovery.k8s.io/cilium-gateway-platform-gateway-abcde\n'
  exit 0
fi

if [[ "${args}" == "-n platform-gateway get endpoints platform-gateway-nginx" ]]; then
  exit 0
fi
if [[ "${args}" == *"-n platform-gateway get endpoints platform-gateway-nginx -o jsonpath="* ]]; then
  printf '10.244.1.124 '
  exit 0
fi

if [[ "${args}" == "-n platform-gateway get certificate platform-gateway-tls" ]]; then
  exit 0
fi
if [[ "${args}" == *"-n platform-gateway get certificate platform-gateway-tls -o jsonpath="* ]]; then
  printf 'True'
  exit 0
fi

if [[ "${args}" == "-n platform-gateway get secret platform-gateway-tls" ]]; then
  exit 0
fi

if [[ "${args}" == "-n gateway-routes get httproute" ]]; then
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.items[*]'; then
  if [[ "${MOCK_NO_ROUTES:-0}" == "1" ]]; then
    exit 0
  fi
  if [[ "${MOCK_LLM_BACKEND_UNAVAILABLE:-0}" == "1" || "${MOCK_LLM_BACKEND_CAPACITY_LIMITED:-0}" == "1" ]]; then
    printf 'headlamp\nsubnetcalc-uat\nkeycloak\nagentgateway-ai-gateway\n'
    exit 0
  fi
  printf 'headlamp\nsubnetcalc-uat\nkeycloak\n'
  exit 0
fi

if [[ "${args}" == *"-n gateway-routes get httproute headlamp -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.spec.hostnames[*]'; then
  printf 'headlamp.admin.127.0.0.1.sslip.io'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute headlamp -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="Accepted"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute headlamp -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="ResolvedRefs"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute headlamp -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.path.value'; then
  printf '/\n'
  exit 0
fi

if [[ "${args}" == *"-n gateway-routes get httproute subnetcalc-uat -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.spec.hostnames[*]'; then
  printf 'subnetcalc.uat.127.0.0.1.sslip.io'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute subnetcalc-uat -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="Accepted"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute subnetcalc-uat -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="ResolvedRefs"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute subnetcalc-uat -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.path.value'; then
  printf '/\n'
  exit 0
fi

if [[ "${args}" == *"-n gateway-routes get httproute keycloak -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.spec.hostnames[*]'; then
  printf 'keycloak.127.0.0.1.sslip.io'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute keycloak -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="Accepted"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute keycloak -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="ResolvedRefs"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute keycloak -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.path.value'; then
  printf '/\n'
  exit 0
fi

if [[ "${args}" == *"-n gateway-routes get httproute agentgateway-ai-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.spec.hostnames[*]'; then
  printf 'llm.127.0.0.1.sslip.io'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute agentgateway-ai-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="Accepted"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute agentgateway-ai-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="ResolvedRefs"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute agentgateway-ai-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.path.value'; then
  printf '/v1\n'
  exit 0
fi

echo "unexpected kubectl invocation: $*" >&2
exit 99
EOF
  chmod +x "${TEST_BIN}/kubectl"
}

@test "check-gateway-urls probes discovered routes and skips absent apps" {
  run "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"HTTPS https://headlamp.admin.127.0.0.1.sslip.io/ -> 302"* ]]
  [[ "${output}" == *"HTTPS https://subnetcalc.uat.127.0.0.1.sslip.io/ -> 200"* ]]
  [[ "${output}" == *"HTTPS https://keycloak.127.0.0.1.sslip.io/ -> 200"* ]]
}

@test "check-gateway-urls fails when a discovered route stays down" {
  run env MOCK_GATEWAY_FAILURE=1 "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"HTTPS https://headlamp.admin.127.0.0.1.sslip.io/ -> 000"* ]]
  [[ "${output}" == *"curl exit 35"* ]]
}

@test "check-gateway-urls uses host.docker.internal inside the devcontainer" {
  run env PLATFORM_DEVCONTAINER=1 "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Host port open: host.docker.internal:443"* ]]
}

@test "check-gateway-urls handles empty discovered route lists without bash nounset crashes" {
  run env MOCK_NO_ROUTES=1 /bin/bash "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"No gateway route hostnames available to probe"* ]]
  [[ "${output}" != *"unbound variable"* ]]
}

@test "check-gateway-urls accepts agentgateway route when optional local LLM backend is absent" {
  run env MOCK_LLM_BACKEND_UNAVAILABLE=1 "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"HTTPS https://llm.127.0.0.1.sslip.io/v1/chat/completions -> 503 (agentgateway reached; OpenAI-compatible backend unavailable)"* ]]
}

@test "check-gateway-urls accepts agentgateway route when local LLM model is capacity limited" {
  run env MOCK_LLM_BACKEND_CAPACITY_LIMITED=1 "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"HTTPS https://llm.127.0.0.1.sslip.io/v1/chat/completions -> 507 (agentgateway reached OpenAI-compatible backend; model unavailable or capacity-limited)"* ]]
}

@test "check-gateway-urls does not treat a public 403 as admin allowlist evidence" {
  facts_file="${BATS_TEST_TMPDIR}/allowlist-facts.json"
  printf '%s\n' '{"platform_base_domain":"127.0.0.1.sslip.io","platform_admin_base_domain":"127.0.0.1.sslip.io","admin_route_allowlist_cidrs":["10.0.0.0/8"]}' >"${facts_file}"

  run env OPERATOR_FACTS_FILE="${facts_file}" MOCK_PUBLIC_FORBIDDEN=1 "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"HTTPS https://subnetcalc.uat.127.0.0.1.sslip.io/ -> 403"* ]]
  [[ "${output}" != *"subnetcalc.uat.127.0.0.1.sslip.io/ -> 403 (admin route blocked"* ]]
}

@test "check-gateway-urls accepts an admin 403 only for an allowlisted admin route" {
  facts_file="${BATS_TEST_TMPDIR}/allowlist-facts.json"
  printf '%s\n' '{"platform_base_domain":"127.0.0.1.sslip.io","platform_admin_base_domain":"127.0.0.1.sslip.io","admin_route_allowlist_cidrs":["10.0.0.0/8"]}' >"${facts_file}"

  run env OPERATOR_FACTS_FILE="${facts_file}" MOCK_ADMIN_FORBIDDEN=1 "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"HTTPS https://headlamp.admin.127.0.0.1.sslip.io/ -> 403 (admin route blocked by configured allowlist from this source)"* ]]
}

@test "check-gateway-urls reports an unconfigured allowlist enforcement matrix as not verified" {
  facts_file="${BATS_TEST_TMPDIR}/allowlist-facts.json"
  printf '%s\n' '{"platform_base_domain":"127.0.0.1.sslip.io","platform_admin_base_domain":"127.0.0.1.sslip.io","admin_route_allowlist_cidrs":["10.0.0.0/8"]}' >"${facts_file}"

  run env OPERATOR_FACTS_FILE="${facts_file}" "${SCRIPT}" --execute --wait-seconds 0 --enforce-admin-allowlist

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Admin allowlist enforcement NOT VERIFIED: both allowed and denied origin addresses are required"* ]]
}

@test "check-gateway-urls verifies admin allowlist behavior with distinct source sockets" {
  facts_file="${BATS_TEST_TMPDIR}/allowlist-facts.json"
  printf '%s\n' '{"platform_base_domain":"127.0.0.1.sslip.io","platform_admin_base_domain":"127.0.0.1.sslip.io","admin_route_allowlist_cidrs":["10.0.0.0/8"]}' >"${facts_file}"

  run env OPERATOR_FACTS_FILE="${facts_file}" "${SCRIPT}" --execute --wait-seconds 0 \
    --enforce-admin-allowlist \
    --allowlist-allowed-origin 127.0.0.2 \
    --allowlist-denied-origin 127.0.0.3

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Admin allowlist allowed origin 127.0.0.2: admin https://headlamp.admin.127.0.0.1.sslip.io/ -> 302"* ]]
  [[ "${output}" == *"Admin allowlist denied origin 127.0.0.3: admin https://headlamp.admin.127.0.0.1.sslip.io/ -> 403"* ]]
  [[ "${output}" == *"Admin allowlist denied origin 127.0.0.3: public https://subnetcalc.uat.127.0.0.1.sslip.io/ -> 200"* ]]
}
