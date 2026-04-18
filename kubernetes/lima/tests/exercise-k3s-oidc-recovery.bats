#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export K3S_STATE_FILE="${BATS_TEST_TMPDIR}/k3s-state"
  export K3S_READYZ_FAILURES_FILE="${BATS_TEST_TMPDIR}/readyz-failures"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

write_kubectl_stub() {
  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_file="${K3S_STATE_FILE:?}"
failures_file="${K3S_READYZ_FAILURES_FILE:?}"
state="$(cat "${state_file}" 2>/dev/null || printf 'healthy')"
failures_remaining="$(cat "${failures_file}" 2>/dev/null || printf '0')"
joined="$*"

if [[ "${joined}" == *"--raw=/readyz"* || "${joined}" == *"--raw='/readyz'"* ]]; then
  if [[ "${state}" == "restarting" && "${failures_remaining}" -gt 0 ]]; then
    printf '%s' "$((failures_remaining - 1))" >"${failures_file}"
    if [[ "${failures_remaining}" -le 1 ]]; then
      printf '%s' "recovering" >"${state_file}"
    fi
    exit 1
  fi
  if [[ "${state}" == "recovering" ]]; then
    printf '%s' "healthy" >"${state_file}"
  fi
  exit 0
fi

if [[ "${joined}" == *" get gateway platform-gateway "* ]]; then
  if [[ "${state}" == "healthy" ]]; then
    if [[ "${joined}" == *'Programmed'* || "${joined}" == *'Accepted'* ]]; then
      printf 'True'
    fi
  else
    printf 'False'
  fi
  exit 0
fi

printf 'unexpected kubectl invocation: %s\n' "${joined}" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/kubectl"
}

write_limactl_stub() {
  cat >"${TEST_BIN}/limactl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_file="${K3S_STATE_FILE:?}"
failures_file="${K3S_READYZ_FAILURES_FILE:?}"
state="$(cat "${state_file}" 2>/dev/null || printf 'healthy')"
joined="$*"

if [[ "${joined}" == *" sudo systemctl restart k3s"* ]]; then
  printf '%s' "restarting" >"${state_file}"
  printf '%s' "1" >"${failures_file}"
  exit 0
fi

if [[ "${joined}" == *" sudo curl "* ]]; then
  if [[ "${state}" == "healthy" ]]; then
    printf '%s\n' '{"issuer":"ok"}'
    exit 0
  fi
  exit 1
fi

printf 'unexpected limactl invocation: %s\n' "${joined}" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/limactl"
}

write_configure_stub() {
  local mode="$1"
  local path="${BATS_TEST_TMPDIR}/configure-k3s-apiserver-oidc.sh"

  case "${mode}" in
    success)
      cat >"${path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "OK   simulated k3s OIDC configuration"
EOF
      ;;
    failure)
      cat >"${path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "FAIL simulated k3s OIDC configuration failure"
exit 19
EOF
      ;;
    *)
      echo "unknown configure stub mode: ${mode}" >&2
      return 1
      ;;
  esac

  chmod +x "${path}"
  printf '%s\n' "${path}"
}

@test "exercise-k3s-oidc-recovery emits machine-readable JSON for a forced k3s restart drill" {
  printf '%s' "healthy" >"${K3S_STATE_FILE}"
  printf '%s' "0" >"${K3S_READYZ_FAILURES_FILE}"
  write_kubectl_stub
  write_limactl_stub
  configure_stub="$(write_configure_stub success)"

  run env \
    K3S_STATE_FILE="${K3S_STATE_FILE}" \
    K3S_READYZ_FAILURES_FILE="${K3S_READYZ_FAILURES_FILE}" \
    LIMA_OIDC_CONFIGURE_SCRIPT="${configure_stub}" \
    OIDC_RECOVERY_FORMAT=json \
    "${REPO_ROOT}/kubernetes/lima/scripts/exercise-k3s-oidc-recovery.sh" --execute

  [ "${status}" -eq 0 ]
  json_output="${output}"

  run jq -r '[.ok, .status_code, .status_group, (.forced | tostring), (.degraded_observed | tostring), .preflight_state, .postflight_state, .force_mode, .configure_exit_code] | @tsv' <<<"${json_output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'true\tforced_k3s_restart_recovered\tsuccess\ttrue\ttrue\thealthy\thealthy\tk3s-restart\t0' ]

  run jq -e '.steps[] | select(.step == "force" and .outcome == "performed")' <<<"${json_output}"

  [ "${status}" -eq 0 ]

  run jq -r '.configure_log[0]' <<<"${json_output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "OK   simulated k3s OIDC configuration" ]
}

@test "exercise-k3s-oidc-recovery returns failure JSON when the configure step fails" {
  printf '%s' "healthy" >"${K3S_STATE_FILE}"
  printf '%s' "0" >"${K3S_READYZ_FAILURES_FILE}"
  write_kubectl_stub
  write_limactl_stub
  configure_stub="$(write_configure_stub failure)"

  run env \
    K3S_STATE_FILE="${K3S_STATE_FILE}" \
    K3S_READYZ_FAILURES_FILE="${K3S_READYZ_FAILURES_FILE}" \
    LIMA_OIDC_CONFIGURE_SCRIPT="${configure_stub}" \
    OIDC_RECOVERY_FORMAT=json \
    "${REPO_ROOT}/kubernetes/lima/scripts/exercise-k3s-oidc-recovery.sh" --execute

  [ "${status}" -eq 1 ]
  json_output="${output}"

  run jq -r '[.ok, .status_code, .status_group, .configure_exit_code, (.forced | tostring)] | @tsv' <<<"${json_output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'false\tconfigure_step_failed\tfailure\t19\tfalse' ]

  run jq -e '.steps[] | select(.step == "configure" and .outcome == "failed")' <<<"${json_output}"

  [ "${status}" -eq 0 ]
}
