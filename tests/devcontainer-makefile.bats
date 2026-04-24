#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export TEST_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${TEST_BIN}" "${TEST_HOME}"
  export PATH="${TEST_BIN}:${PATH}"
}

stub_docker() {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "info" ]]; then
  exit 0
fi
if [[ "${1:-}" == "ps" && "${2:-}" == "-aq" ]]; then
  printf '%s' "${DOCKER_PS_AQ_OUTPUT:-}"
  exit 0
fi
printf 'docker %s\n' "$*" >>"${TEST_HOME}/docker.log"
EOF
  chmod +x "${TEST_BIN}/docker"
}

stub_docker_timeout_on_buildx_load() {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "info" ]]; then
  exit 0
fi
if [[ "${1:-}" == "ps" && "${2:-}" == "-aq" ]]; then
  printf '%s' "${DOCKER_PS_AQ_OUTPUT:-}"
  exit 0
fi
printf 'docker %s\n' "$*" >>"${TEST_HOME}/docker.log"
if [[ "${1:-}" == "buildx" && "${2:-}" == "build" && "${3:-}" == "--load" ]]; then
  sleep 10
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"
}

stub_docker_timeout_on_buildx_and_diagnostics() {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "info" ]]; then
  exit 0
fi
if [[ "${1:-}" == "ps" && "${2:-}" == "-aq" ]]; then
  printf '%s' "${DOCKER_PS_AQ_OUTPUT:-}"
  exit 0
fi
printf 'docker %s\n' "$*" >>"${TEST_HOME}/docker.log"
if [[ "${1:-}" == "buildx" && "${2:-}" == "build" && "${3:-}" == "--load" ]]; then
  sleep 10
  exit 0
fi
if [[ "${1:-}" == "system" && "${2:-}" == "df" ]]; then
  sleep 10
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"
}

stub_docker_for_toolchain_surface() {
  cat >"${TEST_BIN}/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'docker %s\n' "$*" >>"${TEST_HOME}/docker.log"
if [[ "${1:-}" == "run" ]]; then
  [[ "$*" == *"VERSION=24.15.0"* ]]
  [[ "$*" == *"PNPMVERSION=none"* ]]
  [[ "$*" == *"NVMVERSION=0.40.4"* ]]
  [[ "$*" == *"/tmp/platform-devcontainer-node-feature:ro"* ]]
  [[ "$*" == *"/tmp/platform-devcontainer-normalize-node-toolchain.sh:ro"* ]]
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/docker"
}

stub_devcontainer() {
  cat >"${TEST_BIN}/devcontainer" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'devcontainer %s\n' "$*" >>"${TEST_HOME}/devcontainer.log"
EOF
  chmod +x "${TEST_BIN}/devcontainer"
}

stub_devcontainer_read_configuration() {
  local feature_cache="${BATS_TEST_TMPDIR}/node-feature-cache"
  mkdir -p "${feature_cache}"
  printf '#!/usr/bin/env bash\n' >"${feature_cache}/install.sh"
  chmod +x "${feature_cache}/install.sh"

  cat >"${TEST_BIN}/devcontainer" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'devcontainer %s\n' "\$*" >>"${TEST_HOME}/devcontainer.log"
if [[ "\${1:-}" == "read-configuration" ]]; then
  printf '%s\n' '{"type":"text","level":1,"timestamp":1,"text":"resolving features"}'
  printf '%s\n' '{"configuration":{"name":"platform"},"featuresConfiguration":{"featureSets":[{"features":[{"id":"node","cachePath":"'"${feature_cache}"'","value":{"version":"24.15.0","pnpmVersion":"none","nvmVersion":"0.40.4"}}]}]}}'
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/devcontainer"
}

stub_code() {
  cat >"${TEST_BIN}/code" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--list-extensions" ]]; then
  printf '%s\n' 'ms-vscode-remote.remote-containers'
  exit 0
fi
printf 'code %s\n' "$*" >>"${TEST_HOME}/code.log"
EOF
  chmod +x "${TEST_BIN}/code"
}

stub_code_without_devcontainers_extension() {
  cat >"${TEST_BIN}/code" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "--list-extensions" ]]; then
  printf '%s\n' 'ms-python.python'
  exit 0
fi
printf 'code %s\n' "$*" >>"${TEST_HOME}/code.log"
EOF
  chmod +x "${TEST_BIN}/code"
}

stub_mkcert() {
  local caroot="${TEST_HOME}/mkcert-caroot"
  mkdir -p "${caroot}"
  printf 'test-ca\n' >"${caroot}/rootCA.pem"

  cat >"${TEST_BIN}/mkcert" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "-CAROOT" ]]; then
  printf '%s\n' '${caroot}'
  exit 0
fi
exit 0
EOF
  chmod +x "${TEST_BIN}/mkcert"
}

