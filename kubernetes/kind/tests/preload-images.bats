#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/preload-images.sh"
}

@test "preload-images blocks kind load with kind older than v0.32.0" {
  local stub_bin="${BATS_TEST_TMPDIR}/bin"
  local image_list="${BATS_TEST_TMPDIR}/images.txt"
  mkdir -p "${stub_bin}"

  cat >"${stub_bin}/kind" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

case "$*" in
  "version -q")
    printf 'v0.31.0\n'
    ;;
  *)
    printf 'unexpected kind command: %s\n' "$*" >&2
    exit 2
    ;;
esac
EOF
  chmod +x "${stub_bin}/kind"
  printf 'busybox:latest\n' >"${image_list}"

  run env PATH="${stub_bin}:${PATH}" "${SCRIPT}" --execute --image-list "${image_list}" --cluster kind-local

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"kind load requires kind v0.32.0 or newer"* ]]
  [[ "${output}" == *"installed kind v0.31.0"* ]]
}
