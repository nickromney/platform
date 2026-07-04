#!/usr/bin/env bats
# shellcheck shell=bash disable=SC2030,SC2031

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/tests/kubernetes/sso/run.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export BUN_CALLS="${BATS_TEST_TMPDIR}/bun-calls"
  export BUN_PLAYWRIGHT_COUNT_FILE="${BATS_TEST_TMPDIR}/playwright-count"
  export PLAYWRIGHT_LOCK_DIR="${BATS_TEST_TMPDIR}/ms-playwright/__dirlock"
  export PLAYWRIGHT_LOCK_REMOVED_FLAG="${BATS_TEST_TMPDIR}/lock-removed"
  export PLAYWRIGHT_LOCK_PRESERVED_FLAG="${BATS_TEST_TMPDIR}/lock-preserved"

  mkdir -p "${TEST_BIN}"

  cat >"${TEST_BIN}/node" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${TEST_BIN}/node"

  cat >"${TEST_BIN}/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"${BUN_CALLS}"

case "$*" in
  "install --frozen-lockfile")
    exit 0
    ;;
  "x playwright install chromium")
    count=0
    if [ -f "${BUN_PLAYWRIGHT_COUNT_FILE}" ]; then
      count="$(cat "${BUN_PLAYWRIGHT_COUNT_FILE}")"
    fi
    count=$((count + 1))
    printf '%s\n' "${count}" >"${BUN_PLAYWRIGHT_COUNT_FILE}"

    if [ "${count}" -eq 1 ]; then
      mkdir -p "${PLAYWRIGHT_LOCK_DIR}"
      if [ "${PLAYWRIGHT_LOCK_MODE}" = "stale" ]; then
        touch -t 202001010000 "${PLAYWRIGHT_LOCK_DIR}" 2>/dev/null || true
      fi
      printf 'Failed to install browsers\n' >&2
      printf 'Error:\n' >&2
      printf '  %s\n' "${PLAYWRIGHT_LOCK_DIR}" >&2
      exit 1
    fi

    if [ "${PLAYWRIGHT_LOCK_MODE}" = "stale" ]; then
      if [ ! -e "${PLAYWRIGHT_LOCK_DIR}" ]; then
        printf 'removed\n' >"${PLAYWRIGHT_LOCK_REMOVED_FLAG}"
      fi
    else
      if [ -d "${PLAYWRIGHT_LOCK_DIR}" ]; then
        printf 'preserved\n' >"${PLAYWRIGHT_LOCK_PRESERVED_FLAG}"
      fi
      rm -rf "${PLAYWRIGHT_LOCK_DIR}"
    fi
    exit 0
    ;;
  "run test --")
    exit 0
    ;;
  *)
    printf 'unexpected bun args: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/bun"

  export PATH="${TEST_BIN}:${PATH}"
  export SSO_E2E_ENABLE_MCP=false
  export SSO_E2E_PLAYWRIGHT_INSTALL_RETRIES=2
  export SSO_E2E_PLAYWRIGHT_INSTALL_RETRY_SECONDS=0
}

@test "SSO E2E runner removes stale Playwright install locks before retrying" {
  export PLAYWRIGHT_LOCK_MODE=stale
  export SSO_E2E_PLAYWRIGHT_STALE_LOCK_SECONDS=1

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ -f "${PLAYWRIGHT_LOCK_REMOVED_FLAG}" ]
  [ ! -e "${PLAYWRIGHT_LOCK_DIR}" ]
  [ "$(grep -c '^x playwright install chromium$' "${BUN_CALLS}")" -eq 2 ]
  [[ "${output}" == *"WARN removing stale Playwright browser cache lock"* ]]
}

@test "SSO E2E runner preserves active Playwright install locks while retrying" {
  export PLAYWRIGHT_LOCK_MODE=active
  export SSO_E2E_PLAYWRIGHT_STALE_LOCK_SECONDS=999999

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ -f "${PLAYWRIGHT_LOCK_PRESERVED_FLAG}" ]
  [ "$(grep -c '^x playwright install chromium$' "${BUN_CALLS}")" -eq 2 ]
  [[ "${output}" == *"WARN Playwright browser cache lock is active"* ]]
}
