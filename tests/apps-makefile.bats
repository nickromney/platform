#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

teardown() {
  rm -rf "${REPO_ROOT}/apps/zz-test-update-wrapper"
  rm -rf "${REPO_ROOT}/apps/zz-test-app-wrapper"
  rm -rf "${REPO_ROOT}/apps/zz-test-js-wrapper"
  rm -rf "${REPO_ROOT}/apps/zz-test-compose-wrapper"
}

@test "apps make help exposes the Trivy security workflow" {
  run make -C "${REPO_ROOT}/apps" help

  [ "${status}" -eq 0 ]
  local make_output="${output}"
  run env MAKE_OUTPUT="${make_output}" uv run --isolated python - <<PY
import os

from tests.app_contracts import apps_makefile_help_contract_violations

violations = apps_makefile_help_contract_violations(os.environ["MAKE_OUTPUT"])
assert not violations, violations
print("validated apps Makefile help workflow contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated apps Makefile help workflow contract"* ]]
}

@test "apps make help does not scan wrapper Makefiles for delegated targets" {
  grep_stub_dir="${BATS_TEST_TMPDIR}/bin"
  grep_log="${BATS_TEST_TMPDIR}/grep.log"
  mkdir -p "${grep_stub_dir}"

  cat >"${grep_stub_dir}/grep" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf 'grep %s\n' "\$*" >>"${grep_log}"
exec /usr/bin/grep "\$@"
EOF
  chmod +x "${grep_stub_dir}/grep"

  run env PATH="${grep_stub_dir}:${PATH}" make -C "${REPO_ROOT}/apps" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Workflow:"* ]]
  [[ "${output}" == *"Security:"* ]]
  [ ! -e "${grep_log}" ]
}

@test "apps prereqs stays Trivy-optional" {
  run make -C "${REPO_ROOT}/apps" prereqs

  [ "${status}" -eq 0 ]
  local make_output="${output}"
  run env MAKE_OUTPUT="${make_output}" uv run --isolated python - <<PY
import os

from tests.app_contracts import apps_prereqs_contract_violations

violations = apps_prereqs_contract_violations(os.environ["MAKE_OUTPUT"])
assert not violations, violations
print("validated apps prereqs optional Trivy contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated apps prereqs optional Trivy contract"* ]]
}

@test "apps Makefile tests share workflow surface helpers" {
  run uv run --isolated python - <<PY
from pathlib import Path

from tests.app_contracts import apps_makefile_help_contract_violations, apps_prereqs_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "apps-makefile.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "apps workflow surface policy should move" not in line
]

assert callable(apps_makefile_help_contract_violations)
assert callable(apps_prereqs_contract_violations)
assert "apps_makefile_help_contract_violations" in content
assert "apps_prereqs_contract_violations" in content
assert not any('[[ "${output}" == *"trivy-scan-images"* ]]' in line for line in contract_lines), "apps workflow surface policy should move to tests/app_contracts.py"
assert not any('[[ "${output}" != *"Runner mode:"* ]]' in line for line in contract_lines), "apps workflow surface policy should move to tests/app_contracts.py"

print("validated shared apps Makefile workflow helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared apps Makefile workflow helper usage"* ]]
}

@test "apps test delegates to the default app checks" {
  temp_app="${REPO_ROOT}/apps/zz-test-app-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}"
  printf '%s\n' \
    'MAKE_KNOWN_GOALS := test' \
    '.PHONY: test' \
    'test:' \
    '	@echo test wrapper' \
    >"${temp_app}/Makefile"

  run make -n -C "${REPO_ROOT}/apps" test

  [ "${status}" -eq 0 ]
  local make_output="${output}"
  run env MAKE_OUTPUT="${make_output}" uv run --isolated python - <<PY
from pathlib import Path
import os

from tests.app_contracts import apps_makefile_delegation_contract_violations

violations = apps_makefile_delegation_contract_violations(
    Path("${REPO_ROOT}"),
    os.environ["MAKE_OUTPUT"],
    wrapper_target="test",
    delegated_target="test",
)
assert not violations, violations
print("validated apps test wrapper delegation")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated apps test wrapper delegation"* ]]
  [[ "${make_output}" != *"-C ./chatgpt-sim/app test"* ]]
  [[ "${make_output}" != *"./chatgpt-sim/tests/compose-smoke.sh"* ]]
  rm -rf "${temp_app}"
}

