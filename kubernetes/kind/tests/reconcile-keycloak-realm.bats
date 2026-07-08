#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/reconcile-keycloak-realm.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export MOCK_KUBECTL_STATE_DIR="${BATS_TEST_TMPDIR}/state"
  mkdir -p "${TEST_BIN}" "${MOCK_KUBECTL_STATE_DIR}"
  export PATH="${TEST_BIN}:${PATH}"

  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_dir="${MOCK_KUBECTL_STATE_DIR:?}"
args="$*"

if [[ "${args}" == "-n sso get configmap keycloak-realm -o json" ]]; then
  cat <<'JSON'
{"data":{"platform-realm.json":"{\"realm\":\"platform\",\"clientScopes\":[],\"groups\":[],\"clients\":[],\"users\":[{\"username\":\"demo-user\",\"enabled\":true,\"credentials\":[{\"value\":\"demo-password\",\"temporary\":false}],\"groups\":[\"platform-viewers\"]}]}"}}
JSON
  exit 0
fi

if [[ "${args}" == "-n sso rollout status deployment/keycloak --timeout=300s" ]]; then
  exit 0
fi

if [[ "${args}" == "-n sso get pods -l app.kubernetes.io/name=keycloak -o jsonpath={.items[0].metadata.name}" ]]; then
  printf 'keycloak-0'
  exit 0
fi

if [[ "${args}" == "-n sso get secret keycloak-admin -o jsonpath={.data.username}" ]]; then
  printf 'a2V5Y2xvYWstYWRtaW4='
  exit 0
fi

if [[ "${args}" == "-n sso get secret keycloak-admin -o jsonpath={.data.password}" ]]; then
  printf 'cGVybWFuZW50LXBhc3N3b3Jk'
  exit 0
fi

if [[ "${args}" == "-n sso get secret keycloak-bootstrap-admin -o jsonpath={.data.username}" ]]; then
  printf 'Ym9vdHN0cmFwLWFkbWlu'
  exit 0
fi

if [[ "${args}" == "-n sso get secret keycloak-bootstrap-admin -o jsonpath={.data.password}" ]]; then
  printf 'Ym9vdHN0cmFwLXBhc3N3b3Jk'
  exit 0
fi

if [[ "${args}" != *"kcadm.sh "* ]]; then
  echo "unexpected kubectl invocation: ${args}" >&2
  exit 99
fi

command="${args#*kcadm.sh }"
printf '%s\n' "${command}" >>"${state_dir}/kcadm-commands.log"

case "${command}" in
  config\ credentials*)
    printf '%s\n' "${command}" >>"${state_dir}/login-commands.log"
    exit 0
    ;;
  get\ users*\ username=keycloak-admin\ *)
    printf '[{"id":"admin-id","username":"keycloak-admin"}]'
    exit 0
    ;;
  get\ users*\ username=demo-user\ *)
    printf '[{"id":"demo-user-id","username":"demo-user"}]'
    exit 0
    ;;
  get\ users*\ username=bootstrap-admin\ *|get\ users*\ username=demo@admin.test\ *)
    printf '[]'
    exit 0
    ;;
  get\ users*)
    printf '[]'
    exit 0
    ;;
  get\ groups*\ search=platform-admins*)
    printf '[{"id":"platform-admins-id","name":"platform-admins"}]'
    exit 0
    ;;
  get\ groups*\ search=platform-viewers*)
    printf '[{"id":"platform-viewers-id","name":"platform-viewers"}]'
    exit 0
    ;;
  get\ clients*\ clientId=realm-management*)
    printf '[{"id":"realm-management-id","clientId":"realm-management"}]'
    exit 0
    ;;
  get\ *role-mappings*)
    printf '[]'
    exit 0
    ;;
  update\ users/*/groups/*)
    exit 0
    ;;
  update\ users/demo-user-id*)
    stdin_body="$(cat)"
    {
      printf '%s\n' '---stdin---'
      printf '%s\n' "${stdin_body}"
    } >>"${state_dir}/user-update-stdin.log"

    if [[ "${MOCK_KCADM_FAIL_MODE:-}" == "401" && ! -f "${state_dir}/user-update-401-seen" ]]; then
      touch "${state_dir}/user-update-401-seen"
      echo "null [HTTP 401 Unauthorized]" >&2
      exit 1
    fi

    if [[ "${MOCK_KCADM_FAIL_MODE:-}" == "non401" ]]; then
      echo "plain kcadm failure" >&2
      exit 7
    fi

    exit 0
    ;;
  add-roles*)
    if [[ "${MOCK_KCADM_FAIL_MODE:-}" == "non401" ]]; then
      echo "plain kcadm failure" >&2
      exit 7
    fi
    exit 0
    ;;
  update\ users/*|set-password*)
    exit 0
    ;;
esac

echo "unexpected kcadm command: ${command}" >&2
exit 99
EOF
  chmod +x "${TEST_BIN}/kubectl"
}

function test_reconcile_keycloak_realm_retries_one_kcadm_401_after_relogin_and_replays_stdin { #@test
  MOCK_KCADM_FAIL_MODE=401
  export MOCK_KCADM_FAIL_MODE
  stdout_file="${BATS_TEST_TMPDIR}/stdout.txt"
  stderr_file="${BATS_TEST_TMPDIR}/stderr.txt"

  "${SCRIPT}" --execute >"${stdout_file}" 2>"${stderr_file}"

  grep -Fq "Keycloak realm reconciled: platform" "${stdout_file}"
  if grep -Fq "WARN" "${stdout_file}"; then
    return 1
  fi
  grep -Fq "WARN Keycloak admin token returned HTTP 401; re-authenticating and retrying kcadm once" "${stderr_file}"
  [ "$(grep -Fc -- "--user keycloak-admin" "${MOCK_KUBECTL_STATE_DIR}/login-commands.log")" -ge 3 ]
  [ "$(grep -Fc -- "---stdin---" "${MOCK_KUBECTL_STATE_DIR}/user-update-stdin.log")" -eq 2 ]
  [ "$(grep -Fc '"username":"demo-user"' "${MOCK_KUBECTL_STATE_DIR}/user-update-stdin.log")" -eq 2 ]
}

function test_reconcile_keycloak_realm_does_not_retry_non_401_kcadm_failures { #@test
  MOCK_KCADM_FAIL_MODE=non401
  export MOCK_KCADM_FAIL_MODE
  stdout_file="${BATS_TEST_TMPDIR}/stdout.txt"
  stderr_file="${BATS_TEST_TMPDIR}/stderr.txt"

  status=0
  bash -c "\"${SCRIPT}\" --execute >\"${stdout_file}\" 2>\"${stderr_file}\"" || status=$?

  [ "${status}" -eq 7 ]
  grep -Fq "plain kcadm failure" "${stderr_file}"
  if grep -Fq "WARN Keycloak admin token returned HTTP 401" "${stderr_file}"; then
    return 1
  fi
  [ "$(grep -Fc -- "--user keycloak-admin" "${MOCK_KUBECTL_STATE_DIR}/login-commands.log")" -eq 1 ]
}
