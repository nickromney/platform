#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/terraform/kubernetes/scripts/review-environment-dispatch.sh"
  export TEST_BIN="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${TEST_BIN}"
  export PATH="${TEST_BIN}:${PATH}"
  export GITEA_HTTP_BASE="http://gitea.test"
  export GITEA_ADMIN_USERNAME="gitea-admin"
  export GITEA_ADMIN_PWD="test-admin-password"
  export GITEA_REPO_OWNER="platform"
  export APP_REPO_NAME="sentiment"
  export APP_WORKFLOW_ID="review-environment.yaml"
  export APP_WORKFLOW_REF="feature/branch"
  export APP_DISPLAY_NAME="sentiment"
}

@test "review dispatch interface posts workflow_dispatch for repo workflow and ref" {
  capture_file="${BATS_TEST_TMPDIR}/curl-args"
  export CAPTURE_FILE="${capture_file}"
  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >"${CAPTURE_FILE:?}"
printf '\n204'
EOF
  chmod +x "${TEST_BIN}/curl"

  run bash -lc "export PATH='${TEST_BIN}':\"\$PATH\"; source '${SCRIPT}'; review_dispatch_workflow"

  [ "${status}" -eq 0 ]
  grep -Fq "/api/v1/repos/platform/sentiment/actions/workflows/review-environment.yaml/dispatches" "${capture_file}"
  grep -Fq '{"ref":"feature/branch"}' "${capture_file}"
}

@test "review dispatch retry handler triggers one retry for a failed tagged run" {
  capture_file="${BATS_TEST_TMPDIR}/dispatches"
  export CAPTURE_FILE="${capture_file}"
  cat >"${TEST_BIN}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
args="$*"
case "${args}" in
  *"/actions/runs?limit=5"*)
    cat <<'JSON'
{
  "workflow_runs": [
    {
      "head_sha": "abc1234567890",
      "status": "completed",
      "conclusion": "failure",
      "id": 42,
      "html_url": "http://gitea.test/platform/sentiment/actions/runs/42"
    }
  ]
}
JSON
    ;;
  *"/dispatches"*)
    printf '%s\n' "${args}" >>"${CAPTURE_FILE:?}"
    printf '\n204'
    ;;
  *)
    printf '{}'
    ;;
esac
EOF
  chmod +x "${TEST_BIN}/curl"

  run bash -lc "export PATH='${TEST_BIN}':\"\$PATH\"; source '${SCRIPT}'; check_actions_failure abc123; printf 'retried=%s\n' \"\$ACTIONS_RETRIGGERED_TAG\""

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Triggering one workflow_dispatch retry"* ]]
  [[ "${output}" == *"retried=abc123"* ]]
  grep -Fq "/api/v1/repos/platform/sentiment/actions/workflows/review-environment.yaml/dispatches" "${capture_file}"
}
