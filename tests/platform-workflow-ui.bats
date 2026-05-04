#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-workflow-ui.sh"
}

teardown() {
  if [[ -n "${SERVER_PID:-}" ]]; then
    kill "${SERVER_PID}" >/dev/null 2>&1 || true
    wait "${SERVER_PID}" >/dev/null 2>&1 || true
  fi
}

start_server() {
  port="$1"
  "${SCRIPT}" --execute --host 127.0.0.1 --port "${port}" --http http1 >"${BATS_TEST_TMPDIR}/ui.log" 2>&1 &
  SERVER_PID="$!"

  for _ in {1..50}; do
    if curl -fsS "http://127.0.0.1:${port}/health" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  cat "${BATS_TEST_TMPDIR}/ui.log" >&2 || true
  return 1
}

@test "platform workflow ui exposes workflow options from the shared core" {
  start_server 18741

  run curl -fsS "http://127.0.0.1:18741/api/options"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"variants"'* ]]
  [[ "${output}" == *'"variant_classes"'* ]]
  [[ "${output}" == *'"contexts"'* ]]
  [[ "${output}" == *'"contracts"'* ]]
  [[ "${output}" == *'"kubernetes/kind"'* ]]
  [[ "${output}" == *'"local-created-cluster"'* ]]
  [[ "${output}" != *'"targets"'* ]]
  [[ "${output}" != *'"950-local-idp"'* ]]
}

@test "platform workflow ui dry-run defaults to h2 https console URL" {
  run "${SCRIPT}" --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"https://console.127.0.0.1.sslip.io:8443 (h2)"* ]]
}

@test "platform workflow ui dry-run can opt into plain http" {
  run "${SCRIPT}" --dry-run --host 127.0.0.1 --port 18746 --http http1

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"http://127.0.0.1:18746 (http1)"* ]]
}

@test "platform workflow ui startup prints the canonical custom url" {
  port=18749
  "${SCRIPT}" --execute --host console.127.0.0.1.sslip.io --port "${port}" --http h2 >"${BATS_TEST_TMPDIR}/ui-startup.log" 2>&1 &
  SERVER_PID="$!"

  for _ in {1..50}; do
    if grep -F "Open https://console.127.0.0.1.sslip.io:${port}" "${BATS_TEST_TMPDIR}/ui-startup.log" >/dev/null 2>&1; then
      return 0
    fi
    if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      cat "${BATS_TEST_TMPDIR}/ui-startup.log" >&2 || true
      return 1
    fi
    sleep 0.1
  done

  cat "${BATS_TEST_TMPDIR}/ui-startup.log" >&2 || true
  return 1
}

@test "platform workflow ui generates hostname-specific certificates" {
  bin_dir="${BATS_TEST_TMPDIR}/bin"
  cert_dir="${BATS_TEST_TMPDIR}/certs"
  log_file="${BATS_TEST_TMPDIR}/mkcert.log"
  mkdir -p "${bin_dir}" "${cert_dir}"

  cat >"${bin_dir}/mkcert" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >"${log_file}"
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -cert-file) cert="\$2"; shift 2 ;;
    -key-file) key="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf 'cert' >"\${cert}"
printf 'key' >"\${key}"
EOF
  chmod +x "${bin_dir}/mkcert"

  PATH="${bin_dir}:${PATH}" "${SCRIPT}" \
    --execute \
    --host console.127.0.0.1.sslip.io \
    --port 18751 \
    --http h2 \
    --tls-cert-dir "${cert_dir}" >"${BATS_TEST_TMPDIR}/ui-cert.log" 2>&1 &
  SERVER_PID="$!"

  for _ in {1..50}; do
    if grep -F "workflow-ui-console.127.0.0.1.sslip.io" "${log_file}" >/dev/null 2>&1; then
      break
    fi
    if ! kill -0 "${SERVER_PID}" >/dev/null 2>&1; then
      cat "${BATS_TEST_TMPDIR}/ui-cert.log" >&2 || true
      return 1
    fi
    sleep 0.1
  done

  run cat "${log_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"-cert-file ${cert_dir}/workflow-ui-console.127.0.0.1.sslip.io"* ]]
  [[ "${output}" == *"console.127.0.0.1.sslip.io"* ]]
}

@test "platform workflow ui rejects unsupported http modes" {
  run "${SCRIPT}" --execute --http h3

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Invalid --http 'h3'. Expected http1 or h2"* ]]
}

@test "platform workflow ui explains unprivileged low port binds" {
  run "${SCRIPT}" --execute --port 443

  if [[ "$(id -u)" -eq 0 ]]; then
    skip "root can bind low ports"
  fi

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Port 443 requires elevated privileges"* ]]
  [[ "${output}" == *"Use WORKFLOW_UI_PORT=8443"* ]]
}

