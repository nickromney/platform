#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

teardown() {
  rm -rf "${REPO_ROOT}/apps/zz-test-shared-workflow"
  rm -rf "${REPO_ROOT}/apps/zz-test-common-wrapper"
}

@test "app layout tests share Go app discovery helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import iter_go_app_roots, iter_go_app_workflow_roots, iter_go_app_wrapper_roots

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "Go app root discovery should move" not in line
]

assert callable(iter_go_app_roots)
assert callable(iter_go_app_workflow_roots)
assert callable(iter_go_app_wrapper_roots)
assert "iter_go_app_workflow_roots" in content, "workflow layout contracts should call the shared app root iterator"
assert "iter_go_app_wrapper_roots" in content, "wrapper layout contracts should call the shared app root iterator"
assert not any('(repo / "apps").iterdir()' in line for line in contract_lines), "Go app root discovery should move to tests/app_contracts.py"

print("validated shared Go app discovery helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Go app discovery helper usage"* ]]
}

@test "app layout tests share canonical app expectation helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    canonical_go_app_names,
    canonical_local_app_layout_names,
    discovered_go_app_names,
    image_catalog_expectations,
)

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "canonical app expectations should move" not in line
]

assert canonical_go_app_names() == (
    "apim-simulator",
    "chatgpt-sim",
    "idp-core",
    "langfuse-demos",
    "platform-mcp",
    "sentiment",
    "subnetcalc",
)
assert canonical_go_app_names() == discovered_go_app_names(repo)
assert canonical_local_app_layout_names() == (
    "apim-simulator",
    "chatgpt-sim",
    "idp-core",
    "platform-mcp",
    "sentiment",
    "subnetcalc",
)
assert len(image_catalog_expectations()) == 9
assert "canonical_go_app_names" in content, "layout contracts should call the shared canonical app list"
assert "canonical_local_app_layout_names" in content, "layout contracts should call the shared local app layout list"
assert "discovered_go_app_names" in content, "Go app contracts should check the filesystem app list"
assert "image_catalog_expectations" in content, "image catalog contracts should call the shared image expectation list"
assert not any('"subnetcalc-apim-simulator"' in line for line in contract_lines), "canonical app expectations should move to tests/app_contracts.py"

print("validated shared canonical app expectation helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared canonical app expectation helper usage"* ]]
}

@test "app layout tests share shared-module workflow helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    go_app_shared_module_names,
    workflow_local_dockerfile_contract_violations,
    workflow_provides_shared_modules,
    workflow_uses_app_dockerfile,
    shared_module_source_paths_for_app,
)

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "shared module detection should ignore" not in line
    and "workflow copy detection should move" not in line
    and "workflow Dockerfile detection should move" not in line
]

assert callable(go_app_shared_module_names)
assert callable(workflow_provides_shared_modules)
assert callable(workflow_uses_app_dockerfile)
assert callable(workflow_local_dockerfile_contract_violations)
assert callable(shared_module_source_paths_for_app)
assert "go_app_shared_module_names" in content, "workflow contracts should use shared module detection"
assert "shared_module_source_paths_for_app" in content, "image catalog contracts should use shared module source path detection"
assert "workflow_provides_shared_modules" in content, "workflow contracts should use shared module copy detection"
assert "workflow_uses_app_dockerfile" in content, "workflow contracts should use app Dockerfile detection"
assert "workflow_local_dockerfile_contract_violations" in content, "workflow contracts should use local Dockerfile detection"
assert not any('"platform.local/" not in go_mod_content' in line for line in contract_lines), "shared module detection should ignore the module declaration"
assert not any("'\${APPS_DIR}/shared:/shared:ro' in workflow_content" in line for line in contract_lines), "workflow copy detection should move to tests/app_contracts.py"
assert not any('"Dockerfile.runtime" in workflow_content' in line for line in contract_lines), "workflow Dockerfile detection should move to tests/app_contracts.py"

print("validated shared-module workflow helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared-module workflow helper usage"* ]]
}

@test "app layout tests share Go module dependency helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import go_app_dependency_contract_violations, go_module_requirements

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "Go dependency contract should move" not in line
]

