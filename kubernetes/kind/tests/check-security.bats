#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SECURITY_SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/check-security.sh"
}

@test "check-security uses a disposable curl probe pod for negative tests" {
  run grep -n 'POLICY_PROBE_POD="policy-probe"' "${SECURITY_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'POLICY_PROBE_IMAGE="curlimages/curl:8.19.0"' "${SECURITY_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'kubectl -n "\${POLICY_PROBE_NAMESPACE}" run "\${POLICY_PROBE_POD}"' "${SECURITY_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'curl -sS -o /dev/null --connect-timeout 3 --max-time 5 "\${url}"' "${SECURITY_SCRIPT}"

  [ "${status}" -eq 0 ]
}

@test "check-security waits for gateway hardening surfaces before evaluating headers and live config" {
  run grep -n 'wait_for_platform_gateway_hardening()' "${SECURITY_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'PLATFORM_GATEWAY_HEADERS=' "${SECURITY_SCRIPT}"

  [ "${status}" -eq 0 ]

  run grep -n 'PLATFORM_GATEWAY_NGINX_CONF=' "${SECURITY_SCRIPT}"

  [ "${status}" -eq 0 ]
}
