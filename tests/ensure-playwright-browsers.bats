#!/usr/bin/env bats
# shellcheck shell=bash disable=SC2030,SC2031

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/ensure-playwright-browsers.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export PLAYWRIGHT_BROWSERS_PATH="${BATS_TEST_TMPDIR}/ms-playwright"
  export SSO_PLAYWRIGHT_PROJECT_DIR="${BATS_TEST_TMPDIR}/sso"
  export INSTALL_CALLS="${BATS_TEST_TMPDIR}/install-calls"
  export BUN_CALLS="${BATS_TEST_TMPDIR}/bun-calls"
  export CURL_CALLS="${BATS_TEST_TMPDIR}/curl-calls"
  export CHILD_TERM_FLAG="${BATS_TEST_TMPDIR}/child-term"
  export INSTALL_STARTED_AT="${BATS_TEST_TMPDIR}/install-started-at"
  export CHILD_TERM_AT="${BATS_TEST_TMPDIR}/child-term-at"
  export HOME="${BATS_TEST_TMPDIR}/home"
  export PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS=5
  export PLAYWRIGHT_BROWSER_INSTALL_RETRIES=2
  export BROWSERS_JSON="${SSO_PLAYWRIGHT_PROJECT_DIR}/node_modules/playwright-core/browsers.json"

  mkdir -p "${TEST_BIN}" "${PLAYWRIGHT_BROWSERS_PATH}" "$(dirname "${BROWSERS_JSON}")" "${HOME}" "${SSO_PLAYWRIGHT_PROJECT_DIR}"
  cat >"${BROWSERS_JSON}" <<'EOF'
{
  "browsers": [
    { "name": "chromium", "revision": "1208" },
    { "name": "chromium-headless-shell", "revision": "1208" }
  ]
}
EOF

  cat >"${TEST_BIN}/node" <<'EOF'
#!/usr/bin/env bash
printf 'chromium\t1208\tchromium-1208\n'
printf 'chromium-headless-shell\t1208\tchromium_headless_shell-1208\n'
EOF
  chmod +x "${TEST_BIN}/node"

  cat >"${TEST_BIN}/bun" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${BUN_CALLS}"
case "$*" in
  "x playwright install chromium")
    printf '%s\n' "$*" >>"${INSTALL_CALLS}"
    case "${INSTALL_MODE:-success}" in
      success)
        mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1208"
        : >"${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208/INSTALLATION_COMPLETE"
        : >"${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1208/INSTALLATION_COMPLETE"
        ;;
      timeout)
        # Hi-res because the interesting quantity is under two seconds and
        # BSD date has no %N. perl is already a dependency of the script.
        perl -MTime::HiRes=time -e 'printf "%.3f", time' >"${INSTALL_STARTED_AT}"
        trap '' TERM
        (
          trap 'perl -MTime::HiRes=time -e '"'"'printf "%.3f", time'"'"' >"${CHILD_TERM_AT}"; printf child-term >"${CHILD_TERM_FLAG}"; exit 0' TERM
          while :; do sleep 1; done
        ) &
        wait
        ;;
      *)
        exit 2
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/bun"

  cat >"${TEST_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
  -m) printf 'arm64\n' ;;
  *) printf 'Darwin\n' ;;
esac
EOF
  chmod +x "${TEST_BIN}/uname"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${CURL_CALLS}"
printf '%s' "${CURL_STATUS:-200}"
EOF
  chmod +x "${TEST_BIN}/curl"

  export PATH="${TEST_BIN}:${PATH}"
}

complete_cache() {
  mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1208"
  : >"${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208/INSTALLATION_COMPLETE"
  : >"${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1208/INSTALLATION_COMPLETE"
}

@test "complete cache exits OK without invoking install" {
  complete_cache

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ ! -e "${INSTALL_CALLS}" ]
  [ ! -e "${CURL_CALLS}" ]
  [[ "${output}" == *"Playwright browser cache is complete"* ]]
}

@test "incomplete required directory is cleaned before install and validated" {
  mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1208" "${PLAYWRIGHT_BROWSERS_PATH}/__dirlock"
  : >"${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208/stale-file"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ "$(cat "${INSTALL_CALLS}")" = "x playwright install chromium" ]
  [[ "$(cat "${CURL_CALLS}")" == *"https://cdn.playwright.dev/dbazure/download/playwright/builds/chromium/1208/chromium-mac-arm64.zip"* ]]
  [ ! -e "${PLAYWRIGHT_BROWSERS_PATH}/__dirlock" ]
  [ -f "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208/INSTALLATION_COMPLETE" ]
  [ -f "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1208/INSTALLATION_COMPLETE" ]
  [ ! -e "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208/stale-file" ]
  [[ "${output}" == *"removing incomplete Playwright browser cache directory"* ]]
}

@test "install timeout kills process group, retries once, and fails loudly" {
  export INSTALL_MODE=timeout
  export PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS=1
  export PLAYWRIGHT_BROWSER_INSTALL_RETRIES=2

  run "${SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [ "$(grep -c '^x playwright install chromium$' "${INSTALL_CALLS}")" -eq 2 ]
  [ -f "${CHILD_TERM_FLAG}" ]
  [[ "${output}" == *"timed out after 1s; killing process group"* ]]
  [[ "${output}" == *"Playwright browser provisioning failed after 2 attempt(s)"* ]]
  [[ "${output}" == *"Remediation:"* ]]
}

