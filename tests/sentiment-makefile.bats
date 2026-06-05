#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "sentiment make help exposes the update workflow" {
  run make -C "${REPO_ROOT}/apps/sentiment" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"update"* ]]
}

@test "sentiment make help does not resolve the compose backend helper" {
  compose_backend_stub="${BATS_TEST_TMPDIR}/compose-backend.sh"
  log_file="${BATS_TEST_TMPDIR}/compose-backend.log"

  cat >"${compose_backend_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'backend %s\n' "\$*" >>"${log_file}"
printf '/bin/false\n'
EOF
  chmod +x "${compose_backend_stub}"

  run make -C "${REPO_ROOT}/apps/sentiment" help COMPOSE_BACKEND_SCRIPT="${compose_backend_stub}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Run:"* ]]
  [[ "${output}" == *"Test:"* ]]
  [ ! -e "${log_file}" ]
}

@test "sentiment update documents that the default runtime has no Bun roots" {
  run make -n -C "${REPO_ROOT}/apps/sentiment" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"No dependency update required for the default Go sentiment runtime."* ]]
  [[ "${output}" != *"bun update"* ]]
}

@test "sentiment prereqs fails cleanly when the repo env file is missing" {
  missing_env="${BATS_TEST_TMPDIR}/missing.env"

  run env PLATFORM_ENV_FILE="${missing_env}" make -C "${REPO_ROOT}/apps/sentiment" prereqs

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Missing platform env file: ${missing_env}"* ]]
  [[ "${output}" != *"Unknown make goal '${missing_env}'"* ]]
}
