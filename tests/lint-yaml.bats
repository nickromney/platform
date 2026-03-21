#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/lint-yaml.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "lint-yaml reports a missing yamllint binary with install hints" {
  hints="${BATS_TEST_TMPDIR}/install-hints.sh"

  cat >"${hints}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'yamllint: brew install yamllint\n'
EOF
  chmod +x "${hints}"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    YAMLLINT_BIN=yamllint \
    INSTALL_HINTS_SCRIPT="${hints}" \
    /bin/bash "${SCRIPT}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL yamllint not found in PATH"* ]]
  [[ "${output}" == *"yamllint: brew install yamllint"* ]]
}

@test "lint-yaml invokes yamllint with the repo config" {
  yamllint_stub="${TEST_BIN}/yamllint"
  log_file="${BATS_TEST_TMPDIR}/yamllint.log"

  cat >"${yamllint_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  printf 'yamllint 9.9.9\n'
  exit 0
fi
printf '%s\n' "\$*" >"${log_file}"
EOF
  chmod +x "${yamllint_stub}"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    YAMLLINT_BIN=yamllint \
    /bin/bash "${SCRIPT}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"yamllint 9.9.9"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"-c ${REPO_ROOT}/.yamllint"* ]]
  [[ "${output}" == *".github/workflows/release.yml"* ]]
}
