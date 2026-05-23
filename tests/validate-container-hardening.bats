#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "repo-owned app workloads apply the hardened container baseline" {
  run uv run --isolated --with pyyaml python - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import kubernetes_workload_container_hardening_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = kubernetes_workload_container_hardening_contract_violations(repo_root)
assert not violations, violations
print("validated repo-owned workload container hardening baseline")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated repo-owned workload container hardening baseline"* ]]
}

@test "container hardening tests share repo-owned workload baseline helpers" {
  run uv run --isolated python - <<'PY'
from pathlib import Path

from tests.app_contracts import kubernetes_workload_container_hardening_contract_violations

test_file = Path("tests/validate-container-hardening.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "repo-owned app workloads apply the hardened container baseline"'):
    content.index('\n@test "rendered UAT workloads explicitly satisfy the privileged-container policy"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "container hardening baseline policy should move" not in line
]

assert callable(kubernetes_workload_container_hardening_contract_violations)
assert "kubernetes_workload_container_hardening_contract_violations" in test_body
assert not any("readOnlyRootFilesystem" in line for line in contract_lines), "container hardening baseline policy should move to tests/app_contracts.py"
assert not any("allowPrivilegeEscalation" in line for line in contract_lines), "container hardening baseline policy should move to tests/app_contracts.py"
assert not any("persistentVolumeClaim" in line for line in contract_lines), "container hardening baseline policy should move to tests/app_contracts.py"
assert not any("sentiment-auth-ui" in line for line in contract_lines), "container hardening baseline policy should move to tests/app_contracts.py"

print("validated shared container hardening baseline helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared container hardening baseline helper usage"* ]]
}

@test "rendered UAT workloads explicitly satisfy the privileged-container policy" {
  run uv run --isolated --with pyyaml python - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import rendered_uat_privileged_container_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = rendered_uat_privileged_container_contract_violations(repo_root)
assert not violations, violations
print("validated UAT container privileged=false settings")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"UAT container privileged=false"* ]]
}

@test "container hardening tests share rendered UAT privileged helpers" {
  run uv run --isolated python - <<'PY'
from pathlib import Path

from tests.app_contracts import rendered_uat_privileged_container_contract_violations

test_file = Path("tests/validate-container-hardening.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "rendered UAT workloads explicitly satisfy the privileged-container policy"'):
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "rendered UAT privileged policy should move" not in line
]

assert callable(rendered_uat_privileged_container_contract_violations)
assert "rendered_uat_privileged_container_contract_violations" in test_body
assert not any("kubectl" in line for line in contract_lines), "rendered UAT privileged policy should move to tests/app_contracts.py"
assert not any("kustomize" in line for line in contract_lines), "rendered UAT privileged policy should move to tests/app_contracts.py"
assert not any(
    "privileged" in line
    and "assert" in line
    and "rendered_uat_privileged_container_contract_violations" not in line
    for line in contract_lines
), "rendered UAT privileged policy should move to tests/app_contracts.py"

print("validated shared rendered UAT privileged helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared rendered UAT privileged helper usage"* ]]
}