@test "CDN preflight 200 proceeds to bun x install" {
  export CURL_STATUS=200

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [ "$(cat "${INSTALL_CALLS}")" = "x playwright install chromium" ]
  [[ "$(cat "${CURL_CALLS}")" == *"--max-time 10"* ]]
  [[ "$(cat "${CURL_CALLS}")" == *"chromium-mac-arm64.zip"* ]]
}

@test "CDN preflight 400 fails fast with both remediations" {
  export CURL_STATUS=400

  run "${SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [ ! -e "${INSTALL_CALLS}" ]
  [[ "${output}" == *"final HTTP status 400"* ]]
  [[ "${output}" == *"This network cannot fetch Playwright browsers"* ]]
  [[ "${output}" == *"PLATFORM_PLAYWRIGHT_CHANNEL=chrome"* ]]
  run bash -c 'docker_line=$(printf "%s\n" "$1" | grep -n "PLATFORM_PLAYWRIGHT_MODE=docker" | cut -d: -f1); chrome_line=$(printf "%s\n" "$1" | grep -n "PLATFORM_PLAYWRIGHT_CHANNEL=chrome" | cut -d: -f1); network_line=$(printf "%s\n" "$1" | grep -n "change networks and rerun" | cut -d: -f1); test -n "$docker_line" && test -n "$chrome_line" && test -n "$network_line" && test "$docker_line" -lt "$chrome_line" && test "$chrome_line" -lt "$network_line"' _ "${output}"
  [ "${status}" -eq 0 ]
}

@test "check-only complete cache reports OK without install" {
  complete_cache

  run "${SCRIPT}" --check --execute

  [ "${status}" -eq 0 ]
  [ ! -e "${INSTALL_CALLS}" ]
  [[ "${output}" == *"OK   Playwright browser cache is complete"* ]]
}

@test "check-only absent cache warns and exits zero" {
  rm -rf "${PLAYWRIGHT_BROWSERS_PATH}/chromium-1208" "${PLAYWRIGHT_BROWSERS_PATH}/chromium_headless_shell-1208"

  run "${SCRIPT}" --check --execute

  [ "${status}" -eq 0 ]
  [ ! -e "${INSTALL_CALLS}" ]
  [[ "${output}" == *"WARN Playwright browsers are absent or incomplete"* ]]
  [[ "${output}" == *"make playwright-install"* ]]
  [[ "${output}" == *"PLATFORM_PLAYWRIGHT_MODE=docker"* ]]
  [[ "${output}" == *"PLATFORM_PLAYWRIGHT_CHANNEL=chrome"* ]]
}

@test "install timeout waits the full budget before killing the process group" {
  # Regression guard for a flake that hit the gate once parallel runs began.
  #
  # `date +%s` has one-second granularity, and the elapsed check used to run
  # BEFORE the first sleep. If a second boundary fell between capturing the
  # start time and the first poll, `now - start` was already 1, so a 1s budget
  # fired immediately: the script announced "timed out after 1s" having waited
  # essentially none of it, and killed the install stub before it could append
  # its line to INSTALL_CALLS. The visible symptom was the neighbouring test
  # asserting two recorded attempts and finding one, intermittently, which
  # reads like load sensitivity and is not.
  #
  # Asserted as a lower bound on purpose. A busy machine can only make the gap
  # longer, so unlike an equality on the attempt count this cannot flake under
  # load -- which is the whole failure mode being fixed.
  export INSTALL_MODE=timeout
  export PLAYWRIGHT_BROWSER_INSTALL_TIMEOUT_SECONDS=1
  export PLAYWRIGHT_BROWSER_INSTALL_RETRIES=1

  # Force the boundary rather than wait for it. The defect needs a second tick
  # to fall between the script capturing start_seconds and its first poll,
  # which happens rarely enough in real time that a wall-clock test catches it
  # in roughly none of eight runs -- measured, after a first draft of this test
  # did exactly that. This date stub makes the crossing certain: the first call
  # is the start capture, every later one is a second later.
  export DATE_STUB_STATE="${BATS_TEST_TMPDIR}/date-calls"
  cat >"${TEST_BIN}/date" <<'STUB'
#!/bin/sh
n=0
if [ -r "${DATE_STUB_STATE}" ]; then read -r n <"${DATE_STUB_STATE}"; fi
n=$((n + 1))
printf '%s
' "${n}" >"${DATE_STUB_STATE}"
if [ "${n}" -eq 1 ]; then echo 1000; else echo 1001; fi
STUB
  chmod +x "${TEST_BIN}/date"

  run "${SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [ -f "${INSTALL_STARTED_AT}" ]
  [ -f "${CHILD_TERM_AT}" ]

  local waited
  waited="$(perl -e '
    open(my $a, "<", $ARGV[0]) or die; my $started = <$a>;
    open(my $b, "<", $ARGV[1]) or die; my $termed  = <$b>;
    printf "%d", ($termed - $started) * 1000;
  ' "${INSTALL_STARTED_AT}" "${CHILD_TERM_AT}")"

  # 500ms, sitting between the two outcomes rather than near either. The
  # measured gap is a real second of sleep minus the stub's own startup, which
  # lands around 890-905ms; the defect this guards produces close to 0ms. A
  # first draft of this test used 900ms and failed about half its runs -- the
  # threshold was inside the distribution it was meant to sit outside, which is
  # how you write a flake while fixing one.
  [ "${waited}" -ge 500 ]
}
