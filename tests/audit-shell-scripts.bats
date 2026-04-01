#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export AUDIT_SOURCE="${REPO_ROOT}/scripts/audit-shell-scripts.sh"
  export TEST_REPO="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${TEST_REPO}/scripts"
  cp "${AUDIT_SOURCE}" "${TEST_REPO}/scripts/audit-shell-scripts.sh"
  chmod +x "${TEST_REPO}/scripts/audit-shell-scripts.sh"
  git -C "${TEST_REPO}" init -q
  git -C "${TEST_REPO}" config user.email "test@example.com"
  git -C "${TEST_REPO}" config user.name "Test User"
  git -C "${TEST_REPO}" add scripts/audit-shell-scripts.sh
}

write_tracked_file() {
  local rel_path="$1"
  mkdir -p "$(dirname "${TEST_REPO}/${rel_path}")"
  cat > "${TEST_REPO}/${rel_path}"
  git -C "${TEST_REPO}" add "${rel_path}"
}

@test "shell audit ignores printed Python install hints" {
  write_tracked_file "scripts/install-hints.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' 'python3 -m pip install --user yamllint'
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh"

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

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"unexpected Python execution found"* ]]
  [[ "${output}" == *"scripts/bad.sh"* ]]
}

@test "shell audit allows approved shell wrappers that execute Python" {
  write_tracked_file "kubernetes/kind/scripts/ensure-kind-kubeconfig.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 "${SCRIPT_DIR}/rewrite-devcontainer-kubeconfig.py" config host tls
EOF

  run env PATH="/usr/bin:/bin" /bin/bash "${TEST_REPO}/scripts/audit-shell-scripts.sh"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   shell audit"* ]]
}
