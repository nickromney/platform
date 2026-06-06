#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/platform-status-read-model.sh"
}

write_status_stub() {
  status_stub="${BATS_TEST_TMPDIR}/platform-status.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" != "--execute --output json" ]]; then
  printf 'unexpected args: %s\n' "$*" >&2
  exit 64
fi

cat <<'JSON'
{
  "generated_at": "2026-05-03T12:00:00Z",
  "overall_state": "running",
  "active_variant": "kind",
  "active_variant_path": "kubernetes/kind",
  "variants_order": ["kind", "lima"],
  "variants": {
    "kind": {
      "key": "kind",
      "path": "kubernetes/kind",
      "label": "Kind local cluster",
      "runtime_family": "docker",
      "state": "running",
      "serving": true,
      "runtime_present": true,
      "blockers": [],
      "readiness": {
        "docker_available": true,
        "kind_available": true
      }
    },
    "lima": {
      "key": "lima",
      "path": "kubernetes/lima",
      "label": "Kubernetes Lima cluster",
      "runtime_family": "lima",
      "state": "blocked",
      "serving": false,
      "runtime_present": false,
      "blockers": ["shared host ports claimed by kubernetes/kind"],
      "readiness": {
        "docker_available": true,
        "limactl_available": true,
        "bootstrap_client": false
      }
    }
  },
  "actions": [
    {
      "id": "kind-status",
      "label": "Kind status",
      "variant": "kind",
      "variant_path": "kubernetes/kind",
      "enabled": true,
      "reason": null,
      "command": "make -C kubernetes/kind status",
      "dangerous": false
    },
    {
      "id": "kind-stop",
      "label": "Stop kind",
      "variant": "kind",
      "variant_path": "kubernetes/kind",
      "enabled": true,
      "reason": null,
      "command": "make -C kubernetes/kind stop-kind",
      "dangerous": false
    },
    {
      "id": "lima-status",
      "label": "Kubernetes Lima status",
      "variant": "lima",
      "variant_path": "kubernetes/lima",
      "enabled": true,
      "reason": null,
      "command": "make -C kubernetes/lima status",
      "dangerous": false
    },
    {
      "id": "lima-apply-900",
      "label": "Kubernetes Lima stage 900 apply",
      "variant": "lima",
      "variant_path": "kubernetes/lima",
      "enabled": false,
      "reason": "shared host ports claimed by kubernetes/kind",
      "command": "make -C kubernetes/lima 900 apply AUTO_APPROVE=1",
      "dangerous": true
    }
  ]
}
JSON
EOF
  chmod +x "${status_stub}"
  export PLATFORM_STATUS_READ_MODEL_STATUS_SCRIPT="${status_stub}"
}

@test "status read model extracts ownership readiness blockers and actions" {
  write_status_stub

  run "${SCRIPT}" --execute --output json

  [ "${status}" -eq 0 ]

  run jq -r '
    [
      .schema_version,
      .source.name,
      (.source.observed_live_state | tostring),
      (.source.terraform_truth | tostring),
      .active_owner.variant_path,
      (.variants.kind.ownership.active_owner | tostring),
      (.variants.kind.readiness.ready | tostring),
      (.variants.kind.readiness.checks.kind_available | tostring),
      (.variants.lima.ownership.active_owner | tostring),
      (.variants.lima.readiness.ready | tostring),
      (.variants.lima.readiness.blocker_count | tostring),
      .variants.lima.readiness.blocking_owners[0],
      .variants.lima.readiness.recommended_action.command,
      .variants.lima.blockers[0].claim,
      .variants.lima.blockers[0].blocking_owner,
      .variants.lima.blockers[0].recommended_action.command,
      .variants.lima.recommended_action.command,
      (.variants.lima.actions | length | tostring)
    ] | join("|")
  ' <<<"${output}"

  [ "${status}" -eq 0 ]
  [ "${output}" = "0.1|platform-status|true|false|kubernetes/kind|true|true|true|false|false|1|kubernetes/kind|make -C kubernetes/kind stop-kind|shared host ports|kubernetes/kind|make -C kubernetes/kind stop-kind|make -C kubernetes/lima status|2" ]

  run "${SCRIPT}" --execute --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"kubernetes/lima: blocked blocker_count=1 recommended=make -C kubernetes/kind stop-kind"* ]]
}

@test "status read model reports missing status fields without unknown placeholders" {
  status_stub="${BATS_TEST_TMPDIR}/platform-status-missing-fields.sh"

  cat >"${status_stub}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" != "--execute --output json" ]]; then
  printf 'unexpected args: %s\n' "$*" >&2
  exit 64
fi

cat <<'JSON'
{
  "generated_at": "2026-05-03T12:00:00Z",
  "active_variant": null,
  "active_variant_path": null,
  "variants_order": ["kind"],
  "variants": {
    "kind": {
      "path": "kubernetes/kind",
      "blockers": [],
      "readiness": {}
    }
  },
  "actions": []
}
JSON
EOF
  chmod +x "${status_stub}"

  run env PLATFORM_STATUS_READ_MODEL_STATUS_SCRIPT="${status_stub}" "${SCRIPT}" --execute --output text

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Overall: not reported"* ]]
  [[ "${output}" == *"kubernetes/kind: not reported"* ]]
  [[ "${output}" != *"unknown"* ]]
  [[ "${output}" != *"Unknown"* ]]
}

@test "status read model previews without execute" {
  run "${SCRIPT}" --output json

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: platform-status-read-model.sh"* ]]
  [[ "${output}" == *"INFO dry-run: would build platform status read model"* ]]
}
