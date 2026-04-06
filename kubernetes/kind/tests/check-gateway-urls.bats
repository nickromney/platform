#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
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
exit 0
EOF
  chmod +x "${TEST_BIN}/nc"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
url="${*: -1}"
case "${MOCK_GATEWAY_FAILURE:-0}:${url}" in
  0:https://headlamp.admin.127.0.0.1.sslip.io/)
    printf '302'
    exit 0
    ;;
  0:https://subnetcalc.uat.127.0.0.1.sslip.io/)
    printf '200'
    exit 0
    ;;
  0:https://dex.127.0.0.1.sslip.io/dex/)
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
  1:https://dex.127.0.0.1.sslip.io/dex/)
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

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"

if [[ "${args}" == "get nodes" ]]; then
  printf 'kind-local-control-plane Ready\n'
  exit 0
fi

if [[ "${args}" == "-n nginx-gateway get deploy nginx-gateway" ]]; then
  exit 0
fi
if [[ "${args}" == *"-n nginx-gateway get deploy nginx-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.spec.replicas'; then
  printf '1'
  exit 0
fi
if [[ "${args}" == *"-n nginx-gateway get deploy nginx-gateway -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.status.readyReplicas'; then
  printf '1'
  exit 0
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

if [[ "${args}" == "-n platform-gateway get svc platform-gateway-nginx" ]]; then
  exit 0
fi
if [[ "${args}" == *"-n platform-gateway get svc platform-gateway-nginx -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.nodePort'; then
  printf '30070'
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
  printf 'headlamp\nsubnetcalc-uat\ndex\n'
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

if [[ "${args}" == *"-n gateway-routes get httproute dex -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.spec.hostnames[*]'; then
  printf 'dex.127.0.0.1.sslip.io'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute dex -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="Accepted"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute dex -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq 'type=="ResolvedRefs"'; then
  printf 'True'
  exit 0
fi
if [[ "${args}" == *"-n gateway-routes get httproute dex -o jsonpath="* ]] && printf '%s' "${args}" | grep -Fq '.path.value'; then
  printf '/dex/\n'
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
  [[ "${output}" == *"HTTPS https://dex.127.0.0.1.sslip.io/dex/ -> 200"* ]]
  [[ "${output}" != *"signoz.admin.127.0.0.1.sslip.io"* ]]
}

@test "check-gateway-urls fails when a discovered route stays down" {
  run env MOCK_GATEWAY_FAILURE=1 "${SCRIPT}" --execute --wait-seconds 0

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"HTTPS https://headlamp.admin.127.0.0.1.sslip.io/ -> 000"* ]]
  [[ "${output}" == *"curl exit 35"* ]]
  [[ "${output}" != *"signoz.admin.127.0.0.1.sslip.io"* ]]
}
