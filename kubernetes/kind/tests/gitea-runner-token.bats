#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/fetch-gitea-runner-token.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
}

runner_token_query() {
  cat <<'JSON'
{
  "gitea_http_base": "http://127.0.0.1:30090",
  "gitea_admin_username": "gitea-admin",
  "gitea_admin_pwd": "test-admin-password",
  "gitea_local_access_mode": "nodeport",
  "gitea_http_node_port": "30090",
  "gitea_ssh_node_port": "30022",
  "gitea_namespace": "gitea",
  "kubeconfig_path": "",
  "kubeconfig_context": "kind-kind-local"
}
JSON
}

@test "Terraform runner token external program opts into execute mode" {
  gitops_tf="${REPO_ROOT}/terraform/kubernetes/gitops.tf"
  block="$(sed -n '/data "external" "gitea_runner_token"/,/^}/p' "${gitops_tf}")"

  [[ "${block}" == *'fetch-gitea-runner-token.sh", "--execute"'* ]]
}

@test "runner token helper prefers in-cluster Gitea CLI and emits JSON" {
  cat >"${TEST_BIN}/kubectl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args=" $* "
case "${args}" in
  *" get secret act-runner-secret "*)
    exit 1
    ;;
  *" exec deploy/gitea "*)
    printf 'runner-token-from-cli\n'
    ;;
  *)
    printf 'unexpected kubectl args: %s\n' "$*" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/kubectl"

  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'curl should not be called when in-cluster CLI can issue a runner token\n' >&2
exit 1
EOF
  chmod +x "${TEST_BIN}/curl"

  run bash -lc "export PATH='${TEST_BIN}':\"\$PATH\"; bash '${SCRIPT}' --execute 2>'${BATS_TEST_TMPDIR}/stderr'" <<<"$(runner_token_query)"

  [ "${status}" -eq 0 ]
  [ "$(jq -r '.token' <<<"${output}")" = "runner-token-from-cli" ]
  [ "$(jq -c . <<<"${output}")" = '{"token":"runner-token-from-cli"}' ]
}
