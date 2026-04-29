#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TEST_HOME="${BATS_TEST_TMPDIR}/home"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_HOME}" "${TEST_BIN}"
}

stub_git_without_network() {
  cat >"${TEST_BIN}/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'git %s\n' "$*" >>"${HOME}/git.log"
case "${1:-}" in
  config)
    exit 0
    ;;
  clone|fetch|checkout|rev-parse)
    printf 'unexpected git network operation: %s\n' "$*" >&2
    exit 99
    ;;
esac
exit 0
EOF
  chmod +x "${TEST_BIN}/git"
}

@test "devcontainer install-toolchain only bakes Playwright runtime deps" {
  run grep -n 'playwright install-deps chromium' "${REPO_ROOT}/.devcontainer/install-toolchain.sh"

  [ "${status}" -eq 0 ]

  run grep -n 'playwright install --with-deps chromium' "${REPO_ROOT}/.devcontainer/install-toolchain.sh"

  [ "${status}" -eq 1 ]
}

@test "devcontainer disables pnpm and omits slicer from the pinned toolchain surface" {
  run grep -n '"pnpmVersion"[[:space:]]*:[[:space:]]*"none"' "${REPO_ROOT}/.devcontainer/devcontainer.json"

  [ "${status}" -eq 0 ]

  run grep -n 'SLICER_IMAGE_REF\|arkade oci install .*slicer' \
    "${REPO_ROOT}/.devcontainer/toolchain-versions.sh" \
    "${REPO_ROOT}/.devcontainer/install-toolchain.sh" \
    "${REPO_ROOT}/.devcontainer/check-devcontainer-version.sh" \
    "${REPO_ROOT}/.devcontainer/README.md"

  [ "${status}" -eq 1 ]
}

@test "devcontainer post-create can use a preseeded vim-sensible source without git clone" {
  local source_dir="${BATS_TEST_TMPDIR}/vim-sensible"
  stub_git_without_network
  mkdir -p "${source_dir}/plugin"
  printf '" sensible\n' >"${source_dir}/plugin/sensible.vim"

  run env \
    HOME="${TEST_HOME}" \
    PATH="${TEST_BIN}:/usr/bin:/bin" \
    VIM_SENSIBLE_SOURCE_DIR="${source_dir}" \
    bash "${REPO_ROOT}/.devcontainer/post-create.sh"

  [ "${status}" -eq 0 ]
  [ -L "${TEST_HOME}/.vim/pack/tpope/start/sensible" ]
  [ -L "${TEST_HOME}/.local/share/nvim/site/pack/tpope/start/sensible" ]
  [ "$(readlink "${TEST_HOME}/.vim/pack/tpope/start/sensible")" = "${source_dir}" ]
  [ "$(readlink "${TEST_HOME}/.local/share/nvim/site/pack/tpope/start/sensible")" = "${source_dir}" ]

  run cat "${TEST_HOME}/git.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"git config --global --add safe.directory ${REPO_ROOT}"* ]]
  [[ "${output}" != *"git clone"* ]]
  [[ "${output}" != *"git fetch"* ]]
}

@test "devcontainer normalize-node-toolchain removes Corepack pnpm shims" {
  local fake_nvm_dir="${BATS_TEST_TMPDIR}/nvm"
  mkdir -p "${fake_nvm_dir}/current/bin" "${fake_nvm_dir}/versions/node/v24.15.0/bin"
  printf 'nvm() { return 0; }\n' >"${fake_nvm_dir}/nvm.sh"
  printf '#!/usr/bin/env bash\n' >"${fake_nvm_dir}/current/bin/pnpm"
  printf '#!/usr/bin/env bash\n' >"${fake_nvm_dir}/current/bin/pnpx"
  printf '#!/usr/bin/env bash\n' >"${fake_nvm_dir}/versions/node/v24.15.0/bin/pnpm"
  printf '#!/usr/bin/env bash\n' >"${fake_nvm_dir}/versions/node/v24.15.0/bin/pnpx"
  chmod +x \
    "${fake_nvm_dir}/nvm.sh" \
    "${fake_nvm_dir}/current/bin/pnpm" \
    "${fake_nvm_dir}/current/bin/pnpx" \
    "${fake_nvm_dir}/versions/node/v24.15.0/bin/pnpm" \
    "${fake_nvm_dir}/versions/node/v24.15.0/bin/pnpx"

  run env NVM_DIR="${fake_nvm_dir}" bash "${REPO_ROOT}/.devcontainer/normalize-node-toolchain.sh" --execute

  [ "${status}" -eq 0 ]
  [ ! -e "${fake_nvm_dir}/current/bin/pnpm" ]
  [ ! -e "${fake_nvm_dir}/current/bin/pnpx" ]
  [ ! -e "${fake_nvm_dir}/versions/node/v24.15.0/bin/pnpm" ]
  [ ! -e "${fake_nvm_dir}/versions/node/v24.15.0/bin/pnpx" ]
}
