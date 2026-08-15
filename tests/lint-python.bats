#!/usr/bin/env bats
#
# tests/app_contracts.py is ~6,000 lines that every bats suite imports, and it
# went unlinted until 2026-08-15. A dict literal with "lima" twice made the
# Keycloak image contract assert a registry host that exists nowhere in the
# repo. Ruff reports that as F601, so the last case here asserts F is selected
# rather than trusting the config file to keep it.

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/lint-python.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "lint-python reports a missing ruff binary with install hints" {
  hints="${BATS_TEST_TMPDIR}/install-hints.sh"

  cat >"${hints}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ruff: mise use -g ruff@latest\n'
EOF
  chmod +x "${hints}"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    RUFF_BIN=ruff \
    INSTALL_HINTS_SCRIPT="${hints}" \
    /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL ruff not found in PATH"* ]]
  [[ "${output}" == *"ruff: mise use -g ruff@latest"* ]]
}

@test "lint-python invokes ruff with the repo config" {
  ruff_stub="${TEST_BIN}/ruff"
  log_file="${BATS_TEST_TMPDIR}/ruff.log"

  cat >"${ruff_stub}" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  printf 'ruff 9.9.9\n'
  exit 0
fi
printf '%s\n' "\$*" >"${log_file}"
EOF
  chmod +x "${ruff_stub}"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    RUFF_BIN=ruff \
    /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ruff 9.9.9"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--config ${REPO_ROOT}/ruff.toml"* ]]
  [[ "${output}" == *"tests/app_contracts.py"* ]]
}

@test "ruff config selects the rule set that catches duplicate dict keys" {
  config="${REPO_ROOT}/ruff.toml"

  [ -f "${config}" ]

  # F601 lives in F. Asserting the selection rather than the finding keeps this
  # test independent of whether the tree currently happens to be clean.
  run grep -nE '^select = \[.*"F".*\]' "${config}"
  [ "${status}" -eq 0 ]

  # Pinned explicitly because n-dotfiles tracks ruff at "latest", so the default
  # rule set would otherwise change under the repo between releases.
  run grep -nE '^target-version = "py[0-9]+"' "${config}"
  [ "${status}" -eq 0 ]
}

@test "tracked Python is clean under the repo ruff configuration" {
  command -v ruff >/dev/null 2>&1 || skip "ruff is not installed"

  run "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   ruff"* ]]
}
