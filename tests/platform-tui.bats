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

@test "platform tui plain chooser supports numbered interactive fallback" {
  run bash -c '
    set -euo pipefail
    export PLATFORM_TUI_FORCE_PLAIN=1
    source "$1"
    tui_choose "Target stack" kind lima slicer
  ' bash "${SCRIPT}" <<<"2"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Target stack"* ]]
  [[ "${output}" == *"2) lima"* ]]
  [[ "${output}" == *"lima"* ]]
}

@test "platform tui plain confirm accepts yes answers" {
  run bash -c '
    set -euo pipefail
    export PLATFORM_TUI_FORCE_PLAIN=1
    source "$1"
    tui_confirm "Run this workflow?"
  ' bash "${SCRIPT}" <<<"yes"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Run this workflow?"* ]]
}

@test "platform tui app toggle defaults are explicit for every target and stage" {
  run bash -c '
    set -euo pipefail
    source "$1"
    for target in kind lima slicer; do
      for stage in 100 200 300 400 500 600 700 800 900; do
        printf "%s %s sentiment %s\n" "$target" "$stage" "$(workflow_app_default_choice "$target" "$stage" sentiment)"
        printf "%s %s subnetcalc %s\n" "$target" "$stage" "$(workflow_app_default_choice "$target" "$stage" subnetcalc)"
      done
    done
    printf "kind 950-local-idp sentiment %s\n" "$(workflow_app_default_choice kind 950-local-idp sentiment)"
    printf "kind 950-local-idp subnetcalc %s\n" "$(workflow_app_default_choice kind 950-local-idp subnetcalc)"
  ' bash "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"unknown"* ]]
  [[ "${output}" == *"kind 100 sentiment Disable sentiment (stage default)"* ]]
  [[ "${output}" == *"lima 700 subnetcalc Enable subnetcalc (stage default)"* ]]
  [[ "${output}" == *"slicer 900 sentiment Enable sentiment (stage default)"* ]]
  [[ "${output}" == *"kind 950-local-idp sentiment Enable sentiment (stage default)"* ]]
  [[ "${output}" == *"kind 950-local-idp subnetcalc Disable subnetcalc (stage default)"* ]]
}

@test "platform tui app toggle override choices only offer the opposite of the default" {
  run bash -c '
    set -euo pipefail
    source "$1"
    printf "kind 100 sentiment %s\n" "$(workflow_app_override_choice kind 100 sentiment)"
    printf "kind 700 sentiment %s\n" "$(workflow_app_override_choice kind 700 sentiment)"
    printf "lima 600 subnetcalc %s\n" "$(workflow_app_override_choice lima 600 subnetcalc)"
    printf "slicer 900 subnetcalc %s\n" "$(workflow_app_override_choice slicer 900 subnetcalc)"
    printf "kind 950-local-idp subnetcalc %s\n" "$(workflow_app_override_choice kind 950-local-idp subnetcalc)"
  ' bash "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'kind 100 sentiment Enable sentiment\nkind 700 sentiment Disable sentiment\nlima 600 subnetcalc Enable subnetcalc\nslicer 900 subnetcalc Disable subnetcalc\nkind 950-local-idp subnetcalc Enable subnetcalc' ]
}

@test "platform tui can run the guided workflow path through the shared workflow script" {
  command -v script >/dev/null 2>&1 || skip "script not available"

  workflow_stub="${BATS_TEST_TMPDIR}/platform-workflow.sh"
  workflow_log="${BATS_TEST_TMPDIR}/platform-workflow.log"
  choose_file="${BATS_TEST_TMPDIR}/gum-choose.txt"
  confirm_file="${BATS_TEST_TMPDIR}/gum-confirm.txt"
  export MOCK_GUM_CHOOSE_FILE="${choose_file}"
  export MOCK_GUM_CONFIRM_FILE="${confirm_file}"
  printf '%s\n' \
    'Guided platform workflow' \
    'kind' \
    '700 app repos' \
    'apply' \
    'Disable sentiment' \
    'Enable subnetcalc (stage default)' \
    >"${choose_file}"
  printf '%s\n' 'yes' >"${confirm_file}"

  cat >"${workflow_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'workflow %s\n' "\$*" >>"${workflow_log}"
if [[ "\${1:-}" == "preview" ]]; then
  cat <<'JSON'
{"target":"kind","stack_path":"kubernetes/kind","stage":"700","action":"apply","tfvars_file":"/tmp/generated.tfvars","app_overrides":{"sentiment":false,"subnetcalc":null},"command":"env PLATFORM_TFVARS=/tmp/generated.tfvars make -C kubernetes/kind 700 apply AUTO_APPROVE=1"}
JSON
  exit 0
fi
printf 'workflow apply output\n'
EOF
  chmod +x "${workflow_stub}"

  install_gum_stub
  write_status_stub "if [[ \"\${3:-}\" == 'json' ]]; then
  cat <<'JSON'
{\"overall_state\":\"idle\",\"active_cluster_variant_path\":null,\"active_variant_path\":null,\"foreign_ports\":[],\"variants_order\":[],\"variants\":{},\"actions\":[]}
JSON
else
  printf 'unexpected text fallback\n'
fi"

  run script -q /dev/null env PATH="${PATH}" PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT}" PLATFORM_WORKFLOW_SCRIPT="${workflow_stub}" MOCK_GUM_CHOOSE_FILE="${MOCK_GUM_CHOOSE_FILE}" MOCK_GUM_CONFIRM_FILE="${MOCK_GUM_CONFIRM_FILE}" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"workflow apply output"* ]]

  run cat "${workflow_log}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"workflow preview --execute --output json --target kind --stage 700 --action apply --app sentiment=off --auto-approve"* ]]
  [[ "${output}" == *"workflow apply --execute --target kind --stage 700 --action apply --app sentiment=off --auto-approve"* ]]
}

