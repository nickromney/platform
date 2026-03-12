#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/kubernetes/kind/scripts/check-host-llm.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
}

@test "skips the host-side LLM probe when the selected mode is not direct" {
  tfvars="${BATS_TEST_TMPDIR}/litellm.tfvars"
  cat >"${tfvars}" <<'EOF'
llm_gateway_mode = "litellm"
EOF

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "curl should not be called" >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/curl"

  run "${SCRIPT}" --var-file "${tfvars}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"host-side LLM check skipped"* ]]
}

@test "detects Docker Desktop model runner for direct mode via /v1/models" {
  tfvars="${BATS_TEST_TMPDIR}/direct.tfvars"
  cat >"${tfvars}" <<'EOF'
llm_gateway_mode = "direct"
llm_gateway_external_name = "host.docker.internal"
EOF

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out_file=""
url=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out_file="$2"
      shift 2
      ;;
    -w|-m)
      shift 2
      ;;
    -s|-S|-sS)
      shift
      ;;
    http://*)
      url="$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "${out_file}" ]] || exit 1
if [[ "${url}" == "http://127.0.0.1:12434/v1/models" ]]; then
  cat >"${out_file}" <<'JSON'
{"object":"list","data":[{"id":"qwen","owned_by":"docker"}]}
JSON
  printf '200'
  exit 0
fi

cat >"${out_file}" <<'JSON'
{}
JSON
printf '000'
EOF
  chmod +x "${TEST_BIN}/curl"

  run "${SCRIPT}" --var-file "${tfvars}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"127.0.0.1:12434"* ]]
  [[ "${output}" == *"Docker Desktop model runner"* ]]
}

@test "fails when direct mode is selected and no host-side LLM endpoint responds" {
  tfvars="${BATS_TEST_TMPDIR}/direct.tfvars"
  cat >"${tfvars}" <<'EOF'
llm_gateway_mode = "direct"
llm_gateway_external_name = "host.docker.internal"
EOF

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
out_file=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o)
      out_file="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "${out_file}" ]] || exit 1
cat >"${out_file}" <<'JSON'
{}
JSON
printf '000'
EOF
  chmod +x "${TEST_BIN}/curl"

  run "${SCRIPT}" --var-file "${tfvars}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"host-side LLM endpoint not detected"* ]]
}