@test "apps js-check delegates to app wrapper JavaScript checks" {
  temp_app="${REPO_ROOT}/apps/zz-test-js-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}"
  printf '%s\n' \
    'MAKE_KNOWN_GOALS := app-js-check' \
    '.PHONY: app-js-check' \
    'app-js-check:' \
    '	@echo js wrapper' \
    >"${temp_app}/Makefile"

  run make -n -C "${REPO_ROOT}/apps" js-check

  [ "${status}" -eq 0 ]
  local make_output="${output}"
  run env MAKE_OUTPUT="${make_output}" uv run --isolated python - <<PY
from pathlib import Path
import os

from tests.app_contracts import apps_makefile_delegation_contract_violations

violations = apps_makefile_delegation_contract_violations(
    Path("${REPO_ROOT}"),
    os.environ["MAKE_OUTPUT"],
    wrapper_target="app-js-check",
    delegated_target="app-js-check",
)
assert not violations, violations
print("validated apps js-check wrapper delegation")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated apps js-check wrapper delegation"* ]]
  [[ "${make_output}" != *"-C ./chatgpt-sim/app js-check"* ]]
  [[ "${make_output}" != *"-C ./langfuse-demos/app js-check"* ]]
  rm -rf "${temp_app}"
}

@test "apps Makefile tests share wrapper delegation helpers" {
  run uv run --isolated python - <<PY
from pathlib import Path

from tests.app_contracts import app_wrapper_names_with_target, apps_makefile_delegation_contract_violations, apps_makefile_wrapper_dir_function_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "apps-makefile.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "apps wrapper delegation policy should move" not in line
]

assert callable(app_wrapper_names_with_target)
assert callable(apps_makefile_delegation_contract_violations)
assert callable(apps_makefile_wrapper_dir_function_contract_violations)
assert "apps_makefile_delegation_contract_violations" in content
assert "apps_makefile_wrapper_dir_function_contract_violations" in content
assert not any("find . -mindepth 2 -maxdepth 2 -path" in line for line in contract_lines), "apps wrapper delegation policy should move to tests/app_contracts.py"
assert not any("grep -q '^app-js-check:'" in line for line in contract_lines), "apps wrapper delegation policy should move to tests/app_contracts.py"
assert not any("grep -q '^app-test:'" in line for line in contract_lines), "apps wrapper delegation policy should move to tests/app_contracts.py"
assert not any("grep -q '^compose-smoke:'" in line for line in contract_lines), "apps wrapper delegation policy should move to tests/app_contracts.py"
assert not any("grep -q '^update:'" in line for line in contract_lines), "apps wrapper delegation policy should move to tests/app_contracts.py"
assert not any("dirname \"${makefile}\" | sed" in line for line in contract_lines), "apps wrapper delegation policy should move to tests/app_contracts.py"

print("validated shared apps Makefile delegation helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared apps Makefile delegation helper usage"* ]]
}

@test "apps Makefile shares wrapper target discovery" {
  run uv run --isolated python - <<PY
from pathlib import Path

from tests.app_contracts import apps_makefile_wrapper_dir_function_contract_violations

violations = apps_makefile_wrapper_dir_function_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared apps Makefile wrapper target discovery")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared apps Makefile wrapper target discovery"* ]]
}

@test "apps Makefile exposes canonical shared app module targets" {
  run uv run --isolated python - <<PY
from pathlib import Path

from tests.app_contracts import apps_makefile_shared_module_target_contract_violations

violations = apps_makefile_shared_module_target_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated apps Makefile shared module targets")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated apps Makefile shared module targets"* ]]
}

@test "apps Makefile tests share canonical shared module target helpers" {
  run uv run --isolated python - <<PY
from pathlib import Path

from tests.app_contracts import (
    apps_makefile_shared_module_target_contract_violations,
    canonical_shared_app_module_names,
)

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "apps-makefile.bats").read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "apps Makefile exposes canonical shared app module targets"'):
    content.index('\n@test "apps compose-smoke delegates to app wrapper compose smoke checks"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "apps shared module target policy should move" not in line
]

assert callable(apps_makefile_shared_module_target_contract_violations)
assert callable(canonical_shared_app_module_names)
assert "apps_makefile_shared_module_target_contract_violations" in test_body
assert "canonical_shared_app_module_names" in test_body
assert not any("shared-apphttp-test" in line for line in contract_lines), "apps shared module target policy should move to tests/app_contracts.py"
assert not any("shared/idpauth" in line for line in contract_lines), "apps shared module target policy should move to tests/app_contracts.py"

print("validated shared apps Makefile shared module target helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared apps Makefile shared module target helper usage"* ]]
}

@test "apps compose-smoke delegates to app wrapper compose smoke checks" {
  temp_app="${REPO_ROOT}/apps/zz-test-compose-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}"
  printf '%s\n' \
    'MAKE_KNOWN_GOALS := compose-smoke' \
    '.PHONY: compose-smoke' \
    'compose-smoke:' \
    '	@echo compose wrapper' \
    >"${temp_app}/Makefile"

  run make -n -C "${REPO_ROOT}/apps" compose-smoke

  [ "${status}" -eq 0 ]
  local make_output="${output}"
  run env MAKE_OUTPUT="${make_output}" uv run --isolated python - <<PY
from pathlib import Path
import os

from tests.app_contracts import apps_makefile_delegation_contract_violations

violations = apps_makefile_delegation_contract_violations(
    Path("${REPO_ROOT}"),
    os.environ["MAKE_OUTPUT"],
    wrapper_target="compose-smoke",
    delegated_target="compose-smoke",
)
assert not violations, violations
print("validated apps compose-smoke wrapper delegation")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated apps compose-smoke wrapper delegation"* ]]
  [[ "${make_output}" != *"./chatgpt-sim/tests/compose-smoke.sh"* ]]
  [[ "${make_output}" != *"./sentiment/tests/compose-smoke.sh"* ]]
  rm -rf "${temp_app}"
}

