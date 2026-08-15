#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/reset-local-state.sh"
}

make_fake_workspace() {
  export TEST_WORKSPACE="${BATS_TEST_TMPDIR}/workspace"
  mkdir -p "${TEST_WORKSPACE}"
  (
    cd "${TEST_WORKSPACE}"
    git init -q
    # See the note in release-script.bats: the fixture inherits global config,
    # so a host with commit signing on routes the seed commit to that signer.
    git config user.email "test@example.com"
    git config user.name "Test User"
    git config commit.gpgsign false
    mkdir -p .run/demo apps/example/node_modules/pkg infra/.terraform providers/dist
    printf 'cache\n' > .run/demo/file.txt
    printf 'deps\n' > apps/example/node_modules/pkg/index.js
    printf 'tf\n' > infra/.terraform/state
    mkdir -p dist
    printf 'tracked\n' > dist/keep.txt
    git add dist/keep.txt
    git commit -qm "seed"
  )
}

make_fake_home() {
  export TEST_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p \
    "${TEST_HOME}/.npm" \
    "${TEST_HOME}/.bun/install/cache" \
    "${TEST_HOME}/.cache/uv" \
    "${TEST_HOME}/.kube" \
    "${TEST_HOME}/Library/Caches/ms-playwright" \
    "${TEST_HOME}/Library/Caches/pip"
  printf 'npm\n' > "${TEST_HOME}/.npm/cache.txt"
  printf 'bun\n' > "${TEST_HOME}/.bun/install/cache/cache.txt"
  printf 'uv\n' > "${TEST_HOME}/.cache/uv/cache.txt"
  printf 'kind\n' > "${TEST_HOME}/.kube/kind-kind-local.yaml"
  printf 'playwright\n' > "${TEST_HOME}/Library/Caches/ms-playwright/cache.txt"
  printf 'pip\n' > "${TEST_HOME}/Library/Caches/pip/cache.txt"
}

@test "reset-local-state dry-run reports repo-owned and host cache targets without deleting them" {
  make_fake_workspace
  make_fake_home

  run env \
    HOME="${TEST_HOME}" \
    RESET_LOCAL_STATE_WORKSPACE_ROOT="${TEST_WORKSPACE}" \
    RESET_LOCAL_STATE_GIT_ROOT="${TEST_WORKSPACE}" \
    "${SCRIPT}" \
    --dry-run \
    --include-host-caches \
    --include-kubeconfigs

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${TEST_WORKSPACE}/.run"* ]]
  [[ "${output}" == *"${TEST_WORKSPACE}/apps/example/node_modules"* ]]
  [[ "${output}" == *"${TEST_HOME}/.npm"* ]]
  [[ "${output}" == *"${TEST_HOME}/.bun/install/cache"* ]]
  [[ "${output}" == *"${TEST_HOME}/.cache/uv"* ]]
  [[ "${output}" == *"${TEST_HOME}/Library/Caches/ms-playwright"* ]]
  [[ "${output}" == *"${TEST_HOME}/Library/Caches/pip"* ]]
  [[ "${output}" == *"${TEST_HOME}/.kube/kind-kind-local.yaml"* ]]
  [[ "${output}" == *"Skipping tracked path"* ]]

  [ -d "${TEST_WORKSPACE}/.run" ]
  [ -d "${TEST_WORKSPACE}/apps/example/node_modules" ]
  [ -d "${TEST_HOME}/.npm" ]
  [ -d "${TEST_HOME}/Library/Caches/ms-playwright" ]
  [ -f "${TEST_WORKSPACE}/dist/keep.txt" ]
}

@test "reset-local-state execute removes untracked repo state and host caches but keeps tracked paths" {
  make_fake_workspace
  make_fake_home

  run env \
    HOME="${TEST_HOME}" \
    RESET_LOCAL_STATE_WORKSPACE_ROOT="${TEST_WORKSPACE}" \
    RESET_LOCAL_STATE_GIT_ROOT="${TEST_WORKSPACE}" \
    "${SCRIPT}" \
    --execute \
    --include-host-caches \
    --include-kubeconfigs

  [ "${status}" -eq 0 ]
  [ ! -e "${TEST_WORKSPACE}/.run" ]
  [ ! -e "${TEST_WORKSPACE}/apps/example/node_modules" ]
  [ ! -e "${TEST_WORKSPACE}/infra/.terraform" ]
  [ ! -e "${TEST_HOME}/.npm" ]
  [ ! -e "${TEST_HOME}/.bun/install/cache" ]
  [ ! -e "${TEST_HOME}/.cache/uv" ]
  [ ! -e "${TEST_HOME}/Library/Caches/ms-playwright" ]
  [ ! -e "${TEST_HOME}/Library/Caches/pip" ]
  [ ! -e "${TEST_HOME}/.kube/kind-kind-local.yaml" ]
  [ -f "${TEST_WORKSPACE}/dist/keep.txt" ]
}