assert callable(go_module_requirements)
assert callable(go_app_dependency_contract_violations)
assert "go_module_requirements" in content, "module dependency contracts should parse go.mod through tests/app_contracts.py"
assert "go_app_dependency_contract_violations" in content, "module dependency contracts should call tests/app_contracts.py"
assert not any("allowed_external =" in line for line in contract_lines), "Go dependency contract should move to tests/app_contracts.py"
assert not any('"github.com/coreos/go-oidc/v3"' in line for line in contract_lines), "Go dependency contract should move to tests/app_contracts.py"
assert not any('"idpauth owns the direct OIDC dependency"' in line for line in contract_lines), "Go dependency contract should move to tests/app_contracts.py"

print("validated shared Go module dependency helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Go module dependency helper usage"* ]]
}

@test "Go apps use shared IDP auth env mapping" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import go_app_auth_env_contract_violations

violations = go_app_auth_env_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared Go app auth env helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Go app auth env helper usage"* ]]
}

@test "app layout tests share Go-first exception helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import non_go_app_exception_contract_violations

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "Go-first exception policy should move" not in line
]

assert callable(non_go_app_exception_contract_violations)
assert "non_go_app_exception_contract_violations" in content
assert not any('"idp-mcp", "idp-sdk"' in line for line in contract_lines), "Go-first exception policy should move to tests/app_contracts.py"
assert not any('"min-release-age=7"' in line for line in contract_lines), "Go-first exception policy should move to tests/app_contracts.py"
assert not any('"yarn@4.4.1"' in line for line in contract_lines), "Go-first exception policy should move to tests/app_contracts.py"

print("validated shared Go-first exception helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Go-first exception helper usage"* ]]
}

@test "app layout tests share wrapper Makefile contract helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import app_wrapper_contract_violations

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "wrapper Makefile contract should move" not in line
]

assert callable(app_wrapper_contract_violations)
assert "app_wrapper_contract_violations" in content, "wrapper contracts should call tests/app_contracts.py"
assert not any('"include ../../mk/common.mk" in content' in line for line in contract_lines), "wrapper Makefile contract should move to tests/app_contracts.py"
assert not any('"compose-smoke:" in content' in line for line in contract_lines), "wrapper Makefile contract should move to tests/app_contracts.py"

print("validated wrapper Makefile contract helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated wrapper Makefile contract helper usage"* ]]
}

@test "app layout tests share canonical app layout helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import app_layout_contract_violations

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "canonical app layout contract should move" not in line
]

assert callable(app_layout_contract_violations)
assert "app_layout_contract_violations" in content, "layout contracts should call tests/app_contracts.py"
assert not any('for child in [".gitea", "app", "tests", "compose.yml"]' in line for line in contract_lines), "canonical app layout contract should move to tests/app_contracts.py"
assert not any('"pyproject.toml", "uv.lock"' in line for line in contract_lines), "canonical app layout contract should move to tests/app_contracts.py"

print("validated canonical app layout contract helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated canonical app layout contract helper usage"* ]]
}

@test "app layout tests share image catalog contract helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import image_catalog_contract_violations, image_catalog_shared_source_contract_violations

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "image catalog contract should move" not in line
]

assert callable(image_catalog_contract_violations)
assert callable(image_catalog_shared_source_contract_violations)
assert "image_catalog_contract_violations" in content, "image catalog contracts should call tests/app_contracts.py"
assert "image_catalog_shared_source_contract_violations" in content, "shared source contracts should call tests/app_contracts.py"
assert not any('json.loads((repo / "kubernetes/workflow/image-catalog.json")' in line for line in contract_lines), "image catalog contract should move to tests/app_contracts.py"
assert not any('image.get("build", {}).get("context", "")' in line for line in contract_lines), "image catalog contract should move to tests/app_contracts.py"

print("validated image catalog contract helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated image catalog contract helper usage"* ]]
}

@test "in-scope Go apps expose the canonical app layout" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    app_layout_contract_violations,
    canonical_local_app_layout_names,
    shared_keycloak_fixture_contract_violations,
)

