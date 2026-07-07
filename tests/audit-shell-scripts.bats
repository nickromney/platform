#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export AUDIT_SOURCE="${REPO_ROOT}/scripts/audit-shell-scripts.sh"
  export SHELL_CLI_SOURCE="${REPO_ROOT}/scripts/lib/shell-cli.sh"
  export SHELL_CLI_POSIX_SOURCE="${REPO_ROOT}/scripts/lib/shell-cli-posix.sh"
  export TEST_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${TEST_REPO}/scripts/lib"
  cp "${AUDIT_SOURCE}" "${TEST_REPO}/scripts/audit-shell-scripts.sh"
  cp "${SHELL_CLI_SOURCE}" "${TEST_REPO}/scripts/lib/shell-cli.sh"
  cp "${SHELL_CLI_POSIX_SOURCE}" "${TEST_REPO}/scripts/lib/shell-cli-posix.sh"
  chmod +x "${TEST_REPO}/scripts/audit-shell-scripts.sh"
  git -C "${TEST_REPO}" init -q
  git -C "${TEST_REPO}" config user.email "test@example.com"
  git -C "${TEST_REPO}" config user.name "Test User"
  git -C "${TEST_REPO}" add scripts/audit-shell-scripts.sh scripts/lib/shell-cli.sh scripts/lib/shell-cli-posix.sh
}

write_tracked_file() {
  local rel_path="$1"
  mkdir -p "$(dirname "${TEST_REPO}/${rel_path}")"
  cat > "${TEST_REPO}/${rel_path}"
  git -C "${TEST_REPO}" add "${rel_path}"
}

write_tracked_executable_file() {
  local rel_path="$1"
  write_tracked_file "${rel_path}"
  chmod +x "${TEST_REPO}/${rel_path}"
}

@test "shell audit flags executable scripts missing the standard entrypoint interface" {
  write_tracked_executable_file "scripts/missing-interface.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "hello"
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executable shell entrypoints must support --help, --dry-run, and --execute"* ]]
  [[ "${output}" == *"scripts/missing-interface.sh"* ]]
}

@test "shell audit accepts executable scripts that implement the standard interface" {
  write_tracked_executable_file "scripts/good.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  cat <<USAGE
Usage: good.sh [--dry-run] [--execute]

$(shell_cli_standard_options)
USAGE
}

shell_cli_handle_standard_no_args usage "would do the safe thing" "$@"

echo "ok"
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   shell audit"* ]]

  run env PATH="/usr/bin:/bin" "${TEST_REPO}/scripts/good.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: good.sh"* ]]
  [[ "${output}" == *"INFO dry-run: would do the safe thing"* ]]
}

@test "shell audit validates interface output without grep or awk subprocesses" {
  write_tracked_executable_file "scripts/good.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  cat <<USAGE
Usage: good.sh [--dry-run] [--execute]

$(shell_cli_standard_options)
USAGE
}

shell_cli_handle_standard_no_args usage "would do the safe thing" "$@"
EOF

  local probe_bin="${BATS_TEST_TMPDIR}/probe-bin"
  mkdir -p "${probe_bin}"
  export SHELL_AUDIT_HELPER_LOG="${BATS_TEST_TMPDIR}/helper-calls.log"

  cat >"${probe_bin}/grep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'grep\t%s\n' "$*" >>"${SHELL_AUDIT_HELPER_LOG}"
exec /usr/bin/grep "$@"
EOF
  chmod +x "${probe_bin}/grep"

  cat >"${probe_bin}/awk" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'awk\t%s\n' "$*" >>"${SHELL_AUDIT_HELPER_LOG}"
exec /usr/bin/awk "$@"
EOF
  chmod +x "${probe_bin}/awk"

  run env PATH="${probe_bin}:/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 0 ]
  ! grep -Fq 'Usage:' "${SHELL_AUDIT_HELPER_LOG}"
  ! grep -Fq -- '--dry-run' "${SHELL_AUDIT_HELPER_LOG}"
  ! grep -Fq 'expected_name=good.sh' "${SHELL_AUDIT_HELPER_LOG}"
}

@test "shell audit reuses interface capture files without cat subprocesses" {
  write_tracked_executable_file "scripts/good.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  printf '%s\n' \
    'Usage: good.sh [--dry-run] [--execute]' \
    '' \
    'Options:' \
    '  --dry-run  Show a summary and exit before side effects' \
    '  --execute  Execute the script body; without it the script prints help and/or preview output'
}

