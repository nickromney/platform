#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export KUBECTL_STATE_FILE="${BATS_TEST_TMPDIR}/health-state"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

write_kubectl_stub() {
  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_file="${KUBECTL_STATE_FILE:?}"
state="$(cat "${state_file}" 2>/dev/null || printf 'healthy')"
joined="$*"

if [[ "${joined}" == *" get deploy nginx-gateway -o name"* ]]; then
  printf '%s\n' "deployment.apps/nginx-gateway"
  exit 0
fi

if [[ "${joined}" == *" rollout restart deploy/nginx-gateway"* ]]; then
  printf '%s' "degraded" >"${state_file}"
  exit 0
fi

if [[ "${joined}" == *" rollout status deploy/"* ]]; then
  if [[ "${state}" == "healthy" ]]; then
    exit 0
  fi
  exit 1
fi

if [[ "${joined}" == *" get endpoints "* ]]; then
  if [[ "${state}" == "healthy" ]]; then
    printf '10.0.0.10 '
  fi
  exit 0
fi

if [[ "${joined}" == *" get gateway platform-gateway "* ]]; then
  if [[ "${state}" == "healthy" ]]; then
    printf 'True'
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

write_recovery_stub() {
  local mode="$1"
  local path="${BATS_TEST_TMPDIR}/recover-kind-cluster-after-apiserver-restart.sh"

  case "${mode}" in
    success)
      cat >"${path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "OK   simulated recovery"
printf '%s' "healthy" >"${KUBECTL_STATE_FILE:?}"
EOF
      ;;
    failure)
      cat >"${path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "FAIL simulated recovery failure"
exit 17
EOF
      ;;
    *)
      echo "unknown recovery stub mode: ${mode}" >&2
      return 1
      ;;
  esac

  chmod +x "${path}"
  printf '%s\n' "${path}"
}

@test "exercise-kind-oidc-recovery emits machine-readable JSON for a forced recovery run" {
  printf '%s' "healthy" >"${KUBECTL_STATE_FILE}"
  write_kubectl_stub
  recovery_stub="$(write_recovery_stub success)"

  run env \
    KUBECTL_STATE_FILE="${KUBECTL_STATE_FILE}" \
    KIND_OIDC_RECOVERY_SCRIPT="${recovery_stub}" \
    OIDC_RECOVERY_FORMAT=json \
    "${REPO_ROOT}/terraform/kubernetes/scripts/exercise-kind-oidc-recovery.sh" --execute

  [ "${status}" -eq 0 ]
  json_output="${output}"

  run jq -r '[.ok, .status_code, .status_group, (.forced | tostring), .preflight_state, .postflight_state, .force_mode, .recovery_exit_code] | @tsv' <<<"${json_output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'true\tforced_recovery_succeeded\tsuccess\ttrue\thealthy\thealthy\tnginx-rollout\t0' ]

  run jq -e '.steps[] | select(.step == "force" and .outcome == "performed")' <<<"${json_output}"

  [ "${status}" -eq 0 ]

  run jq -r '.recovery_log[0]' <<<"${json_output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "OK   simulated recovery" ]
}

@test "exercise-kind-oidc-recovery returns failure JSON when delegated recovery fails" {
  printf '%s' "healthy" >"${KUBECTL_STATE_FILE}"
  write_kubectl_stub
  recovery_stub="$(write_recovery_stub failure)"

  run env \
    KUBECTL_STATE_FILE="${KUBECTL_STATE_FILE}" \
    KIND_OIDC_RECOVERY_SCRIPT="${recovery_stub}" \
    OIDC_RECOVERY_FORMAT=json \
    "${REPO_ROOT}/terraform/kubernetes/scripts/exercise-kind-oidc-recovery.sh" --execute

  [ "${status}" -eq 1 ]
  json_output="${output}"

  run jq -r '[.ok, .status_code, .status_group, .recovery_exit_code, .postflight_state] | @tsv' <<<"${json_output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = $'false\trecovery_flow_failed\tfailure\t17\tdegraded' ]

  run jq -e '.steps[] | select(.step == "recovery" and .outcome == "failed")' <<<"${json_output}"

  [ "${status}" -eq 0 ]
}