repo = Path("${REPO_ROOT}")
apps = canonical_local_app_layout_names()

for name in apps:
    root = repo / "apps" / name
    violations = app_layout_contract_violations(root)
    assert not violations, violations

violations = shared_keycloak_fixture_contract_violations(repo)
assert not violations, violations

print(f"validated {len(apps)} canonical Go app layout(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 6 canonical Go app layout(s)"* ]]
}

@test "app layout tests share Keycloak fixture helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_keycloak_fixture_contract_violations

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "in-scope Go apps expose the canonical app layout"'):
    content.index('\n@test "in-scope Go apps keep direct dependencies local and documented"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "shared Keycloak fixture policy should move" not in line
]

assert callable(shared_keycloak_fixture_contract_violations)
assert "shared_keycloak_fixture_contract_violations" in content
assert not any("../shared/keycloak/realm-export.json" in line for line in contract_lines), "shared Keycloak fixture policy should move to tests/app_contracts.py"
assert not any("start-with-templated-realm.sh" in line for line in contract_lines), "shared Keycloak fixture policy should move to tests/app_contracts.py"
assert not any('apps" / "shared" / "keycloak"' in line for line in contract_lines), "shared Keycloak fixture policy should move to tests/app_contracts.py"

print("validated shared Keycloak fixture helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Keycloak fixture helper usage"* ]]
}

@test "in-scope Go apps keep direct dependencies local and documented" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import canonical_go_app_names, discovered_go_app_names, go_app_dependency_contract_violations

repo = Path("${REPO_ROOT}")
assert canonical_go_app_names() == discovered_go_app_names(repo)
violations = go_app_dependency_contract_violations(repo)
assert not violations, violations

print(f"validated {len(canonical_go_app_names())} minimal Go app dependency contract(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 7 minimal Go app dependency contract(s)"* ]]
}

@test "Platform MCP config uses shared apphttp env parsing" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import platform_mcp_config_env_contract_violations

repo = Path("${REPO_ROOT}")
violations = platform_mcp_config_env_contract_violations(repo)
assert not violations, violations

print("validated Platform MCP shared env parsing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Platform MCP shared env parsing"* ]]
}

@test "Langfuse demos config uses shared apphttp env parsing" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import langfuse_demos_config_env_contract_violations

repo = Path("${REPO_ROOT}")
violations = langfuse_demos_config_env_contract_violations(repo)
assert not violations, violations

print("validated Langfuse demos shared env parsing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Langfuse demos shared env parsing"* ]]
}

@test "ChatGPT Sim config uses shared apphttp env parsing" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import chatgpt_sim_config_env_contract_violations

repo = Path("${REPO_ROOT}")
violations = chatgpt_sim_config_env_contract_violations(repo)
assert not violations, violations

print("validated ChatGPT Sim shared env parsing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated ChatGPT Sim shared env parsing"* ]]
}

@test "APIM Simulator config uses shared apphttp env parsing" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import apim_simulator_config_env_contract_violations

repo = Path("${REPO_ROOT}")
violations = apim_simulator_config_env_contract_violations(repo)
assert not violations, violations

print("validated APIM Simulator shared env parsing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated APIM Simulator shared env parsing"* ]]
}

@test "non-Go app roots remain documented Go-first exceptions" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import non_go_app_exception_contract_violations

repo = Path("${REPO_ROOT}")
violations = non_go_app_exception_contract_violations(repo)
assert not violations, violations

print("validated 3 documented Go-first app exception(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 3 documented Go-first app exception(s)"* ]]
}

@test "in-scope Go app image catalog entries point at canonical app directories" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    image_catalog_contract_violations,
    image_catalog_expectations,
    image_catalog_shared_source_contract_violations,
)

repo = Path("${REPO_ROOT}")
violations = (
    image_catalog_contract_violations(repo)
    + image_catalog_shared_source_contract_violations(repo)
)
assert not violations, violations

print(f"validated {len(image_catalog_expectations())} canonical image catalog entry and shared source contract(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 9 canonical image catalog entry and shared source contract(s)"* ]]
}