@test "platform workflow ui labels app defaults and only offers opposite overrides" {
  start_server 18743

  run curl -fsS "http://127.0.0.1:18743/"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Default: enabled'* ]]
  [[ "${output}" == *'name="sentiment"'* ]]
  [[ "${output}" == *'name="subnetcalc"'* ]]
  [[ "${output}" == *'<option value="on" selected>Enabled</option>'* ]]
  [[ "${output}" == *'<option value="off">Disabled</option>'* ]]
  [[ "${output}" != *'Stage default: enabled'* ]]
  [[ "${output}" != *'Enable sentiment (stage default)'* ]]
  [[ "${output}" != *'Enable subnetcalc (stage default)'* ]]
  [[ "${output}" != *'<option value="">Stage default</option>'* ]]
}

@test "platform workflow ui serves a small htmx page without implementation chrome" {
  start_server 18744

  run curl -fsS "http://127.0.0.1:18744/"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *'FastAPI + HTMX, no Node build'* ]]
  [[ "${output}" == *'hx-post="/preview"'* ]]
  [[ "${output}" == *'hx-target="#result"'* ]]
  [[ "${output}" != *'Local operator console'* ]]
  [[ "${output}" != *'<h1>Platform Workflow</h1>'* ]]
  [[ "${output}" == *'<section class="quick-actions" aria-label="Quick actions">'* ]]
  [[ "${output}" != *'<h2>Quick actions</h2>'* ]]
  [[ "${output}" != *'Quick actions run immediately, except Reset.'* ]]
  [[ "${output}" != *'Preview</button>'* ]]
  [[ "${output}" == *'/static/htmx.min.js'* ]]
  [[ "${output}" != *'node_modules'* ]]
}

@test "platform workflow ui recent commands include timestamps and mark newest" {
  run uv run --project "${REPO_ROOT}/tools/platform-workflow-ui" python - <<'PY'
from platform_workflow_ui.main import history_panel

print(history_panel([
    {"kind": "Run", "variant": "kubernetes/kind", "timestamp": "09:15:03", "exit_status": "0", "command": "make -C kubernetes/kind 900 apply AUTO_APPROVE=1"},
    {"kind": "Run", "variant": "kubernetes/kind", "timestamp": "09:11:42", "exit_status": "1", "command": "make -C kubernetes/kind status"},
], current_variant="kubernetes/lima"))
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'<span class="history-current" aria-label="Most recent">&rarr;</span>'* ]]
  [[ "${output}" == *'<time datetime="09:15:03">09:15:03</time>'* ]]
  [[ "${output}" == *'<time datetime="09:11:42">09:11:42</time>'* ]]
  [[ "${output}" == *'<span class="history-status-ok">Succeeded</span>'* ]]
  [[ "${output}" == *'<span class="history-status-failed">Failed (1)</span>'* ]]
  [[ "${output}" == *'Latest run was for kubernetes/kind'* ]]
  [[ "${output}" == *'recent-command-0'* ]]
  [[ "${output}" == *'recent-command-1'* ]]
}

@test "platform workflow ui serves the shared favicon" {
  start_server 18745

  run curl -fsS -D "${BATS_TEST_TMPDIR}/favicon.headers" \
    -o "${BATS_TEST_TMPDIR}/favicon.ico" \
    "http://127.0.0.1:18745/favicon.ico"

  [ "${status}" -eq 0 ]
  [[ "$(tr '[:upper:]' '[:lower:]' <"${BATS_TEST_TMPDIR}/favicon.headers")" == *"content-type: image/x-icon"* ]]
  [ -s "${BATS_TEST_TMPDIR}/favicon.ico" ]
}

@test "platform workflow ui previews the selected kind 900 apply intent" {
  start_server 18742

  run curl -fsS -X POST "http://127.0.0.1:18742/preview" \
    -H 'content-type: application/x-www-form-urlencoded' \
    --data 'variant=kubernetes/kind&stage=900&action=apply&sentiment=off&subnetcalc=&auto_approve=1'

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'<strong>kubernetes/kind</strong>'* ]]
  [[ "${output}" == *'<strong>900</strong>'* ]]
  [[ "${output}" == *'<strong>apply</strong>'* ]]
  [[ "${output}" == *"make -C kubernetes/kind 900 apply AUTO_APPROVE=1"* ]]
  [[ "${output}" == *'hx-post="/run"'* ]]
  [[ "${output}" == *'copyCommand('\''command-text'\'''* ]]
  [[ "${output}" != *'<section class="quick-actions" aria-label="Quick actions">'* ]]
  [[ "${output}" == *'id="history"'* ]]
  [[ "${output}" == *'hx-swap-oob="outerHTML"'* ]]
  [[ "${output}" != *'<h2>Recent commands</h2>'* ]]
}