@test ".devcontainer make help lists the wrapper targets" {
  run make -C "${REPO_ROOT}/.devcontainer" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Setup:"* ]]
  [[ "${output}" == *"prereqs"* ]]
  [[ "${output}" == *"build"* ]]
  [[ "${output}" == *"run"* ]]
  [[ "${output}" == *"up"* ]]
  [[ "${output}" == *"exec"* ]]
  [[ "${output}" == *"check-toolchain-surface"* ]]
}

@test ".devcontainer prereqs checks tools and prepares host mount directories" {
  stub_docker
  stub_devcontainer
  stub_code
  stub_mkcert

  run make -C "${REPO_ROOT}/.devcontainer" prereqs HOST_HOME="${TEST_HOME}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Devcontainer prerequisites look ready"* ]]
  [ -d "${TEST_HOME}/.kube" ]
  [ -d "${TEST_HOME}/.config/platform-devcontainer/mkcert" ]
  [ -f "${TEST_HOME}/.config/platform-devcontainer/mkcert/rootCA.pem" ]
}

@test ".devcontainer prereqs fails on the host when the devcontainer CLI is missing" {
  stub_docker
  stub_code

  run env PATH="${TEST_BIN}:/usr/bin:/bin" make -C "${REPO_ROOT}/.devcontainer" prereqs HOST_HOME="${TEST_HOME}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Missing required tool in PATH: devcontainer"* ]]
}

@test ".devcontainer prereqs warns on the host when the VS Code Dev Containers extension is missing" {
  stub_docker
  stub_devcontainer
  stub_code_without_devcontainers_extension

  run make -C "${REPO_ROOT}/.devcontainer" prereqs HOST_HOME="${TEST_HOME}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARN missing VS Code extension: ms-vscode-remote.remote-containers"* ]]
}

@test ".devcontainer prereqs skips host-only checks from inside the devcontainer" {
  local marker_file="${BATS_TEST_TMPDIR}/dockerenv"
  touch "${marker_file}"

  run make -C "${REPO_ROOT}/.devcontainer" prereqs PLATFORM_DEVCONTAINER=1 CONTAINER_MARKER_FILE="${marker_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Already inside the devcontainer; skipping host-side devcontainer prerequisites."* ]]
}

@test ".devcontainer build removes any existing workspace container before building" {
  stub_docker
  stub_devcontainer
  stub_code
  export DOCKER_PS_AQ_OUTPUT="stale-devcontainer-id"

  run make -C "${REPO_ROOT}/.devcontainer" build HOST_HOME="${TEST_HOME}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Removing existing devcontainer container(s): stale-devcontainer-id"* ]]
  run cat "${TEST_HOME}/docker.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker build -t platform-devcontainer-smoke-"* ]]
  [[ "${output}" == *"docker buildx build --load -t platform-devcontainer-smoke-"* ]]
  [[ "${output}" == *"docker rm -f stale-devcontainer-id"* ]]
  run cat "${TEST_HOME}/devcontainer.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"devcontainer build --workspace-folder ${REPO_ROOT}"* ]]
}

@test ".devcontainer run starts the container without attaching a shell" {
  stub_docker
  stub_devcontainer
  stub_code

  run make -C "${REPO_ROOT}/.devcontainer" run HOST_HOME="${TEST_HOME}"

  [ "${status}" -eq 0 ]
  run cat "${TEST_HOME}/docker.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker build -t platform-devcontainer-smoke-"* ]]
  [[ "${output}" == *"docker buildx build --load -t platform-devcontainer-smoke-"* ]]
  run cat "${TEST_HOME}/devcontainer.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"devcontainer up --workspace-folder ${REPO_ROOT}"* ]]
  [[ "${output}" != *"devcontainer build --workspace-folder ${REPO_ROOT}"* ]]
  [[ "${output}" != *"devcontainer exec --workspace-folder ${REPO_ROOT} zsh -l"* ]]
}

@test ".devcontainer exec ensures the container is running then attaches a shell" {
  stub_docker
  stub_devcontainer
  stub_code

  run make -C "${REPO_ROOT}/.devcontainer" exec HOST_HOME="${TEST_HOME}"

  [ "${status}" -eq 0 ]
  run cat "${TEST_HOME}/docker.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker build -t platform-devcontainer-smoke-"* ]]
  [[ "${output}" == *"docker buildx build --load -t platform-devcontainer-smoke-"* ]]
  run cat "${TEST_HOME}/devcontainer.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"devcontainer up --workspace-folder ${REPO_ROOT}"* ]]
  [[ "${output}" == *"devcontainer exec --workspace-folder ${REPO_ROOT} zsh -l"* ]]
}