@test "in-scope Go app workflows include shared modules when their go.mod uses them" {
  temp_app="${REPO_ROOT}/apps/zz-test-shared-workflow"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app" "${temp_app}/.gitea/workflows"
  cat >"${temp_app}/app/go.mod" <<'EOF'
module platform.local/zz-test-shared-workflow

go 1.26

require platform.local/apphttp v0.0.0

replace platform.local/apphttp => ../../shared/apphttp
EOF
  cat >"${temp_app}/.gitea/workflows/build-images.yaml" <<'EOF'
on:
  push:
    paths:
      - "app/**"
      - "shared/**"
jobs:
  build:
    runs-on: [self-hosted, in-cluster]
    steps:
      - run: echo "${APPS_DIR}/shared:/shared:ro"
EOF

run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    shared_module_workflow_contract_violations,
    shared_module_workflow_validated_apps,
)

repo = Path("${REPO_ROOT}")
violations = shared_module_workflow_contract_violations(repo)
assert not violations, violations
validated = shared_module_workflow_validated_apps(repo)

print(f"validated {len(validated)} shared-module workflow contract(s): {', '.join(validated)}")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"zz-test-shared-workflow"* ]]
}

@test "app layout tests share shared-module workflow contract helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_module_workflow_contract_violations

repo = Path("${REPO_ROOT}")
test_file = repo / "tests" / "app-layout-consistency.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "in-scope Go app workflows include shared modules when their go.mod uses them"'):
    content.index('\n@test "in-scope Go app workflows use app-owned Dockerfiles"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "shared-module workflow policy should move" not in line
]

assert callable(shared_module_workflow_contract_violations)
assert "shared_module_workflow_contract_violations" in content
assert not any("go_app_shared_module_names" in line for line in contract_lines), "shared-module workflow policy should move to tests/app_contracts.py"
assert not any("iter_go_app_workflow_roots" in line for line in contract_lines), "shared-module workflow policy should move to tests/app_contracts.py"
assert not any("workflow_provides_shared_modules" in line for line in contract_lines), "shared-module workflow policy should move to tests/app_contracts.py"
assert not any('workflow_content = workflow.read_text' in line for line in contract_lines), "shared-module workflow policy should move to tests/app_contracts.py"

print("validated shared shared-module workflow contract helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared shared-module workflow contract helper usage"* ]]
}

@test "in-scope Go app workflows use app-owned Dockerfiles" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import workflow_local_dockerfile_contract_violations

violations = workflow_local_dockerfile_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated app workflow Dockerfile ownership")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated app workflow Dockerfile ownership"* ]]
}

@test "in-scope Go app wrappers share the common Makefile interface" {
  temp_app="${REPO_ROOT}/apps/zz-test-common-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/Makefile" <<'EOF'
MAKE_KNOWN_GOALS := help
MAKE_KNOWN_GOALS += app-prereqs

include ../../mk/app-common.mk

app-prereqs:
	@echo ok
EOF
  touch "${temp_app}/app/go.mod"

run python3 - <<PY
from pathlib import Path

from tests.app_contracts import app_wrapper_contract_violations, iter_go_app_wrapper_roots

repo = Path("${REPO_ROOT}")
apps = [app_root.name for app_root in iter_go_app_wrapper_roots(repo)]

for name in apps:
    violations = app_wrapper_contract_violations(repo / "apps" / name)
    assert not violations, violations

print(f"validated {len(apps)} common app wrapper interface(s): {', '.join(apps)}")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"zz-test-common-wrapper"* ]]
}

@test "common app wrapper exposes only declared non-compose targets" {
  temp_app="${REPO_ROOT}/apps/zz-test-common-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/Makefile" <<'EOF'
MAKE_KNOWN_GOALS := help app-prereqs

include ../../mk/app-common.mk

app-prereqs: ## Check local app prerequisites
	@echo ok
EOF
  touch "${temp_app}/app/go.mod"

  run make -C "${temp_app}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-prereqs"* ]]
  [[ "${output}" != *"update"* ]]

  run make -C "${temp_app}" update

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown make goal 'update'."* ]]
}