shell_cli_handle_standard_no_args usage "would do the safe thing" "$@"
EOF

  local probe_bin="${BATS_TEST_TMPDIR}/probe-bin"
  mkdir -p "${probe_bin}"
  export SHELL_AUDIT_CAPTURE_HELPER_LOG="${BATS_TEST_TMPDIR}/capture-helper-calls.log"

  cat >"${probe_bin}/mktemp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'mktemp\t%s\n' "$*" >>"${SHELL_AUDIT_CAPTURE_HELPER_LOG:-/dev/null}"
exec /usr/bin/mktemp "$@"
EOF
  chmod +x "${probe_bin}/mktemp"

  cat >"${probe_bin}/cat" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'cat\t%s\n' "$*" >>"${SHELL_AUDIT_CAPTURE_HELPER_LOG:-/dev/null}"
exec /bin/cat "$@"
EOF
  chmod +x "${probe_bin}/cat"

  cat >"${probe_bin}/rm" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'rm\t%s\n' "$*" >>"${SHELL_AUDIT_CAPTURE_HELPER_LOG:-/dev/null}"
exec /bin/rm "$@"
EOF
  chmod +x "${probe_bin}/rm"

  run env PATH="${probe_bin}:/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 0 ]
  mktemp_count="$(grep -c '^mktemp' "${SHELL_AUDIT_CAPTURE_HELPER_LOG}" || true)"
  cat_count="$(grep -c '^cat' "${SHELL_AUDIT_CAPTURE_HELPER_LOG}" || true)"
  rm_count="$(grep -c '^rm' "${SHELL_AUDIT_CAPTURE_HELPER_LOG}" || true)"

  [ "${mktemp_count}" -le 2 ]
  [ "${cat_count}" -eq 0 ]
  [ "${rm_count}" -le 1 ]
}

@test "shell audit rejects shared-helper entrypoints with mismatched descriptor metadata" {
  write_tracked_executable_file "scripts/described.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "--shell-entrypoint-descriptor" ]]; then
  printf '%s\n' '{"schema_version":"shell-entrypoint/v1","name":"old-name.sh","path":"scripts/described.sh","supports":["--help","--dry-run","--execute"],"default_mode":"dry-run"}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  cat <<USAGE
Usage: described.sh [--dry-run] [--execute]

$(shell_cli_standard_options)
USAGE
}

shell_cli_handle_standard_no_args usage "would do the safe thing" "$@"
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executable shell entrypoints must expose valid descriptor metadata"* ]]
  [[ "${output}" == *"scripts/described.sh"* ]]
  [[ "${output}" == *"descriptor name old-name.sh did not match described.sh"* ]]
}

@test "shell audit rejects usage names that do not match the executable basename" {
  write_tracked_executable_file "scripts/renamed.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  cat <<USAGE
Usage: old-name.sh [--dry-run] [--execute]

$(shell_cli_standard_options)
USAGE
}

shell_cli_handle_standard_no_args usage "would do the safe thing" "$@"
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"executable shell entrypoints must support --help, --dry-run, and --execute"* ]]
  [[ "${output}" == *"scripts/renamed.sh"* ]]
  [[ "${output}" == *"Usage output did not name renamed.sh"* ]]
}

@test "shell audit ignores printed install hints" {
  write_tracked_file "scripts/install-hints.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'uv tool install yamllint'
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   shell audit"* ]]
}

@test "shell audit flags unapproved Python execution" {
  write_tracked_file "scripts/bad.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
print("bad")
PY
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"unexpected Python execution found"* ]]
  [[ "${output}" == *"scripts/bad.sh"* ]]
}

@test "shell audit can scope validation to selected paths" {
  write_tracked_executable_file "scripts/good.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

usage() {
  cat <<USAGE
Usage: good.sh [--dry-run] [--execute]

$(shell_cli_standard_options)
USAGE
}

shell_cli_handle_standard_no_args usage "would do the safe thing" "$@"
EOF

  write_tracked_executable_file "apps/bad.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "hello"
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" \
    --execute \
    --path scripts

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   shell audit"* ]]
}

@test "kind node kubectl wrapper stays runnable when mounted alone as kubectl" {
  local mounted_dir="${BATS_TEST_TMPDIR}/usr/local/bin"
  local real_kubectl="${BATS_TEST_TMPDIR}/real-kubectl"
  mkdir -p "${mounted_dir}"
  cp "${REPO_ROOT}/terraform/kubernetes/scripts/kind-node-kubectl-wrapper.sh" "${mounted_dir}/kubectl"
  chmod +x "${mounted_dir}/kubectl"

  cat >"${real_kubectl}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'ARGS:%s\n' "$*"
cat >/dev/null
EOF
  chmod +x "${real_kubectl}"

  run env PATH="/usr/bin:/bin" KIND_REAL_KUBECTL="${real_kubectl}" \
    "${mounted_dir}/kubectl" --execute --kubeconfig=/etc/kubernetes/admin.conf apply -f - <<<"apiVersion: v1"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ARGS:--kubeconfig=/etc/kubernetes/admin.conf apply -f -"* ]]
}

