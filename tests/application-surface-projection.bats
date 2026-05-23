#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "platform catalog projects application surfaces into Backstage, launchpad, and observability metrics" {
  run uv run --project "${REPO_ROOT}/apps/idp-core" --with pyyaml python - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import application_surface_projection_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = application_surface_projection_contract_violations(repo_root)
assert not violations, violations

print("validated platform application surface projection locality")
PY

  if [ "${status}" -ne 0 ]; then
    printf '%s\n' "${output}"
  fi
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform application surface projection locality"* ]]
}

@test "application surface projection tests share projection contract helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import application_surface_projection_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "application-surface-projection.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "application surface projection policy should move" not in line
]

assert callable(application_surface_projection_contract_violations)
assert "application_surface_projection_contract_violations" in content
assert not any("yaml.safe_load_all" in line for line in contract_lines), "application surface projection policy should move to tests/app_contracts.py"
assert not any("platform-launchpad.apps.json" in line for line in contract_lines), "application surface projection policy should move to tests/app_contracts.py"
assert not any("catalogMetrics.ts" in line for line in contract_lines), "application surface projection policy should move to tests/app_contracts.py"

print("validated shared application surface projection helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared application surface projection helper usage"* ]]
}

@test "Platform Launchpad renderer previews concrete default targets" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/render-platform-launchpad.sh"

  run "${script}" --dry-run

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"INFO dry-run: would render the Platform Launchpad dashboard into 2 target file(s) with 24 selected tile(s)"* ]]
  [[ "${output}" != *"unknown"* ]]
  [[ "${output}" != *"Unknown"* ]]
}

@test "Platform Launchpad renderer rejects unknown tile toggles" {
  script="${REPO_ROOT}/terraform/kubernetes/scripts/render-platform-launchpad.sh"
  inventory="$(mktemp)"
  cat >"${inventory}" <<'JSON'
{"tiles":[{"title":"New App","url":"https://new.example.test","sort_key":"dev/new","expr":"vector(1)","requires":["ENABLE_NOT_DECLARED"]}]}
JSON

  run env INVENTORY_FILE="${inventory}" "${script}" --dry-run
  rm -f "${inventory}"

  [ "${status}" -ne 0 ]
  [[ "${output}" == *"Launchpad inventory uses unsupported requires toggle(s): ENABLE_NOT_DECLARED"* ]]
}

@test "Platform Launchpad rendered dashboard avoids unknown placeholders and tile drift" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import platform_launchpad_rendered_dashboard_contract_violations

violations = platform_launchpad_rendered_dashboard_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated rendered Platform Launchpad dashboard inventory contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated rendered Platform Launchpad dashboard inventory contract"* ]]
}