@test "common app wrapper delegates declared app core targets" {
  temp_app="${REPO_ROOT}/apps/zz-test-common-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/Makefile" <<'EOF'
MAKE_KNOWN_GOALS := help app-help app-test app-js-check app-build

include ../../mk/app-common.mk
EOF
  cat >"${temp_app}/app/Makefile" <<'EOF'
.PHONY: help test js-check build
help:
	@echo app-help-delegated
test:
	@echo app-test-delegated
js-check:
	@echo app-js-check-delegated
build:
	@echo app-build-delegated
EOF

  run make -C "${temp_app}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-help"* ]]
  [[ "${output}" == *"app-test"* ]]
  [[ "${output}" == *"app-js-check"* ]]
  [[ "${output}" == *"app-build"* ]]

  run make -C "${temp_app}" app-help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-help-delegated"* ]]

  run make -C "${temp_app}" app-test

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-test-delegated"* ]]

  run make -C "${temp_app}" app-js-check

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-js-check-delegated"* ]]

  run make -C "${temp_app}" app-build

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"app-build-delegated"* ]]
}

@test "common app wrapper exposes only declared compose lifecycle targets" {
  temp_app="${REPO_ROOT}/apps/zz-test-common-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/compose.yml" <<'EOF'
services: {}
EOF
  cat >"${temp_app}/Makefile" <<'EOF'
MAKE_KNOWN_GOALS := help prereqs

include ../../mk/app-common.mk
EOF
  touch "${temp_app}/app/go.mod"

  run make -C "${temp_app}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"prereqs"* ]]
  [[ "${output}" != *"compose-smoke"* ]]
  [[ "${output}" != *"down"* ]]
  [[ "${output}" != *"logs"* ]]
  [[ "${output}" != *"ps"* ]]

  run make -C "${temp_app}" down

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown make goal 'down'."* ]]
}

@test "common app compose lifecycle targets use private prerequisites when prereqs is undeclared" {
  temp_app="${REPO_ROOT}/apps/zz-test-common-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/compose.yml" <<'EOF'
services: {}
EOF
  cat >"${temp_app}/Makefile" <<'EOF'
MAKE_KNOWN_GOALS := help down

include ../../mk/app-common.mk
EOF
  touch "${temp_app}/app/go.mod"

  run make -C "${temp_app}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"down"* ]]
  [[ "${output}" != *"prereqs"* ]]

  run make -n -C "${temp_app}" down COMPOSE_CMD=true PLATFORM_ENV_FILE="${REPO_ROOT}/.env.example" PLATFORM_ENV_TEMPLATE="${REPO_ROOT}/.env.example"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"Unknown make goal 'prereqs'."* ]]
  [[ "${output}" == *"check-platform-env"* ]]
  [[ "${output}" == *"true  down --remove-orphans"* ]]
}

@test "common app wrapper does not turn declared missing goals into empty successes" {
  temp_app="${REPO_ROOT}/apps/zz-test-common-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/Makefile" <<'EOF'
MAKE_KNOWN_GOALS := help missing-real-target

include ../../mk/app-common.mk
EOF
  touch "${temp_app}/app/go.mod"

  run make -C "${temp_app}" missing-real-target

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown make goal 'missing-real-target'."* ]]
}

@test "common app wrapper rejects public rules that are not declared goals" {
  temp_app="${REPO_ROOT}/apps/zz-test-common-wrapper"
  rm -rf "${temp_app}"
  mkdir -p "${temp_app}/app"
  cat >"${temp_app}/Makefile" <<'EOF'
MAKE_KNOWN_GOALS := help

include ../../mk/app-common.mk

leaked-target: ## Leaked target
	@echo leaked
EOF
  touch "${temp_app}/app/go.mod"

  run make -C "${temp_app}" help

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"leaked-target"* ]]

  run make -C "${temp_app}" leaked-target

  [ "${status}" -eq 2 ]
  [[ "${output}" == *"Unknown make goal 'leaked-target'."* ]]
}
