#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/scaffold-platform-service.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  export CURL_LOG="${BATS_TEST_TMPDIR}/curl.log"
  export GITEA_ROOT="${BATS_TEST_TMPDIR}/gitea"
  # file:// lets the real git push land in a local bare repository, while the
  # curl stub below stands in for the Gitea API.
  export GITEA_URL="file://${GITEA_ROOT}"
  export GITEA_ADMIN_USERNAME="gitea-admin"
  export GITEA_ADMIN_PWD="s3cret-test-password"
  mkdir -p "${TEST_BIN}" "${GITEA_ROOT}/platform"
  export PATH="${TEST_BIN}:${PATH}"
}

# FAKE_REPO_STATUS is what GET /repos/... answers; POST answers 201.
write_fake_curl() {
  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${CURL_LOG}"
method="GET"
out=""
config=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -X) method="$2"; shift 2 ;;
    -o) out="$2"; shift 2 ;;
    -K) config="$2"; shift 2 ;;
    -w|-H|--data) shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
[[ -n "${config}" ]] && cat "${config}" >>"${CURL_LOG}.config"
case "${method} ${url}" in
  "GET "*/api/v1/repos/platform/*)
    printf '{}' >"${out}"
    printf '%s' "${FAKE_REPO_STATUS:-404}"
    ;;
  "POST "*/api/v1/orgs/platform/repos)
    git init -q --bare -b main "${GITEA_ROOT}/platform/orders.git"
    printf '{"name":"orders"}' >"${out}"
    printf '201'
    ;;
  *)
    printf 'unexpected curl call: %s %s\n' "${method}" "${url}" >&2
    exit 22
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/curl"
}

@test "scaffold-service creates the Gitea repo and pushes the rendered template to main" {
  write_fake_curl

  run "${SCRIPT}" --execute --name orders --environments dev,uat

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"OK   created Gitea repository platform/orders"* ]]
  [[ "${output}" == *"OK   pushed main to platform/orders"* ]]

  bare="${GITEA_ROOT}/platform/orders.git"
  run git --git-dir="${bare}" ls-tree -r --name-only main
  [ "${status}" -eq 0 ]
  [[ "${output}" == *".gitea/workflows/review-environment.yaml"* ]]
  [[ "${output}" == *"kubernetes/routing/httproutes.yaml"* ]]

  run git --git-dir="${bare}" show main:kubernetes/routing/httproutes.yaml
  [[ "${output}" == *"name: orders-dev"* ]]
  [[ "${output}" == *"name: orders-uat"* ]]
  [[ "${output}" != *'${{'* ]]
}

@test "scaffold-service keeps the Gitea password out of curl's arguments" {
  write_fake_curl

  run "${SCRIPT}" --execute --name orders

  [ "${status}" -eq 0 ]
  run grep -F "${GITEA_ADMIN_PWD}" "${CURL_LOG}"
  [ "${status}" -ne 0 ]
  # It reaches curl through the -K config file instead.
  grep -qF "${GITEA_ADMIN_PWD}" "${CURL_LOG}.config"
}

@test "scaffold-service refuses to overwrite an existing repository" {
  write_fake_curl

  run env FAKE_REPO_STATUS=200 "${SCRIPT}" --execute --name orders

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"already exists"* ]]
  run grep -c -- '-X POST' "${CURL_LOG}"
  [ "${output}" = "0" ]
}

@test "scaffold-service needs a Gitea password before calling the API" {
  write_fake_curl

  run env -u GITEA_ADMIN_PWD -u PLATFORM_ADMIN_PASSWORD "${SCRIPT}" --execute --name orders

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"GITEA_ADMIN_PWD or PLATFORM_ADMIN_PASSWORD must be set"* ]]
  [ ! -e "${CURL_LOG}" ]
}

@test "scaffold-service rejects a name that is not a DNS label before creating anything" {
  write_fake_curl

  run "${SCRIPT}" --execute --name Orders_Service

  [ "${status}" -ne 0 ]
  run grep -c -- '-X POST' "${CURL_LOG}"
  [ "${output}" = "0" ]
}

@test "scaffold-service --render-only renders without touching Gitea" {
  write_fake_curl
  out="${BATS_TEST_TMPDIR}/rendered"

  run "${SCRIPT}" --execute --name orders --render-only "${out}"

  [ "${status}" -eq 0 ]
  [ -f "${out}/.gitea/workflows/build.yaml" ]
  [ ! -e "${CURL_LOG}" ]
}
