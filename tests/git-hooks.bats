#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TEST_REPO="${BATS_TEST_TMPDIR}/hook-repo"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_REPO}/scripts/lib" "${TEST_BIN}"
  cp -R "${REPO_ROOT}/scripts/hooks" "${TEST_REPO}/scripts/hooks"
  cp "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${TEST_REPO}/scripts/lib/shell-cli.sh"
  cp "${REPO_ROOT}/.yamllint" "${TEST_REPO}/.yamllint"
}

write_repo_file() {
  local rel_path="$1"
  mkdir -p "$(dirname "${TEST_REPO}/${rel_path}")"
  cat >"${TEST_REPO}/${rel_path}"
}

@test "staged shell checker passes on a clean explicit shell file" {
  cat >"${TEST_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/shellcheck"

  local file=".run/git-hook-tests/good.sh"
  write_repo_file "${file}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ok\n'
EOF

  run env PATH="${TEST_BIN}:/usr/bin:/bin" "${TEST_REPO}/scripts/hooks/check-staged-shell.sh" --execute "${file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   shellcheck: 1 staged shell file(s)"* ]]
}

@test "staged shell checker fails on an explicit shell file with a shellcheck error" {
  cat >"${TEST_BIN}/shellcheck" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'SC2086: Double quote to prevent globbing and word splitting.'
exit 1
EOF
  chmod +x "${TEST_BIN}/shellcheck"

  local file=".run/git-hook-tests/bad.sh"
  write_repo_file "${file}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo $name
EOF

  run env PATH="${TEST_BIN}:/usr/bin:/bin" "${TEST_REPO}/scripts/hooks/check-staged-shell.sh" --execute "${file}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"SC2086"* ]]
  [[ "${output}" == *"FAIL ${file}: fix shellcheck findings before committing"* ]]
}

@test "staged kind tfvars checker fails on an explicit file with a duplicate attribute" {
  local file="kubernetes/kind/stages/999-hook-test.tfvars"
  write_repo_file "${file}" <<'EOF'
enable_sso = true
enable_sso = false
EOF

  run "${TEST_REPO}/scripts/hooks/check-staged-tfvars.sh" --execute "${file}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"duplicate attribute enable_sso"* ]]
  [[ "${output}" == *"FAIL ${file}: remove duplicate tfvars attributes so each key is assigned once"* ]]
}

@test "PLATFORM_SKIP_HOOKS=1 bypasses check scripts with a WARN" {
  run env PLATFORM_SKIP_HOOKS=1 "${TEST_REPO}/scripts/hooks/check-staged-shell.sh" --execute "scripts/bad.sh"

  [ "${status}" -eq 0 ]
  [ "${output}" = "WARN PLATFORM_SKIP_HOOKS=1; skipping check-staged-shell.sh" ]
}

@test "lefthook.yml wires staged checks and local CI scripts" {
  command -v yq >/dev/null 2>&1 || skip "yq not available"

  run yq eval '.pre-commit.parallel' "${REPO_ROOT}/lefthook.yml"
  [ "${status}" -eq 0 ]
  [ "${output}" = "true" ]

  run yq eval '.pre-commit.commands.shellcheck.run' "${REPO_ROOT}/lefthook.yml"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"scripts/hooks/check-staged-shell.sh --execute"* ]]
  [[ "${output}" == *"{staged_files}"* ]]

  run yq eval '.pre-commit.commands.yamllint.run' "${REPO_ROOT}/lefthook.yml"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"scripts/hooks/check-staged-yaml.sh --execute"* ]]
  [[ "${output}" == *"{staged_files}"* ]]

  run yq eval '.pre-commit.commands.kind-tfvars-duplicates.run' "${REPO_ROOT}/lefthook.yml"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"scripts/hooks/check-staged-tfvars.sh --execute"* ]]
  [[ "${output}" == *"{staged_files}"* ]]

  run yq eval '.pre-push.commands.local-ci.run' "${REPO_ROOT}/lefthook.yml"
  [ "${status}" -eq 0 ]
  [ "${output}" = "scripts/hooks/run-local-ci.sh --execute" ]
}

@test "make hooks invokes lefthook install" {
  local test_repo="${BATS_TEST_TMPDIR}/repo"
  local log_file="${BATS_TEST_TMPDIR}/lefthook.log"
  mkdir -p "${test_repo}/mk"
  cp "${REPO_ROOT}/Makefile" "${test_repo}/Makefile"
  cp "${REPO_ROOT}/mk/common.mk" "${test_repo}/mk/common.mk"

  cat >"${TEST_BIN}/lefthook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >"${log_file}"
EOF
  chmod +x "${TEST_BIN}/lefthook"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" make -C "${test_repo}" hooks

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Installed lefthook hooks from lefthook.yml"* ]]
  [[ "${output}" == *"LEFTHOOK=0 git <command>"* ]]

  run cat "${log_file}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "install" ]
}

@test "pre-push local CI wrapper respects PLATFORM_SKIP_HOOKS=1 without running make" {
  cat >"${TEST_BIN}/make" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'unexpected make %s\n' "$*" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/make"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" PLATFORM_SKIP_HOOKS=1 "${TEST_REPO}/scripts/hooks/run-local-ci.sh" --execute

  [ "${status}" -eq 0 ]
  [ "${output}" = "WARN PLATFORM_SKIP_HOOKS=1; skipping run-local-ci.sh" ]
}

@test "pre-push local CI audit probe previews without running make" {
  local log_file="${BATS_TEST_TMPDIR}/make.log"
  cat >"${TEST_BIN}/make" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${log_file}"
EOF
  chmod +x "${TEST_BIN}/make"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" "${TEST_REPO}/scripts/hooks/run-local-ci.sh" --dry-run --help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: run-local-ci.sh"* ]]
  [[ "${output}" == *"--dry-run"* ]]
  [[ "${output}" == *"--execute"* ]]
  [ ! -e "${log_file}" ]
}