@test "platform tui passes helper actions to the workflow script without exposing profiles" {
  command -v script >/dev/null 2>&1 || skip "script not available"

  workflow_stub="${BATS_TEST_TMPDIR}/platform-workflow-helper.sh"
  workflow_log="${BATS_TEST_TMPDIR}/platform-workflow-helper.log"
  choose_file="${BATS_TEST_TMPDIR}/gum-choose-helper.txt"
  confirm_file="${BATS_TEST_TMPDIR}/gum-confirm-helper.txt"
  export MOCK_GUM_CHOOSE_FILE="${choose_file}"
  export MOCK_GUM_CONFIRM_FILE="${confirm_file}"
  printf '%s\n' \
    'Guided platform workflow' \
    'kind' \
    '900 sso' \
    'check-health' \
    'Enable sentiment (stage default)' \
    'Enable subnetcalc (stage default)' \
    >"${choose_file}"
  printf '%s\n' 'yes' >"${confirm_file}"

  cat >"${workflow_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'workflow %s\n' "\$*" >>"${workflow_log}"
if [[ "\${1:-}" == "preview" ]]; then
  cat <<'JSON'
{"target":"kind","stack_path":"kubernetes/kind","stage":"900","action":"check-health","profile":{"name":null,"path":null},"tfvars_file":null,"app_overrides":{"sentiment":null,"subnetcalc":null},"command":"make -C kubernetes/kind 900 check-health"}
JSON
  exit 0
fi
printf 'workflow helper output\n'
EOF
  chmod +x "${workflow_stub}"

  install_gum_stub
  write_status_stub "if [[ \"\${3:-}\" == 'json' ]]; then
  cat <<'JSON'
{\"overall_state\":\"idle\",\"active_cluster_variant_path\":null,\"active_variant_path\":null,\"foreign_ports\":[],\"variants_order\":[],\"variants\":{},\"actions\":[]}
JSON
else
  printf 'unexpected text fallback\n'
fi"

  run script -q /dev/null env PATH="${PATH}" PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT}" PLATFORM_WORKFLOW_SCRIPT="${workflow_stub}" MOCK_GUM_CHOOSE_FILE="${MOCK_GUM_CHOOSE_FILE}" MOCK_GUM_CONFIRM_FILE="${MOCK_GUM_CONFIRM_FILE}" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"workflow helper output"* ]]

  run cat "${workflow_log}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"workflow preview --execute --output json --target kind --stage 900 --action check-health"* ]]
  [[ "${output}" == *"workflow apply --execute --target kind --stage 900 --action check-health"* ]]
  [[ "${output}" != *"--profile"* ]]
  [[ "${output}" != *"--auto-approve"* ]]
}

@test "platform tui stack selection opens stage and action workflow choices" {
  command -v script >/dev/null 2>&1 || skip "script not available"

  workflow_stub="${BATS_TEST_TMPDIR}/platform-workflow-stack.sh"
  workflow_log="${BATS_TEST_TMPDIR}/platform-workflow-stack.log"
  choose_file="${BATS_TEST_TMPDIR}/gum-choose.txt"
  confirm_file="${BATS_TEST_TMPDIR}/gum-confirm.txt"
  export MOCK_GUM_CHOOSE_FILE="${choose_file}"
  export MOCK_GUM_CONFIRM_FILE="${confirm_file}"
  printf '%s\n' \
    'kubernetes/kind' \
    '300 hubble' \
    'plan' \
    'Disable sentiment (stage default)' \
    'Disable subnetcalc (stage default)' \
    >"${choose_file}"
  printf '%s\n' 'yes' >"${confirm_file}"

  cat >"${workflow_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'workflow %s\n' "\$*" >>"${workflow_log}"
if [[ "\${1:-}" == "preview" ]]; then
  cat <<'JSON'
{"target":"kind","stack_path":"kubernetes/kind","stage":"300","action":"plan","profile":{"name":null,"path":null},"tfvars_file":null,"app_overrides":{"sentiment":null,"subnetcalc":null},"command":"make -C kubernetes/kind 300 plan"}
JSON
  exit 0
fi
printf 'stack workflow output\n'
EOF
  chmod +x "${workflow_stub}"

  install_gum_stub
  write_status_stub "printf 'unexpected status call\n'"

  run script -q /dev/null env PATH="${PATH}" PLATFORM_STATUS_SCRIPT="${PLATFORM_STATUS_SCRIPT}" PLATFORM_WORKFLOW_SCRIPT="${workflow_stub}" MOCK_GUM_CHOOSE_FILE="${MOCK_GUM_CHOOSE_FILE}" MOCK_GUM_CONFIRM_FILE="${MOCK_GUM_CONFIRM_FILE}" "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"stack workflow output"* ]]

  run cat "${workflow_log}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"workflow preview --execute --output json --target kind --stage 300 --action plan"* ]]
  [[ "${output}" == *"workflow apply --execute --target kind --stage 300 --action plan"* ]]
}
