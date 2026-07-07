#!/usr/bin/env bats
# shellcheck shell=bash

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/tests/kubernetes/sso/run.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export BUN_CALLS="${BATS_TEST_TMPDIR}/bun-calls"
  export DOCKER_CALLS="${BATS_TEST_TMPDIR}/docker-calls"
  export ENSURE_CALLS="${BATS_TEST_TMPDIR}/ensure-calls"
  export MKCERT_CAROOT="${BATS_TEST_TMPDIR}/mkcert"
  export PLAYWRIGHT_CORE_PACKAGE_JSON="${BATS_TEST_TMPDIR}/sso/node_modules/playwright-core/package.json"

  mkdir -p "${TEST_BIN}" "${MKCERT_CAROOT}" "$(dirname "${PLAYWRIGHT_CORE_PACKAGE_JSON}")"
  : >"${MKCERT_CAROOT}/rootCA.pem"
  cat >"${PLAYWRIGHT_CORE_PACKAGE_JSON}" <<'EOF'
{"version":"1.58.2-fixture"}
EOF

  cat >"${TEST_BIN}/node" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-p" ] && [[ "${2:-}" == *"playwright-core/package.json"* ]]; then
  sed -nE 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/p' "${PLAYWRIGHT_CORE_PACKAGE_JSON}"
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/node"

  cat >"${TEST_BIN}/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s|PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=%s\n' "$*" "${PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD:-}" >>"${BUN_CALLS}"

case "$*" in
  "install --frozen-lockfile")
    exit 0
    ;;
  "run test --")
    [ "${PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD:-}" = "1" ]
    exit 0
    ;;
  *)
    printf 'unexpected bun args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/bun"

  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${DOCKER_CALLS}"

case "$*" in
  "image inspect mcr.microsoft.com/playwright:v1.58.2-fixture-noble")
    exit 0
    ;;
  *" sh -lc "*getent*" host.docker.internal"*)
    printf '172.17.0.1\n'
    exit 0
    ;;
  run*)
    exit 0
    ;;
  *)
    printf 'unexpected docker args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/docker"

  cat >"${TEST_BIN}/mkcert" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${1:-}" = "-CAROOT" ]; then
  printf '%s\n' "${MKCERT_CAROOT}"
fi
EOF
  chmod +x "${TEST_BIN}/mkcert"

  export ENSURE_PLAYWRIGHT_BROWSERS="${BATS_TEST_TMPDIR}/ensure-playwright-browsers.sh"
  cat >"${ENSURE_PLAYWRIGHT_BROWSERS}" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${ENSURE_CALLS}"
EOF
  chmod +x "${ENSURE_PLAYWRIGHT_BROWSERS}"

  export PATH="${TEST_BIN}:${PATH}"
  export SSO_E2E_ENABLE_MCP=false
}

@test "SSO E2E runner provisions browsers before tests and disables test-time downloads" {
  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ "$(cat "${ENSURE_CALLS}")" = "--execute" ]
  grep -Fq 'install --frozen-lockfile|PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=' "${BUN_CALLS}"
  grep -Fq 'run test --|PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1' "${BUN_CALLS}"
}

@test "SSO E2E runner can skip browser provisioning for focused wrapper tests" {
  export SSO_E2E_SKIP_PLAYWRIGHT_INSTALL=1

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ ! -e "${ENSURE_CALLS}" ]
  grep -Fq 'run test --|PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1' "${BUN_CALLS}"
  [[ "${output}" == *"Skipping Playwright browser install because SSO_E2E_SKIP_PLAYWRIGHT_INSTALL=1"* ]]
}

@test "SSO E2E runner docker mode uses matching Playwright image and container wiring" {
  export PLATFORM_PLAYWRIGHT_MODE=docker

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ ! -e "${ENSURE_CALLS}" ]
  grep -Fq 'run --rm' "${DOCKER_CALLS}"
  grep -Fq 'mcr.microsoft.com/playwright:v1.58.2-fixture-noble' "${DOCKER_CALLS}"
  grep -Fq -- '-e SSO_E2E_HOST_RESOLVER_RULES=MAP *.127.0.0.1.sslip.io 172.17.0.1,MAP 127.0.0.1.sslip.io 172.17.0.1' "${DOCKER_CALLS}"
  grep -Fq -- '-e NODE_EXTRA_CA_CERTS=/certs/mkcert-rootCA.pem' "${DOCKER_CALLS}"
  grep -Fq 'npx playwright test' "${DOCKER_CALLS}"
}