@test "direct shell_cli_handle_standard_flag callers initialize standard flag state" {
  local offenders=()
  local file=""

  while IFS= read -r file; do
    if ! rg -q 'shell_cli_init_standard_flags|shell_cli_parse_standard_only|shell_cli_handle_standard_no_args' "${file}"; then
      offenders+=("${file}")
    fi
  done < <(cd "${REPO_ROOT}" && rg -l 'shell_cli_handle_standard_flag' -g '*.sh')

  [ "${#offenders[@]}" -eq 0 ]
}

@test "hubble observe supports promote-to-module dry-run without unbound CLI state" {
  run "${REPO_ROOT}/terraform/kubernetes/scripts/hubble-observe-cilium-policies.sh" \
    --promote-to-module \
    --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would observe Hubble flows and generate candidate Cilium policies"* ]]
}

@test "shell audit rejects executable library scripts in scripts/lib" {
  write_tracked_executable_file "scripts/lib/bad-lib.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "hello"
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh" --execute

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"FAIL shell audit: library scripts under scripts/lib should not be executable entrypoints"* ]]
  [[ "${output}" == *"scripts/lib/bad-lib.sh"* ]]
}

@test "compose-backend supports dry-run-by-default interface output" {
  run "${REPO_ROOT}/scripts/compose-backend.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: compose-backend.sh [--print] [--dry-run] [--execute]"* ]]
  [[ "${output}" == *"--dry-run  Show a summary and exit before side effects"* ]]
  [[ "${output}" == *"--execute  Execute the script body; without it the script prints help and/or preview output"* ]]
  [[ "${output}" == *"INFO dry-run: would print the first supported compose backend command"* ]]
}

@test "sync-gitea-repo supports standard no-op interface" {
  run "${REPO_ROOT}/terraform/kubernetes/scripts/sync-gitea-repo.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: sync-gitea-repo.sh [--dry-run] [--execute]"* ]]
  [[ "${output}" == *"--dry-run  Show a summary and exit before side effects"* ]]
  [[ "${output}" == *"--execute  Execute the script body; without it the script prints help and/or preview output"* ]]
  [[ "${output}" == *"INFO dry-run: would sync SOURCE_DIR into Gitea if needed"* ]]
}

@test "promote gitea admin supports standard no-op interface" {
  run /bin/bash "${REPO_ROOT}/terraform/kubernetes/scripts/promote-gitea-admin.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: promote-gitea-admin.sh [--dry-run] [--execute]"* ]]
  [[ "${output}" == *"--dry-run  Show a summary and exit before side effects"* ]]
  [[ "${output}" == *"--execute  Execute the script body; without it the script prints help and/or preview output"* ]]
  [[ "${output}" == *"INFO dry-run: would promote the configured user to a Gitea administrator if needed"* ]]
}

@test "fetch gitea runner token supports standard no-op interface" {
  run /bin/sh -c "printf '{}' | /bin/bash \"${REPO_ROOT}/terraform/kubernetes/scripts/fetch-gitea-runner-token.sh\""

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: fetch-gitea-runner-token.sh [--dry-run] [--execute]"* ]]
  [[ "${output}" == *"--dry-run  Show a summary and exit before side effects"* ]]
  [[ "${output}" == *"--execute  Execute the script body; without it the script prints help and/or preview output"* ]]
  [[ "${output}" == *"INFO dry-run: would fetch or read-through-cache a Gitea Actions runner token"* ]]
}

@test "test-idempotence harness supports standard no-op interface" {
  run "${REPO_ROOT}/kubernetes/scripts/test-idempotence.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: test-idempotence.sh [options]"* ]]
  [[ "${output}" == *"--dry-run  Show a summary and exit before side effects"* ]]
  [[ "${output}" == *"--execute  Execute the script body; without it the script prints help and/or preview output"* ]]
  [[ "${output}" == *"INFO dry-run: would run apply/apply/plan idempotence checks for a Kubernetes stack"* ]]
}

@test "hubble observe without --execute prints help plus the dry-run preview" {
  run "${REPO_ROOT}/terraform/kubernetes/scripts/hubble-observe-cilium-policies.sh" \
    --promote-to-module

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: hubble-observe-cilium-policies.sh [options]"* ]]
  [[ "${output}" == *"INFO dry-run: would observe Hubble flows and generate candidate Cilium policies"* ]]
}

@test "resolve tfvar accepts an explicit empty default with --execute" {
  run "${REPO_ROOT}/kubernetes/scripts/resolve-tfvar-value.sh" \
    --execute \
    --key platform_admin_base_domain \
    --default ""

  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}
