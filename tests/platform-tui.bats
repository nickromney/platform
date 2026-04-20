#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-tui.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export STATUS_STUB="${BATS_TEST_TMPDIR}/platform-status.sh"
  export PLATFORM_STATUS_SCRIPT="${STATUS_STUB}"
}

write_status_stub() {
  local body="$1"

  cat >"${STATUS_STUB}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
${body}
EOF
  chmod +x "${STATUS_STUB}"
}

install_gum_stub() {
  cat >"${TEST_BIN}/gum" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

next_response() {
  local file="${1:?response file required}"
  local first=""
  first="$(sed -n '1p' "${file}")"
  tail -n +2 "${file}" > "${file}.next" 2>/dev/null || true
  mv "${file}.next" "${file}"
  printf '%s\n' "${first}"
}

subcommand="${1:-}"
shift || true

case "${subcommand}" in
  choose)
    next_response "${MOCK_GUM_CHOOSE_FILE}"
    ;;
  confirm)
    if [[ -n "${MOCK_GUM_CONFIRM_FILE:-}" && -f "${MOCK_GUM_CONFIRM_FILE}" ]]; then
      response="$(next_response "${MOCK_GUM_CONFIRM_FILE}")"
      [[ "${response}" == "yes" ]]
      exit $?
    fi
    exit "${MOCK_GUM_CONFIRM_EXIT:-0}"
    ;;
  style)
    printf '%s\n' "$*" | sed -E 's/--[^ ]+ ?//g' | sed '/^[[:space:]]*$/d'
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/gum"
}

@test "platform tui falls back to plain status when gum is unavailable" {
  log_file="${BATS_TEST_TMPDIR}/status.log"

  write_status_stub "printf 'status %s\n' \"\$*\" >>\"${log_file}\"; printf 'plain status fallback\n'"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"plain status fallback"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'status --execute --output text' ]
}

@test "platform tui shows disabled action reasons from status json" {
  command -v script >/dev/null 2>&1 || skip "script not available"

  choose_file="${BATS_TEST_TMPDIR}/gum-choose.txt"
  export MOCK_GUM_CHOOSE_FILE="${choose_file}"
  printf '%s\n' \
    'kubernetes/kind' \
    'Kind stage 900 apply' \
    'Back' \
    'Quit' \
    >"${choose_file}"

  install_gum_stub
  write_status_stub "if [[ \"\${3:-}\" == 'json' ]]; then
  cat <<'JSON'
{\"overall_state\":\"running\",\"active_cluster_variant_path\":\"kubernetes/lima\",\"active_variant_path\":\"kubernetes/lima\",\"foreign_ports\":[],\"variants_order\":[\"kind\"],\"variants\":{\"kind\":{\"path\":\"kubernetes/kind\",\"label\":\"Kind local cluster\"}},\"actions\":[{\"id\":\"kind-apply-900\",\"label\":\"Kind stage 900 apply\",\"variant\":\"kind\",\"variant_path\":\"kubernetes/kind\",\"enabled\":false,\"reason\":\"kubernetes/lima must be cleared first\",\"command\":\"make -C kubernetes/kind 900 apply AUTO_APPROVE=1\",\"dangerous\":true}]}
JSON
else
  printf 'unexpected text fallback\n'
fi"

  run script -q /dev/null env PATH="${PATH}" PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT}" MOCK_GUM_CHOOSE_FILE="${MOCK_GUM_CHOOSE_FILE}" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kubernetes/lima must be cleared first"* ]]
}

@test "platform tui executes enabled read-only actions directly" {
  command -v script >/dev/null 2>&1 || skip "script not available"

  action_log="${BATS_TEST_TMPDIR}/read-only-action.log"
  action_stub="${BATS_TEST_TMPDIR}/read-only-action.sh"
  choose_file="${BATS_TEST_TMPDIR}/gum-choose.txt"
  export MOCK_GUM_CHOOSE_FILE="${choose_file}"
  printf '%s\n' \
    'kubernetes/kind' \
    'Kind status' \
    >"${choose_file}"

  cat >"${action_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'ran read-only\n' >>"${action_log}"
printf 'read-only action output\n'
EOF
  chmod +x "${action_stub}"

  install_gum_stub
  write_status_stub "if [[ \"\${3:-}\" == 'json' ]]; then
  cat <<'JSON'
{\"overall_state\":\"idle\",\"active_cluster_variant_path\":null,\"active_variant_path\":null,\"foreign_ports\":[],\"variants_order\":[\"kind\"],\"variants\":{\"kind\":{\"path\":\"kubernetes/kind\",\"label\":\"Kind local cluster\"}},\"actions\":[{\"id\":\"kind-status\",\"label\":\"Kind status\",\"variant\":\"kind\",\"variant_path\":\"kubernetes/kind\",\"enabled\":true,\"reason\":null,\"command\":\"${action_stub}\",\"dangerous\":false}]}
JSON
else
  printf 'unexpected text fallback\n'
fi"

  run script -q /dev/null env PATH="${PATH}" PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT}" MOCK_GUM_CHOOSE_FILE="${MOCK_GUM_CHOOSE_FILE}" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"read-only action output"* ]]

  run cat "${action_log}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'ran read-only' ]
}

@test "platform tui confirms dangerous actions before executing them" {
  command -v script >/dev/null 2>&1 || skip "script not available"

  action_log="${BATS_TEST_TMPDIR}/dangerous-action.log"
  action_stub="${BATS_TEST_TMPDIR}/dangerous-action.sh"
  choose_file="${BATS_TEST_TMPDIR}/gum-choose.txt"
  confirm_file="${BATS_TEST_TMPDIR}/gum-confirm.txt"
  export MOCK_GUM_CHOOSE_FILE="${choose_file}"
  export MOCK_GUM_CONFIRM_FILE="${confirm_file}"
  printf '%s\n' \
    'kubernetes/kind' \
    'Kind stage 900 apply' \
    >"${choose_file}"
  printf '%s\n' 'yes' >"${confirm_file}"

  cat >"${action_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'ran dangerous\n' >>"${action_log}"
printf 'dangerous action output\n'
EOF
  chmod +x "${action_stub}"

  install_gum_stub
  write_status_stub "if [[ \"\${3:-}\" == 'json' ]]; then
  cat <<'JSON'
{\"overall_state\":\"idle\",\"active_cluster_variant_path\":null,\"active_variant_path\":null,\"foreign_ports\":[],\"variants_order\":[\"kind\"],\"variants\":{\"kind\":{\"path\":\"kubernetes/kind\",\"label\":\"Kind local cluster\"}},\"actions\":[{\"id\":\"kind-apply-900\",\"label\":\"Kind stage 900 apply\",\"variant\":\"kind\",\"variant_path\":\"kubernetes/kind\",\"enabled\":true,\"reason\":null,\"command\":\"${action_stub}\",\"dangerous\":true}]}
JSON
else
  printf 'unexpected text fallback\n'
fi"

  run script -q /dev/null env PATH="${PATH}" PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT}" MOCK_GUM_CHOOSE_FILE="${MOCK_GUM_CHOOSE_FILE}" MOCK_GUM_CONFIRM_FILE="${MOCK_GUM_CONFIRM_FILE}" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"dangerous action output"* ]]

  run cat "${action_log}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'ran dangerous' ]
}
