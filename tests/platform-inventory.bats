#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-inventory.sh"
}

@test "platform inventory combines status and workflow metadata" {
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  workflow_stub="${BATS_TEST_TMPDIR}/platform-workflow.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"generated_at":"2026-05-03T12:00:00Z","overall_state":"ready","active_variant":"kind","active_variant_path":"kubernetes/kind","variants_order":["kind"],"variants":{"kind":{"state":"ready","blockers":[]}},"host_runtimes":{},"host_runtimes_order":[],"registry_auth":{},"registry_auth_order":[]}\n'
EOF
  chmod +x "${status_stub}"

  cat >"${workflow_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"variant":{"id":"kind","path":"kubernetes/kind"},"stage":"900","action":"status","contexts":[{"id":"platform-stack"}],"contract_requirements":[{"id":"identity"}],"effective_config":{"source_precedence":["stage_baseline","custom_overrides"]}}\n'
EOF
  chmod +x "${workflow_stub}"

  run env \
    PLATFORM_INVENTORY_STATUS_SCRIPT="${status_stub}" \
    PLATFORM_INVENTORY_WORKFLOW_SCRIPT="${workflow_stub}" \
    "${SCRIPT}" --execute --variant kind --stage 900 --output json

  [ "${status}" -eq 0 ]
  run jq -r '.variant, .stage, .observed_live_state, .terraform_truth, .health_summary.overall_state, .workflow.contract_requirements[0].id, .variants.kind.state' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'kind\n900\ntrue\nfalse\nready\nidentity\nready' ]
}

@test "platform inventory has a concise text output" {
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  workflow_stub="${BATS_TEST_TMPDIR}/platform-workflow.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"generated_at":"2026-05-03T12:00:00Z","overall_state":"blocked","active_variant":null,"variants_order":[],"variants":{},"host_runtimes":{},"host_runtimes_order":[],"registry_auth":{},"registry_auth_order":[]}\n'
EOF
  chmod +x "${status_stub}"

  cat >"${workflow_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"variant":{"id":"slicer"},"stage":"700","action":"status","contexts":[],"contract_requirements":[],"effective_config":{}}\n'
EOF
  chmod +x "${workflow_stub}"

  run env \
    PLATFORM_INVENTORY_STATUS_SCRIPT="${status_stub}" \
    PLATFORM_INVENTORY_WORKFLOW_SCRIPT="${workflow_stub}" \
    "${SCRIPT}" --execute --variant slicer --stage 700 --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Variant: slicer"* ]]
  [[ "${output}" == *"Stage: 700"* ]]
  [[ "${output}" == *"Overall: blocked"* ]]
  [[ "${output}" == *"Active variant: none"* ]]
}
