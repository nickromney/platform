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

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --plain k3sup-pro docker jq kubie kyverno yamllint

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

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --plain docker jq node npx yamllint

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

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --plain kubie

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kubie: sudo arkade get kubie --path /usr/local/bin"* ]]
}

@test "install-tool-hints supports bun and npx" {
  cat >"${TEST_BIN}/brew" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "${TEST_BIN}/brew"

  run env PATH="${TEST_BIN}:/usr/bin:/bin" /bin/bash "${REPO_ROOT}/scripts/install-tool-hints.sh" --plain bun npx

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"bun: brew install bun"* ]]
  [[ "${output}" == *"npx: brew install node"* ]]
}
