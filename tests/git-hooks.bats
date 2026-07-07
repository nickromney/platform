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
  mkdir -p "${test_repo}/mk" "${test_repo}/scripts/lib" "${test_repo}/scripts/hooks"
  cp "${REPO_ROOT}/Makefile" "${test_repo}/Makefile"
  cp "${REPO_ROOT}/mk/common.mk" "${test_repo}/mk/common.mk"
  cp "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${test_repo}/scripts/lib/shell-cli.sh"
  cp "${REPO_ROOT}/scripts/hooks/install-lefthook-hooks.sh" "${test_repo}/scripts/hooks/install-lefthook-hooks.sh"
  cp "${REPO_ROOT}/scripts/hooks/lefthook-git-hook.sh" "${test_repo}/scripts/hooks/lefthook-git-hook.sh"

  git -C "${test_repo}" init >/dev/null
  git -C "${test_repo}" config user.name "Hook Test"
  git -C "${test_repo}" config user.email "hook@example.test"

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
  [ -x "${test_repo}/.git/hooks/pre-push" ]
  [ -x "${test_repo}/.git/hooks/pre-commit" ]
  run grep -F "lefthook failed while resolving Git worktree metadata" "${test_repo}/.git/hooks/pre-push"
  [ "${status}" -eq 0 ]
}

@test "make hooks refuses linked worktree installs without mutating shared core.bare" {
  local main_repo="${BATS_TEST_TMPDIR}/main-repo"
  local linked_repo="${BATS_TEST_TMPDIR}/linked-repo"
  local log_file="${BATS_TEST_TMPDIR}/lefthook.log"
  mkdir -p "${main_repo}/mk" "${main_repo}/scripts/lib" "${main_repo}/scripts/hooks"
  cp "${REPO_ROOT}/Makefile" "${main_repo}/Makefile"
  cp "${REPO_ROOT}/mk/common.mk" "${main_repo}/mk/common.mk"
  cp "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${main_repo}/scripts/lib/shell-cli.sh"
  cp "${REPO_ROOT}/scripts/hooks/install-lefthook-hooks.sh" "${main_repo}/scripts/hooks/install-lefthook-hooks.sh"
  cp "${REPO_ROOT}/scripts/hooks/lefthook-git-hook.sh" "${main_repo}/scripts/hooks/lefthook-git-hook.sh"

  git -C "${main_repo}" init >/dev/null
  git -C "${main_repo}" config user.name "Hook Test"
  git -C "${main_repo}" config user.email "hook@example.test"
  git -C "${main_repo}" config commit.gpgsign false
  touch "${main_repo}/README.md"
  git -C "${main_repo}" add .
  git -C "${main_repo}" commit -m initial >/dev/null
  git -C "${main_repo}" worktree add "${linked_repo}" >/dev/null

  cat >"${TEST_BIN}/lefthook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >"${log_file}"
EOF
  chmod +x "${TEST_BIN}/lefthook"

  local before_config
  before_config="$(git -C "${main_repo}" config --local --list | LC_ALL=C sort)"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" make -C "${linked_repo}" hooks

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Refusing to run lefthook install from a linked Git worktree"* ]]
  [[ "${output}" == *"Run make hooks from the main checkout instead"* ]]
  [ ! -e "${log_file}" ]
  [ "$(git -C "${main_repo}" config --local --get core.bare)" = "false" ]
  [ "$(git -C "${main_repo}" config --local --list | LC_ALL=C sort)" = "${before_config}" ]
}

