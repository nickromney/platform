#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/hubble-capture-flows.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export PATH="${TEST_BIN}:${PATH}"
  export HUBBLE_LOG="${BATS_TEST_TMPDIR}/hubble.log"

  mkdir -p "${TEST_BIN}"
  : > "${HUBBLE_LOG}"
}

@test "hubble-capture-flows adaptive mode escalates recent samples before falling back to since" {
  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "observe --help" ]]; then
  cat <<'HELP'
      --experimental-field-mask strings
HELP
  exit 0
fi

printf '%s\n' "$*" >> "${HUBBLE_LOG}"

last=""
since=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --last)
      last="${2:-}"
      shift 2
      ;;
    --since)
      since="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

if [[ -n "${last}" ]]; then
  cat <<'JSON'
{"flow":{"verdict":"FORWARDED","is_reply":true}}
JSON
  exit 0
fi

if [[ "${since}" == "30s" ]]; then
  cat <<'JSON'
{"flow":{"verdict":"FORWARDED","is_reply":false}}
JSON
  exit 0
fi

exit 1
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${SCRIPT}" \
    --execute \
    --server localhost:4245 \
    --namespace argocd \
    --capture-strategy adaptive \
    --since 30s \
    --sample-target 1000 \
    --sample-min 2

  [ "${status}" -eq 0 ]

  run cat "${HUBBLE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--last 100"* ]]
  [[ "${output}" == *"--last 300"* ]]
  [[ "${output}" == *"--last 1000"* ]]
  [[ "${output}" == *"--since 30s"* ]]
}

@test "hubble-capture-flows adaptive mode stops once the sample minimum is satisfied" {
  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "observe --help" ]]; then
  cat <<'HELP'
      --experimental-field-mask strings
HELP
  exit 0
fi

printf '%s\n' "$*" >> "${HUBBLE_LOG}"

last=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --last)
      last="${2:-}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

case "${last}" in
  100)
    cat <<'JSON'
{"flow":{"verdict":"FORWARDED","is_reply":true}}
JSON
    ;;
  300)
    cat <<'JSON'
{"flow":{"verdict":"FORWARDED","is_reply":false}}
{"flow":{"verdict":"FORWARDED","is_reply":false}}
JSON
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${SCRIPT}" \
    --execute \
    --server localhost:4245 \
    --namespace argocd \
    --capture-strategy adaptive \
    --since 30s \
    --sample-target 1000 \
    --sample-min 2

  [ "${status}" -eq 0 ]

  run cat "${HUBBLE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--last 100"* ]]
  [[ "${output}" == *"--last 300"* ]]
  [[ "${output}" != *"--last 1000"* ]]
  [[ "${output}" != *"--since 30s"* ]]
}

@test "hubble-capture-flows keeps explicit last queries working unchanged" {
  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "observe --help" ]]; then
  exit 0
fi

printf '%s\n' "$*" >> "${HUBBLE_LOG}"
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${SCRIPT}" \
    --execute \
    --server localhost:4245 \
    --namespace observability \
    --last 42 \
    --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--last 42"* ]]
  [[ "${output}" != *"--since 10m"* ]]
}

@test "hubble-capture-flows applies policy-observe field masks only when supported" {
  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "observe --help" ]]; then
  cat <<'HELP'
      --experimental-field-mask strings
HELP
  exit 0
fi
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${SCRIPT}" \
    --execute \
    --server localhost:4245 \
    --namespace observability \
    --capture-strategy last \
    --sample-target 1000 \
    --field-mask-profile policy-observe \
    --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--experimental-field-mask"* ]]
  [[ "${output}" == *"verdict\\,traffic_direction\\,is_reply\\,source\\,destination\\,source_names\\,destination_names\\,IP\\,l4\\,l7.dns"* ]]

  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "observe --help" ]]; then
  exit 0
fi
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${SCRIPT}" \
    --server localhost:4245 \
    --namespace observability \
    --capture-strategy last \
    --sample-target 1000 \
    --field-mask-profile policy-observe \
    --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"--experimental-field-mask"* ]]
}

@test "hubble-capture-flows retries without an invalid experimental field mask" {
  cat > "${TEST_BIN}/hubble" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == "observe --help" ]]; then
  cat <<'HELP'
      --experimental-field-mask strings
HELP
  exit 0
fi

printf '%s\n' "$*" >> "${HUBBLE_LOG}"

if [[ "$*" == *"--experimental-field-mask"* ]]; then
  echo 'failed to construct field mask: proto: invalid path "flow.verdict" for message "flow.Flow"' >&2
  exit 1
fi

cat <<'JSON'
{"flow":{"verdict":"FORWARDED","is_reply":false}}
JSON
EOF
  chmod +x "${TEST_BIN}/hubble"

  run "${SCRIPT}" \
    --execute \
    --server localhost:4245 \
    --namespace observability \
    --capture-strategy last \
    --sample-target 1000 \
    --field-mask-profile policy-observe

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"experimental field mask was rejected by this Hubble version; retrying without it"* ]]
  [[ "${output}" == *'{"flow":{"verdict":"FORWARDED","is_reply":false}}'* ]]

  run cat "${HUBBLE_LOG}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"--experimental-field-mask"* ]]
  [ "$(grep -c -- '--experimental-field-mask' "${HUBBLE_LOG}")" = "1" ]
  [ "$(grep -vc -- '--experimental-field-mask' "${HUBBLE_LOG}")" = "1" ]
}
