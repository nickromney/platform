#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/lint-markdown.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

# Changed 2026-08-17 from "skips cleanly" to "fails". The old contract meant
# `make lint` was green on any host without markdownlint while all 94 tracked
# Markdown files went unchecked, and the exit code could not tell you which had
# happened. Its three siblings -- lint-yaml, lint-python, lint-shellcheck -- all
# hard-fail on a missing tool; this is now the fourth.
@test "lint-markdown fails when no markdownlint binary is installed" {
  cat >"${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-C" && "${3:-}" == "ls-files" ]]; then
  printf '%s\0' README.md
  exit 0
fi
if [[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/git"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    GIT_BIN=git \
    /bin/bash "${SCRIPT}" --execute

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"FAIL markdownlint not found in PATH"* ]]
}

@test "lint-markdown uses the repo config with tracked markdown files" {
  log_file="${BATS_TEST_TMPDIR}/markdownlint.log"

  cat >"${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-C" && "${3:-}" == "ls-files" ]]; then
  printf '%s\0' README.md docs/example.md
  exit 0
fi
if [[ "${1:-}" == "-C" && "${3:-}" == "rev-parse" ]]; then
  exit 0
fi
exit 1
EOF
  chmod +x "${TEST_BIN}/git"

  cat >"${TEST_BIN}/markdownlint" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "--version" ]]; then
  printf '0.48.0\n'
  exit 0
fi
printf '%s\n' "\$*" >"${log_file}"
EOF
  chmod +x "${TEST_BIN}/markdownlint"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    GIT_BIN=git \
    MARKDOWNLINT_BIN=markdownlint \
    /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"0.48.0"* ]]
  [[ "${output}" == *"linting 2 tracked Markdown file(s)"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"-c ${REPO_ROOT}/.markdownlint"* ]]
  [[ "${output}" == *"README.md"* ]]
  [[ "${output}" == *"docs/example.md"* ]]
}
