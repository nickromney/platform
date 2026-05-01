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
  "${SCRIPT}" --execute --host 127.0.0.1 --port "${port}" >"${BATS_TEST_TMPDIR}/ui.log" 2>&1 &
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
  [[ "${output}" == *'"kind"'* ]]
  [[ "${output}" == *'"950-local-idp"'* ]]
}

@test "platform workflow ui labels app defaults and only offers opposite overrides" {
  start_server 18743

  run curl -fsS "http://127.0.0.1:18743/"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Enable" : "Disable"} (stage default)'* ]]
  [[ "${output}" == *'label: enabledByDefault ? "Disable" : "Enable"'* ]]
  [[ "${output}" == *'value: enabledByDefault ? "off" : "on"'* ]]
  [[ "${output}" != *'<option value="">Stage default</option>'* ]]
  [[ "${output}" != *'${app} (stage default)'* ]]
  [[ "${output}" != *'Enable"} ${app}'* ]]
}

@test "platform workflow ui explains that it generates a terminal command" {
  start_server 18744

  run curl -fsS "http://127.0.0.1:18744/"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'id="status">loading options</div>'* ]]
  [[ "${output}" == *'This page generates the Make command to run in a terminal; it does not apply changes from the browser.'* ]]
  [[ "${output}" == *'Generate Terminal Command</button>'* ]]
  [[ "${output}" == *'id="copy-command" type="button">Copy</button>'* ]]
  [[ "${output}" == *'Terminal Command</h2>'* ]]
  [[ "${output}" == *'async function copyCommand()'* ]]
  [[ "${output}" == *'navigator.clipboard.writeText(command)'* ]]
  [[ "${output}" == *'document.execCommand("copy")'* ]]
  [[ "${output}" == *'$("status").textContent = "copied command"'* ]]
  [[ "${output}" != *'Generate Command</button>'* ]]
  [[ "${output}" == *'Select options to generate the exact command.'* ]]
  [[ "${output}" == *'$("status").textContent = "command current"'* ]]
  [[ "${output}" == *'$("status").textContent = "generating command"'* ]]
  [[ "${output}" != *'Preview Workflow</button>'* ]]
  [[ "${output}" != *'Select options to preview the exact command.'* ]]
  [[ "${output}" != *'$("status").textContent = "ready"'* ]]
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

  run curl -fsS -X POST "http://127.0.0.1:18742/api/preview" \
    -H 'content-type: application/json' \
    --data '{"target":"kind","stage":"900","action":"apply","profile":"","sentiment":"off","subnetcalc":"","auto_approve":true}'

  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"target": "kind"'* ]]
  [[ "${output}" == *'"stage": "900"'* ]]
  [[ "${output}" == *'"action": "apply"'* ]]
  [[ "${output}" == *'"sentiment": false'* ]]
  [[ "${output}" == *"make -C kubernetes/kind 900 apply AUTO_APPROVE=1"* ]]
}
