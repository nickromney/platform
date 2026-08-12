#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

@test "install-tool-hints plain mode suppresses the header and normalizes brew installs" {
  cat >"${TEST_BIN}/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/brew"

  cat >"${TEST_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  -s)
    printf '%s\n' Darwin
    ;;
  -m)
    printf '%s\n' arm64
    ;;
  *)
    printf '%s\n' Darwin
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/uname"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" INSTALL_TOOL_HINTS_MANAGERS="brew curl" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute --plain k3sup-pro docker jq kubie kyverno yamllint

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"Install hints for"* ]]
  [[ "${output}" == *"k3sup-pro: brew install k3sup"* ]]
  [[ "${output}" == *"docker: brew install --cask docker"* ]]
  [[ "${output}" == *"jq: brew install jq"* ]]
  [[ "${output}" == *"kubie: brew install kubie"* ]]
  [[ "${output}" == *"kyverno: brew install kyverno"* ]]
  [[ "${output}" == *"yamllint: brew install yamllint"* ]]
}

@test "install-tool-hints prefers apt on Linux when brew and arkade are absent" {
  cat >"${TEST_BIN}/apt-get" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/apt-get"

  cat >"${TEST_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  -s)
    printf '%s\n' Linux
    ;;
  -m)
    printf '%s\n' x86_64
    ;;
  *)
    printf '%s\n' Linux
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/uname"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" INSTALL_TOOL_HINTS_MANAGERS="apt curl" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute --plain docker jq node npx yamllint

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker: sudo apt-get update && sudo apt-get install -y docker.io"* ]]
  [[ "${output}" == *"jq: sudo apt-get update && sudo apt-get install -y jq"* ]]
  [[ "${output}" == *"node: sudo apt-get update && sudo apt-get install -y nodejs npm"* ]]
  [[ "${output}" == *"npx: sudo apt-get update && sudo apt-get install -y nodejs npm"* ]]
  [[ "${output}" == *"yamllint: sudo apt-get update && sudo apt-get install -y yamllint"* ]]
}

@test "install-tool-hints prefers arkade for kubie when arkade is available" {
  cat >"${TEST_BIN}/arkade" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/arkade"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" INSTALL_TOOL_HINTS_MANAGERS="arkade curl" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute --plain kubie

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kubie: arkade get kubie@0.28.0"* ]]
}

@test "install-tool-hints supports bun and npx" {
  cat >"${TEST_BIN}/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/brew"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" INSTALL_TOOL_HINTS_MANAGERS="brew curl" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute --plain bun npx

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"bun: brew install bun"* ]]
  [[ "${output}" == *"npx: brew install node"* ]]
}

@test "install-tool-hints prefers mise and maps repo tool names onto registry names" {
  cat >"${TEST_BIN}/mise" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/mise"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" INSTALL_TOOL_HINTS_MANAGERS="mise curl" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute --plain jq tofu limactl hubble npx k3sup-pro

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"jq: mise use jq@1.8.2"* ]]
  [[ "${output}" == *"tofu: mise use opentofu@1.12.5"* ]]
  [[ "${output}" == *"limactl: mise use lima@2.2.0"* ]]
  [[ "${output}" == *"hubble: mise use github:cilium/hubble@1.19.4"* ]]
  [[ "${output}" == *"npx: mise use node@24.15.0"* ]]
  [[ "${output}" == *"k3sup-pro: mise use k3sup@0.13.12"* ]]
}

@test "install-tool-hints uses pacman on Arch and picks go-yq for mikefarah yq" {
  cat >"${TEST_BIN}/pacman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/pacman"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" INSTALL_TOOL_HINTS_MANAGERS="pacman curl" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute --plain docker yq mkcert gh step tofu node

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"docker: sudo pacman -S --needed docker"* ]]
  [[ "${output}" == *"yq: sudo pacman -S --needed go-yq"* ]]
  [[ "${output}" == *"mkcert: sudo pacman -S --needed mkcert nss"* ]]
  [[ "${output}" == *"gh: sudo pacman -S --needed github-cli"* ]]
  [[ "${output}" == *"step: sudo pacman -S --needed step-cli"* ]]
  [[ "${output}" == *"tofu: sudo pacman -S --needed opentofu"* ]]
  [[ "${output}" == *"node: sudo pacman -S --needed nodejs npm"* ]]
}

@test "install-tool-hints ranks self-updating managers ahead of arkade" {
  for stub in mise pacman arkade; do
    cat >"${TEST_BIN}/${stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
    chmod +x "${TEST_BIN}/${stub}"
  done

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute --plain kubectl docker

  [ "${status}" -eq 0 ]
  # mise carries kubectl, so arkade must not win it.
  [[ "${output}" == *"kubectl: mise use kubectl@1.36.3"* ]]
  # docker is in neither mise nor arkade, so pacman handles it.
  [[ "${output}" == *"docker: sudo pacman -S --needed docker"* ]]
}

@test "install-tool-hints falls back to arkade only for tools no manager carries" {
  cat >"${TEST_BIN}/arkade" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/arkade"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" INSTALL_TOOL_HINTS_MANAGERS="arkade curl" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute --plain kyverno step bun

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kyverno: arkade get kyverno@1.18.2"* ]]
  [[ "${output}" == *"step: arkade get step@0.30.6"* ]]
  [[ "${output}" == *"bun: arkade get bun@1.3.14"* ]]
}

@test "install-tool-hints reports missing platform facts without unknown placeholders" {
  cat >"${TEST_BIN}/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 1
EOF
  chmod +x "${TEST_BIN}/uname"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" INSTALL_TOOL_HINTS_MANAGERS="brew pacman apt arkade curl" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --execute docker

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"unknown"* ]]
  [[ "${output}" == *"Install hints for OS not reported architecture not reported"* ]]
}
