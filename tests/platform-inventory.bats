#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-inventory.sh"
}

@test "platform inventory combines status and workflow metadata" {
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  read_model_stub="${BATS_TEST_TMPDIR}/platform-status-read-model.sh"
  workflow_stub="${BATS_TEST_TMPDIR}/platform-workflow.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"generated_at":"2026-05-03T12:00:00Z","overall_state":"ready","active_variant":"kind","active_variant_path":"kubernetes/kind","variants_order":["kind"],"variants":{"kind":{"state":"ready","blockers":[]}},"host_runtimes":{},"host_runtimes_order":[],"registry_auth":{},"registry_auth_order":[]}\n'
EOF
  chmod +x "${status_stub}"

  cat >"${read_model_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" != "--execute --output json" ]]; then
  printf 'unexpected args: %s\n' "$*" >&2
  exit 64
fi
printf '{"schema_version":"0.1","source":{"name":"platform-status-read-model"},"overall_state":"ready","active_owner":{"variant":"kind","variant_path":"kubernetes/kind"},"variants_order":["kind"],"variants":{"kind":{"ownership":{"variant":"kind","variant_path":"kubernetes/kind","label":"Kind local cluster","runtime_family":"docker","active_owner":true,"serving":true,"runtime_present":true},"readiness":{"state":"ready","ready":false,"blocker_count":1,"blocking_owners":["kubernetes/lima"],"recommended_action":{"id":"lima-stop","command":"make -C kubernetes/lima stop-lima","enabled":true,"dangerous":false},"checks":{"kind_available":true}},"blockers":[{"id":"kind-blocker-0","message":"shared host ports claimed by kubernetes/lima","blocking_owner":"kubernetes/lima","recommended_action":{"id":"lima-stop","command":"make -C kubernetes/lima stop-lima","enabled":true,"dangerous":false}}],"recommended_action":{"id":"kind-status","command":"make -C kubernetes/kind status","enabled":true,"dangerous":false},"actions":[]}}}\n'
EOF
  chmod +x "${read_model_stub}"

  cat >"${workflow_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"variant":{"id":"kind","path":"kubernetes/kind"},"stage":"900","action":"status","contexts":[{"id":"platform-stack"}],"contract_requirements":[{"id":"identity"}],"effective_config":{"source_precedence":["stage_baseline","custom_overrides"]}}\n'
EOF
  chmod +x "${workflow_stub}"

  run env \
    PLATFORM_INVENTORY_STATUS_SCRIPT="${status_stub}" \
    PLATFORM_INVENTORY_READ_MODEL_SCRIPT="${read_model_stub}" \
    PLATFORM_INVENTORY_WORKFLOW_SCRIPT="${workflow_stub}" \
    "${SCRIPT}" --execute --variant kind --stage 900 --output json

  [ "${status}" -eq 0 ]
  run jq -r '.variant, .stage, .observed_live_state, .terraform_truth, .health_summary.overall_state, .workflow.contract_requirements[0].id, .status_read_model.source.name, .variants.kind.state, (.variants.kind.readiness.blocker_count | tostring), .variants.kind.blockers[0], .variants.kind.blocker_facts[0].recommended_action.command, .variants.kind.recommended_action.command' <<<"${output}"
  [ "${status}" -eq 0 ]
  [ "${output}" = $'kind\n900\ntrue\nfalse\nready\nidentity\nplatform-status-read-model\nready\n1\nshared host ports claimed by kubernetes/lima\nmake -C kubernetes/lima stop-lima\nmake -C kubernetes/lima stop-lima' ]
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

@test "platform inventory text output avoids unknown placeholders for missing health fields" {
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"
  workflow_stub="${BATS_TEST_TMPDIR}/platform-workflow.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"generated_at":"2026-05-03T12:00:00Z","active_variant":null,"variants_order":[],"variants":{},"host_runtimes":{},"host_runtimes_order":[],"registry_auth":{},"registry_auth_order":[]}\n'
EOF
  chmod +x "${status_stub}"

  cat >"${workflow_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '{"variant":{"id":"kind"},"stage":"900","action":"status","contexts":[],"contract_requirements":[],"effective_config":{}}\n'
EOF
  chmod +x "${workflow_stub}"

  run env \
    PLATFORM_INVENTORY_STATUS_SCRIPT="${status_stub}" \
    PLATFORM_INVENTORY_WORKFLOW_SCRIPT="${workflow_stub}" \
    "${SCRIPT}" --execute --variant kind --stage 900 --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overall: not reported"* ]]
  [[ "${output}" == *"Active variant: none"* ]]
  [[ "${output}" != *"unknown"* ]]
  [[ "${output}" != *"Unknown"* ]]
}