@test "reset-local-state collects known cache locations even when the tool reports one" {
  make_fake_workspace
  make_fake_home

  # This suite passed on Arch and failed on ubuntu-latest, because the tool
  # lookup and the well-known locations were alternatives rather than additive.
  # `pip cache dir` returns ~/.cache/pip, so on a host with pip the macOS-style
  # ~/Library/Caches/pip was never looked at; on a host without pip it was. The
  # stub pins that condition so the result no longer depends on the host.
  stub_bin="${BATS_TEST_TMPDIR}/stub-bin"
  mkdir -p "${stub_bin}"
  cat >"${stub_bin}/pip" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "cache" && "${2:-}" == "dir" ]] && { printf '%s\n' "${HOME}/.cache/pip"; exit 0; }
exit 1
EOF
  chmod +x "${stub_bin}/pip"
  mkdir -p "${TEST_HOME}/.cache/pip"
  printf 'pip-xdg\n' >"${TEST_HOME}/.cache/pip/cache.txt"

  run env \
    PATH="${stub_bin}:${PATH}" \
    HOME="${TEST_HOME}" \
    RESET_LOCAL_STATE_WORKSPACE_ROOT="${TEST_WORKSPACE}" \
    RESET_LOCAL_STATE_GIT_ROOT="${TEST_WORKSPACE}" \
    "${SCRIPT}" \
    --dry-run \
    --include-host-caches

  [ "${status}" -eq 0 ]
  # Both, not either: the path pip reported and the macOS location it does not.
  [[ "${output}" == *"${TEST_HOME}/.cache/pip"* ]]
  [[ "${output}" == *"${TEST_HOME}/Library/Caches/pip"* ]]
}

@test "reset-local-state refuses a host cache resolved outside HOME" {
  make_fake_workspace
  make_fake_home

  # Not hypothetical. `uv cache dir` ignores a reassigned HOME and returns the
  # invoking user's real cache, so this suite deleted the operator's actual
  # ~/.cache/uv rather than its fixture. The override stands in for any tool
  # that reports a path outside the HOME it was handed.
  outside="${BATS_TEST_TMPDIR}/outside-cache"
  mkdir -p "${outside}"
  printf 'keep\n' >"${outside}/file.txt"

  run env \
    HOME="${TEST_HOME}" \
    RESET_LOCAL_STATE_WORKSPACE_ROOT="${TEST_WORKSPACE}" \
    RESET_LOCAL_STATE_GIT_ROOT="${TEST_WORKSPACE}" \
    RESET_LOCAL_STATE_UV_CACHE_DIR="${outside}" \
    "${SCRIPT}" \
    --execute \
    --include-host-caches

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ignoring host cache outside HOME"* ]]
  [ -f "${outside}/file.txt" ]
}

@test "reset-local-state dry-run includes docker cleanup estimate when requested" {
  make_fake_workspace
  make_fake_home

  fake_bin="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${fake_bin}"
  estimate_stub="${BATS_TEST_TMPDIR}/docker-prune-estimate.sh"

  cat >"${fake_bin}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "info" ]]; then
  exit 0
fi
printf 'unexpected docker args: %s\n' "$*" >&2
exit 1
EOF
  chmod +x "${fake_bin}/docker"

  cat >"${estimate_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'Docker prune estimate\n'
printf '  combined sequence        : 1.23 GB plus any unused networks\n'
EOF
  chmod +x "${estimate_stub}"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${fake_bin}:${PATH}" \
    RESET_LOCAL_STATE_WORKSPACE_ROOT="${TEST_WORKSPACE}" \
    RESET_LOCAL_STATE_GIT_ROOT="${TEST_WORKSPACE}" \
    DOCKER_PRUNE_ESTIMATE_SCRIPT="${estimate_stub}" \
    "${SCRIPT}" \
    --dry-run \
    --include-docker

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Docker prune estimate"* ]]
  [[ "${output}" == *"platform-local-image-cache"* ]]
  [[ "${output}" == *"docker system prune -af"* ]]
}