@test "apps dynamic compose-smoke app target delegates to matching wrapper" {
  temp_app="${REPO_ROOT}/apps/zz-test-compose-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}"
  printf '%s\n' \
    'MAKE_KNOWN_GOALS := compose-smoke' \
    '.PHONY: compose-smoke' \
    'compose-smoke:' \
    '	@echo compose wrapper' \
    >"${temp_app}/Makefile"

  run make -C "${REPO_ROOT}/apps" compose-smoke-zz-test-compose-wrapper

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"compose wrapper"* ]]
  rm -rf "${temp_app}"
}

@test "apps per-app test targets delegate to app wrapper unit checks" {
  run uv run --isolated python - <<PY
from pathlib import Path
import subprocess

from tests.app_contracts import app_wrapper_names_with_target, apps_makefile_delegation_contract_violations

repo = Path("${REPO_ROOT}")
validated = []

for app_name in app_wrapper_names_with_target(repo, "app-test"):
    target = f"{app_name}-test"
    result = subprocess.run(
        ["make", "-n", "-C", str(repo / "apps"), target],
        check=True,
        capture_output=True,
        text=True,
    )
    violations = apps_makefile_delegation_contract_violations(
        repo,
        result.stdout,
        wrapper_target="app-test",
        delegated_target="app-test",
        app_names=(app_name,),
    )
    assert not violations, violations
    assert f"-C ./{app_name}/app test" not in result.stdout
    validated.append(target)

assert validated
print(f"validated {len(validated)} app-specific test target delegation(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-specific test target delegation(s)"* ]]
}

@test "apps update delegates to each app root update workflow" {
  temp_app="${REPO_ROOT}/apps/zz-test-update-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}"
  printf '%s\n' \
    'MAKE_KNOWN_GOALS := update' \
    '.PHONY: update' \
    'update:' \
    '	@echo update test wrapper' \
    >"${temp_app}/Makefile"

  run make -n -C "${REPO_ROOT}/apps" update

  [ "${status}" -eq 0 ]
  local make_output="${output}"
  run env MAKE_OUTPUT="${make_output}" uv run --isolated python - <<PY
from pathlib import Path
import os

from tests.app_contracts import apps_makefile_delegation_contract_violations

violations = apps_makefile_delegation_contract_violations(
    Path("${REPO_ROOT}"),
    os.environ["MAKE_OUTPUT"],
    wrapper_target="update",
    delegated_target="update",
)
assert not violations, violations
print("validated apps update wrapper delegation")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated apps update wrapper delegation"* ]]
  rm -rf "${temp_app}"
}

@test "apps wrapper target discovery supports continued MAKE_KNOWN_GOALS declarations" {
  temp_app="${REPO_ROOT}/apps/zz-test-update-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}"
  printf '%s\n' \
    'MAKE_KNOWN_GOALS := help \' \
    '  update' \
    '.PHONY: update' \
    'update:' \
    '	@echo update test wrapper' \
    >"${temp_app}/Makefile"

  run make -n -C "${REPO_ROOT}/apps" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make --no-print-directory -C ./zz-test-update-wrapper update"* ]]
  rm -rf "${temp_app}"
}

@test "apps wrapper target discovery uses evaluated MAKE_KNOWN_GOALS additions" {
  temp_app="${REPO_ROOT}/apps/zz-test-update-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}"
  printf '%s\n' \
    'MAKE_KNOWN_GOALS := help' \
    'MAKE_KNOWN_GOALS += update' \
    '.PHONY: update' \
    'update:' \
    '	@echo update test wrapper' \
    >"${temp_app}/Makefile"

  run make -n -C "${REPO_ROOT}/apps" update

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"make --no-print-directory -C ./zz-test-update-wrapper update"* ]]
  rm -rf "${temp_app}"
}

@test "apps Makefile contract helpers use evaluated MAKE_KNOWN_GOALS additions" {
  temp_app="${REPO_ROOT}/apps/zz-test-app-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}"
  printf '%s\n' \
    'MAKE_KNOWN_GOALS := help' \
    'MAKE_KNOWN_GOALS += app-test' \
    '.PHONY: app-test' \
    'app-test:' \
    '	@echo app test wrapper' \
    >"${temp_app}/Makefile"

  run uv run --isolated python - <<PY
from pathlib import Path

from tests.app_contracts import app_wrapper_names_with_target

names = app_wrapper_names_with_target(Path("${REPO_ROOT}"), "app-test")
assert "zz-test-app-wrapper" in names, names
print("validated evaluated app wrapper target helper")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated evaluated app wrapper target helper"* ]]
  rm -rf "${temp_app}"
}
