#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/scripts/k3s-bootstrap-lib.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${TEST_BIN}" "${HOME}/.arkade/bin"
  export PATH="${TEST_BIN}:${PATH}"
}

write_executable() {
  local path="$1"
  mkdir -p "$(dirname "${path}")"
  cat >"${path}" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${path}"
}

@test "k3s bootstrap lib finds clients in explicit and PATH preference order" {
  explicit_pro="${BATS_TEST_TMPDIR}/explicit/k3sup-pro"
  explicit_k3sup="${BATS_TEST_TMPDIR}/explicit/k3sup"
  path_pro="${TEST_BIN}/k3sup-pro"
  path_k3sup="${TEST_BIN}/k3sup"
  arkade_k3sup="${HOME}/.arkade/bin/k3sup"
  write_executable "${explicit_pro}"
  write_executable "${explicit_k3sup}"
  write_executable "${path_pro}"
  write_executable "${path_k3sup}"
  write_executable "${arkade_k3sup}"

  run bash -lc "source '${SCRIPT}'; K3SUP_PRO_BIN='${explicit_pro}' K3SUP_BIN='${explicit_k3sup}' PATH='${TEST_BIN}' HOME='${HOME}' k3s_bootstrap_find_client"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${explicit_pro}" ]

  run bash -lc "source '${SCRIPT}'; K3SUP_PRO_BIN='' K3SUP_BIN='${explicit_k3sup}' PATH='${TEST_BIN}' HOME='${HOME}' k3s_bootstrap_find_client"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${path_pro}" ]

  rm -f "${path_pro}"
  run bash -lc "source '${SCRIPT}'; K3SUP_PRO_BIN='' K3SUP_BIN='${explicit_k3sup}' PATH='${TEST_BIN}' HOME='${HOME}' k3s_bootstrap_find_client"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${explicit_k3sup}" ]

  rm -f "${explicit_k3sup}"
  run bash -lc "source '${SCRIPT}'; K3SUP_PRO_BIN='' K3SUP_BIN='' PATH='${TEST_BIN}' HOME='${HOME}' k3s_bootstrap_find_client"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${path_k3sup}" ]

  rm -f "${path_k3sup}"
  run bash -lc "source '${SCRIPT}'; K3SUP_PRO_BIN='' K3SUP_BIN='' PATH='${TEST_BIN}' HOME='${HOME}' k3s_bootstrap_find_client"
  [ "${status}" -eq 0 ]
  [ "${output}" = "${arkade_k3sup}" ]
}

@test "k3s bootstrap lib renders version args instead of channel args when a version is set" {
  run bash -lc "source '${SCRIPT}'; k3s_bootstrap_channel_args stable ''"
  [ "${status}" -eq 0 ]
  [ "${output}" = "--k3s-channel stable" ]

  run bash -lc "source '${SCRIPT}'; k3s_bootstrap_channel_args stable 'v1.35.1+k3s1'"
  [ "${status}" -eq 0 ]
  [ "${output}" = "--k3s-version v1.35.1+k3s1" ]
}
