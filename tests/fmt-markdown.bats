#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/fmt-markdown.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "fmt-markdown skips cleanly when no markdownlint binary is installed" {
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

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN markdownlint not found in PATH; skipping tracked Markdown formatting"* ]]
}

@test "fmt-markdown applies fixes and re-runs tracked markdown lint" {
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
printf '%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/markdownlint"

  run env \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    GIT_BIN=git \
    MARKDOWNLINT_BIN=markdownlint \
    /bin/bash "${SCRIPT}" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"formatting 2 tracked Markdown file(s)"* ]]
  [[ "${output}" == *"OK   markdownlint"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"-c ${REPO_ROOT}/.markdownlint -f README.md docs/example.md"* ]]
  [[ "${output}" == *"-c ${REPO_ROOT}/.markdownlint README.md docs/example.md"* ]]
}