@test "make hooks refuses non-bare checkout when shared core.bare is true" {
  local test_repo="${BATS_TEST_TMPDIR}/bare-flag-repo"
  local log_file="${BATS_TEST_TMPDIR}/lefthook.log"
  mkdir -p "${test_repo}/mk" "${test_repo}/scripts/lib" "${test_repo}/scripts/hooks"
  cp "${REPO_ROOT}/Makefile" "${test_repo}/Makefile"
  cp "${REPO_ROOT}/mk/common.mk" "${test_repo}/mk/common.mk"
  cp "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${test_repo}/scripts/lib/shell-cli.sh"
  cp "${REPO_ROOT}/scripts/hooks/install-lefthook-hooks.sh" "${test_repo}/scripts/hooks/install-lefthook-hooks.sh"
  cp "${REPO_ROOT}/scripts/hooks/lefthook-git-hook.sh" "${test_repo}/scripts/hooks/lefthook-git-hook.sh"

  git -C "${test_repo}" init >/dev/null
  git -C "${test_repo}" config user.name "Hook Test"
  git -C "${test_repo}" config user.email "hook@example.test"
  git -C "${test_repo}" config core.bare true

  cat >"${TEST_BIN}/lefthook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >"${log_file}"
EOF
  chmod +x "${TEST_BIN}/lefthook"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" make -C "${test_repo}" hooks

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Refusing to install hooks because core.bare=true"* ]]
  [[ "${output}" == *"git config --local core.bare false"* ]]
  [ ! -e "${log_file}" ]
  [ "$(git --git-dir="${test_repo}/.git" config --local --get core.bare)" = "true" ]
}

@test "installed pre-push hook skips lefthook worktree metadata crash without blocking linked push" {
  local remote_repo="${BATS_TEST_TMPDIR}/remote.git"
  local main_repo="${BATS_TEST_TMPDIR}/main-repo"
  local linked_repo="${BATS_TEST_TMPDIR}/linked-repo"
  local log_file="${BATS_TEST_TMPDIR}/lefthook.log"
  git init --bare "${remote_repo}" >/dev/null
  mkdir -p "${main_repo}/mk" "${main_repo}/scripts/lib" "${main_repo}/scripts/hooks"
  cp "${REPO_ROOT}/Makefile" "${main_repo}/Makefile"
  cp "${REPO_ROOT}/mk/common.mk" "${main_repo}/mk/common.mk"
  cp "${REPO_ROOT}/scripts/lib/shell-cli.sh" "${main_repo}/scripts/lib/shell-cli.sh"
  cp "${REPO_ROOT}/scripts/hooks/install-lefthook-hooks.sh" "${main_repo}/scripts/hooks/install-lefthook-hooks.sh"
  cp "${REPO_ROOT}/scripts/hooks/lefthook-git-hook.sh" "${main_repo}/scripts/hooks/lefthook-git-hook.sh"

  git -C "${main_repo}" init >/dev/null
  git -C "${main_repo}" config user.name "Hook Test"
  git -C "${main_repo}" config user.email "hook@example.test"
  git -C "${main_repo}" config commit.gpgsign false
  git -C "${main_repo}" remote add origin "${remote_repo}"
  touch "${main_repo}/README.md"
  git -C "${main_repo}" add README.md
  git -C "${main_repo}" commit -m initial >/dev/null
  git -C "${main_repo}" push -u origin HEAD >/dev/null

  cat >"${TEST_BIN}/lefthook" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$*" >>"${log_file}"
if [ "\${1:-}" = "run" ]; then
  printf '%s\n' "fatal: this operation must be run in a work tree" >&2
  exit 128
fi
EOF
  chmod +x "${TEST_BIN}/lefthook"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" make -C "${main_repo}" hooks
  [ "${status}" -eq 0 ]

  git -C "${main_repo}" worktree add "${linked_repo}" >/dev/null
  git -C "${linked_repo}" config user.name "Hook Test"
  git -C "${linked_repo}" config user.email "hook@example.test"
  git -C "${linked_repo}" config commit.gpgsign false
  printf '%s\n' "linked" >"${linked_repo}/linked.txt"
  git -C "${linked_repo}" add linked.txt
  git -C "${linked_repo}" commit -m linked >/dev/null

  local before_config
  before_config="$(git -C "${main_repo}" config --local --list | LC_ALL=C sort)"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" git -C "${linked_repo}" push origin HEAD

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN lefthook pre-push: lefthook failed while resolving Git worktree metadata"* ]]
  [[ "${output}" == *"skipping hook so Git worktree operations are not blocked"* ]]
  [[ "${output}" == *"HEAD ->"* ]]
  [ "$(git -C "${main_repo}" config --local --get core.bare)" = "false" ]
  [ "$(git -C "${main_repo}" config --local --list | LC_ALL=C sort)" = "${before_config}" ]
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