@test ".devcontainer up is an alias for ensuring the container is running then attaching a shell" {
  stub_docker
  stub_devcontainer
  stub_code

  run make -C "${REPO_ROOT}/.devcontainer" up HOST_HOME="${TEST_HOME}"

  [ "${status}" -eq 0 ]
  run cat "${TEST_HOME}/docker.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker build -t platform-devcontainer-smoke-"* ]]
  [[ "${output}" == *"docker buildx build --load -t platform-devcontainer-smoke-"* ]]
  run cat "${TEST_HOME}/devcontainer.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"devcontainer up --workspace-folder ${REPO_ROOT}"* ]]
  [[ "${output}" == *"devcontainer exec --workspace-folder ${REPO_ROOT} zsh -l"* ]]
}

@test ".devcontainer exec fails clearly when called from inside the devcontainer" {
  local marker_file="${BATS_TEST_TMPDIR}/dockerenv"
  touch "${marker_file}"

  run make -C "${REPO_ROOT}/.devcontainer" exec PLATFORM_DEVCONTAINER=1 CONTAINER_MARKER_FILE="${marker_file}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"make -C .devcontainer exec must be run from the host. You are already inside the devcontainer."* ]]
}

@test ".devcontainer run fails clearly when called from inside the devcontainer" {
  local marker_file="${BATS_TEST_TMPDIR}/dockerenv"
  touch "${marker_file}"

  run make -C "${REPO_ROOT}/.devcontainer" run PLATFORM_DEVCONTAINER=1 CONTAINER_MARKER_FILE="${marker_file}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"make -C .devcontainer run must be run from the host. You are already inside the devcontainer."* ]]
}

@test ".devcontainer up fails clearly when called from inside the devcontainer" {
  local marker_file="${BATS_TEST_TMPDIR}/dockerenv"
  touch "${marker_file}"

  run make -C "${REPO_ROOT}/.devcontainer" up PLATFORM_DEVCONTAINER=1 CONTAINER_MARKER_FILE="${marker_file}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"make -C .devcontainer exec must be run from the host. You are already inside the devcontainer."* ]]
}

@test ".devcontainer run fails fast with diagnostics when docker buildx smoke hangs" {
  stub_docker_timeout_on_buildx_load
  stub_devcontainer
  stub_code

  run make -C "${REPO_ROOT}/.devcontainer" run HOST_HOME="${TEST_HOME}" DEVCONTAINER_DOCKER_SMOKE_TIMEOUT_SECONDS=1

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Timed out after 1s"* ]]
  [[ "${output}" == *"Docker diagnostics for run"* ]]
  if [[ -f "${TEST_HOME}/devcontainer.log" ]]; then
    run cat "${TEST_HOME}/devcontainer.log"
    [ "${status}" -eq 0 ]
    [[ "${output}" != *"devcontainer up --workspace-folder ${REPO_ROOT}"* ]]
  fi
}

@test ".devcontainer run times out hanging diagnostics instead of stalling after a smoke failure" {
  stub_docker_timeout_on_buildx_and_diagnostics
  stub_devcontainer
  stub_code

  run make -C "${REPO_ROOT}/.devcontainer" run \
    HOST_HOME="${TEST_HOME}" \
    DEVCONTAINER_DOCKER_SMOKE_TIMEOUT_SECONDS=1 \
    DEVCONTAINER_DIAGNOSTIC_TIMEOUT_SECONDS=1

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Timed out after 1s: diagnostic: docker system df"* ]]
  [[ "${output}" == *"WARN diagnostic did not complete cleanly: docker system df"* ]]
}

@test ".devcontainer check-toolchain-surface validates the resolved node feature without loading a workspace image" {
  stub_docker_for_toolchain_surface
  stub_devcontainer_read_configuration

  run make -C "${REPO_ROOT}/.devcontainer" check-toolchain-surface

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"resolved node feature cache is available"* ]]
  [[ "${output}" == *"resolved node feature installs Node 24.15.0, nvm 0.40.4, and no pnpm"* ]]

  run cat "${TEST_HOME}/docker.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker run --rm"* ]]

  run cat "${TEST_HOME}/devcontainer.log"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"devcontainer read-configuration --workspace-folder ${REPO_ROOT} --include-features-configuration --log-format json"* ]]
}

@test ".devcontainer install-toolchain supports dry-run from a copied temp directory" {
  local temp_dir="${BATS_TEST_TMPDIR}/copied-devcontainer"
  mkdir -p "${temp_dir}"
  cp "${REPO_ROOT}/.devcontainer/install-toolchain.sh" "${temp_dir}/install-toolchain.sh"
  cp "${REPO_ROOT}/.devcontainer/toolchain-versions.sh" "${temp_dir}/toolchain-versions.sh"
  chmod +x "${temp_dir}/install-toolchain.sh"

  run "${temp_dir}/install-toolchain.sh" --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would install the devcontainer toolchain for vscode"* ]]
}
