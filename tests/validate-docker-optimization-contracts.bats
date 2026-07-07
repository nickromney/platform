#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

assert_file_contains() {
  local relative_path="$1"
  local expected="$2"

  run grep -Fq -- "${expected}" "${REPO_ROOT}/${relative_path}"
  [ "${status}" -eq 0 ] || {
    echo "${relative_path} must contain: ${expected}"
    return 1
  }
}

assert_file_matches() {
  local relative_path="$1"
  local expected_regex="$2"

  run grep -Eq -- "${expected_regex}" "${REPO_ROOT}/${relative_path}"
  [ "${status}" -eq 0 ] || {
    echo "${relative_path} must match: ${expected_regex}"
    return 1
  }
}

assert_file_omits_ci() {
  local relative_path="$1"
  local forbidden="$2"

  run grep -Eiq -- "${forbidden}" "${REPO_ROOT}/${relative_path}"
  [ "${status}" -ne 0 ] || {
    echo "${relative_path} must not contain case-insensitive match: ${forbidden}"
    return 1
  }
}

assert_image_source() {
  local image_id="$1"
  local source="$2"

  run jq -e \
    --arg image_id "${image_id}" \
    --arg source "${source}" \
    '(.platform_images + .workload_images) | any(.[]; .id == $image_id and ((.fingerprint_sources // []) | index($source)))' \
    "${REPO_ROOT}/kubernetes/workflow/image-catalog.json"
  [ "${status}" -eq 0 ] || {
    echo "${image_id} fingerprint must include ${source}"
    return 1
  }
}

@test "subnetcalc Go runtime image stays package-manager-free" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import go_app_dockerfile_runtime_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_dockerfile_runtime_contract_violations(repo_root)
assert not violations, violations

print("validated package-manager-free subnetcalc Go runtime image")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated package-manager-free subnetcalc Go runtime image"* ]]
}

@test "APIM simulator image follows the Go single-binary runtime contract" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import go_app_dockerfile_runtime_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_dockerfile_runtime_contract_violations(repo_root)
assert not violations, violations
print("validated APIM simulator Go single-binary runtime contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated APIM simulator Go single-binary runtime contract"* ]]
}

@test "lightweight Go app images avoid package manager runtimes" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import go_app_dockerfile_runtime_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_dockerfile_runtime_contract_violations(repo_root)
assert not violations, violations
print("validated lightweight Go app package-manager-free runtime contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated lightweight Go app package-manager-free runtime contract"* ]]
}

@test "local Go app runtime binaries are owned by the non-root runtime user" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import go_app_dockerfile_runtime_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_dockerfile_runtime_contract_violations(repo_root)
assert not violations, violations
print("validated local Go app runtime binary ownership contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go app runtime binary ownership contract"* ]]
}

@test "local Go app runtime images use writable temp home for the non-root user" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import go_app_dockerfile_runtime_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_dockerfile_runtime_contract_violations(repo_root)
assert not violations, violations
print("validated local Go app runtime writable temp home contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go app runtime writable temp home contract"* ]]
}

@test "docker optimization tests share Go app Dockerfile runtime helpers" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import go_app_dockerfile_runtime_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-docker-optimization-contracts.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "subnetcalc Go runtime image stays package-manager-free"'):
    content.index('\n@test "local Go app Makefiles create their binary output directory"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "Go app Dockerfile runtime policy should move" not in line
]

assert callable(go_app_dockerfile_runtime_contract_violations)
assert (
    "go_app_dockerfile_runtime_contract_violations" in content
), "Go app Dockerfile runtime contracts should call tests/app_contracts.py"
assert not any("apps/apim-simulator/app/Dockerfile" in line for line in contract_lines), "Go app Dockerfile runtime policy should move to tests/app_contracts.py"
assert not any("COPY --chown=65532:65532" in line for line in contract_lines), "Go app Dockerfile runtime policy should move to tests/app_contracts.py"
assert not any("ENTRYPOINT" in line for line in contract_lines), "Go app Dockerfile runtime policy should move to tests/app_contracts.py"
assert not any("HOME=/tmp" in line for line in contract_lines), "Go app Dockerfile runtime policy should move to tests/app_contracts.py"

print("validated shared Go app Dockerfile runtime helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Go app Dockerfile runtime helper usage"* ]]
}

@test "local Go app Makefiles create their binary output directory" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import go_app_makefile_workflow_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_makefile_workflow_contract_violations(repo_root)
assert not violations, violations
print("validated local Go app Makefile workflow contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go app Makefile workflow contract"* ]]
}

@test "local Go app Makefiles build trimmed stripped binaries by default" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import go_app_makefile_workflow_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_makefile_workflow_contract_violations(repo_root)
assert not violations, violations
print("validated local Go app Makefile optimized build contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go app Makefile optimized build contract"* ]]
}

@test "local Go app Makefiles share the Linux binary build contract" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import go_app_makefile_build_linux_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_makefile_build_linux_contract_violations(repo_root)
assert not violations, violations
print("validated local Go app Makefile build-linux contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go app Makefile build-linux contract"* ]]
}

@test "local Go app Makefiles expose help for focused workflows" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import go_app_makefile_workflow_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_makefile_workflow_contract_violations(repo_root)
assert not violations, violations
print("validated local Go app Makefile focused help contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go app Makefile focused help contract"* ]]
}

@test "local Go app Makefiles expose clean for generated run artifacts" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import go_app_makefile_workflow_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_makefile_workflow_contract_violations(repo_root)
assert not violations, violations
print("validated local Go app Makefile clean contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go app Makefile clean contract"* ]]
}

@test "local Go app Makefiles share common Go app core module" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import go_app_core_makefile_module_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = go_app_core_makefile_module_contract_violations(repo_root)
assert not violations, violations
print("validated local Go app Makefile shared core module contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go app Makefile shared core module contract"* ]]
}

@test "docker optimization tests share local Go app Makefile workflow helpers" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import go_app_makefile_workflow_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-docker-optimization-contracts.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "local Go app Makefiles create their binary output directory"'):
    content.index('\n@test "shared app module Makefiles expose focused help"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "local Go app Makefile workflow policy should move" not in line
]

assert callable(go_app_makefile_workflow_contract_violations)
assert (
    "go_app_makefile_workflow_contract_violations" in content
), "local Go app Makefile workflow contracts should call tests/app_contracts.py"
assert not any("apps/apim-simulator/app/Makefile" in line for line in contract_lines), "local Go app Makefile workflow policy should move to tests/app_contracts.py"
assert not any("apps/subnetcalc/app/Makefile" in line for line in contract_lines), "local Go app Makefile workflow policy should move to tests/app_contracts.py"
assert not any("APIM Simulator app:" in line for line in contract_lines), "local Go app Makefile workflow policy should move to tests/app_contracts.py"
assert not any("rm -rf \\.run" in line for line in contract_lines), "local Go app Makefile workflow policy should move to tests/app_contracts.py"

print("validated shared local Go app Makefile workflow helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared local Go app Makefile workflow helper usage"* ]]
}

@test "shared app module Makefiles expose focused help" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import (
    canonical_shared_app_module_names,
    shared_app_module_makefile_contract_violations,
)

repo_root = Path(os.environ["REPO_ROOT"])
violations = shared_app_module_makefile_contract_violations(repo_root)
assert not violations, violations

print("validated shared app module Makefile focused help")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app module Makefile focused help"* ]]
}

@test "shared app module Makefiles share common Go module workflow" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import shared_app_module_makefile_module_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = shared_app_module_makefile_module_contract_violations(repo_root)
assert not violations, violations

print("validated shared app module Makefile common Go module workflow")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app module Makefile common Go module workflow"* ]]
}

@test "docker optimization tests share shared app module Makefile helpers" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import (
    canonical_shared_app_module_names,
    shared_app_module_makefile_contract_violations,
)

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-docker-optimization-contracts.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "shared app module Makefiles expose focused help"'):
    content.index('\n@test "browser app js-check targets cover shipped vanilla web assets"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "shared app module Makefile policy should move" not in line
]

assert callable(shared_app_module_makefile_contract_violations)
assert callable(canonical_shared_app_module_names)
assert "shared_app_module_makefile_contract_violations" in test_body
assert "canonical_shared_app_module_names" in test_body
assert not any("assert_file_matches" in line for line in contract_lines), "shared app module Makefile policy should move to tests/app_contracts.py"
assert not any("apps/shared/appshell/Makefile" in line for line in contract_lines), "shared app module Makefile policy should move to tests/app_contracts.py"
assert not any("apps/shared/idpauth/Makefile" in line for line in contract_lines), "shared app module Makefile policy should move to tests/app_contracts.py"

print("validated shared app module Makefile helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app module Makefile helper usage"* ]]
}

@test "browser app js-check targets cover shipped vanilla web assets" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import browser_app_js_check_asset_contract_violations

repo_root = Path.cwd()
violations = browser_app_js_check_asset_contract_violations(repo_root)
assert not violations, violations

print("validated browser app js-check coverage for shipped vanilla web assets")
PY

	[ "$status" -eq 0 ]
	[[ "${output}" == *"validated browser app js-check coverage for shipped vanilla web assets"* ]]
}

@test "docker optimization tests share browser app js-check asset helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import browser_app_js_check_asset_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "browser app js-check targets cover shipped vanilla web assets"'):
    content.index('\n@test "local Go app commands use the shared hardened HTTP server helper"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "browser app js-check asset policy should move" not in line
]

assert callable(browser_app_js_check_asset_contract_violations)
assert (
    "browser_app_js_check_asset_contract_violations" in content
), "browser app js-check asset contracts should call tests/app_contracts.py"
assert not any('Path("apps/apim-simulator/app")' in line for line in contract_lines), "browser app js-check asset policy should move to tests/app_contracts.py"
assert not any('"internal/app/web"' in line for line in contract_lines), "browser app js-check asset policy should move to tests/app_contracts.py"
assert not any('path.suffix in {".js", ".css", ".html", ".ts"}' in line for line in contract_lines), "browser app js-check asset policy should move to tests/app_contracts.py"

print("validated shared browser app js-check asset helper usage")
PY

	[ "$status" -eq 0 ]
	[[ "${output}" == *"validated shared browser app js-check asset helper usage"* ]]
}

@test "local Go app commands use the shared hardened HTTP server helper" {
	run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import hardened_go_command_http_contract_violations

violations = hardened_go_command_http_contract_violations(Path.cwd())
assert not violations, violations

print("validated shared hardened HTTP server and healthcheck helper usage")
PY

	[ "$status" -eq 0 ]
	[[ "${output}" == *"validated shared hardened HTTP server and healthcheck helper usage"* ]]
}

@test "Go apps decode upstream JSON through shared apphttp helper" {
	run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import go_app_upstream_json_decode_contract_violations

violations = go_app_upstream_json_decode_contract_violations(Path.cwd())
assert not violations, violations

print("validated shared upstream JSON decode helper usage")
PY

	[ "$status" -eq 0 ]
	[[ "${output}" == *"validated shared upstream JSON decode helper usage"* ]]
}

@test "docker optimization tests share hardened Go command HTTP helpers" {
	run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import hardened_go_command_http_contract_violations, go_app_upstream_json_decode_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "local Go app commands use the shared hardened HTTP server helper"'):
    content.index('\n@test "compose files harden additional subnetcalc runtime services"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "hardened Go command HTTP policy should move" not in line
]

assert callable(hardened_go_command_http_contract_violations)
assert callable(go_app_upstream_json_decode_contract_violations)
assert (
    "hardened_go_command_http_contract_violations" in content
), "hardened Go command HTTP contracts should call tests/app_contracts.py"
assert (
    "go_app_upstream_json_decode_contract_violations" in content
), "upstream JSON decode contracts should call tests/app_contracts.py"
assert not any('Path("apps").glob("*/app/cmd/*/main.go")' in line for line in contract_lines), "hardened Go command HTTP policy should move to tests/app_contracts.py"
assert not any('"http.ListenAndServe("' in line for line in contract_lines), "hardened Go command HTTP policy should move to tests/app_contracts.py"
assert not any('"func CheckLocalHealth("' in line for line in contract_lines), "hardened Go command HTTP policy should move to tests/app_contracts.py"

print("validated shared hardened Go command HTTP helper usage")
PY

	[ "$status" -eq 0 ]
	[[ "${output}" == *"validated shared hardened Go command HTTP helper usage"* ]]
}

@test "compose files harden additional subnetcalc runtime services" {
	run python3 - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import (
    additional_subnetcalc_compose_hardening_contract_violations,
    additional_subnetcalc_compose_hardening_validated_services,
)

repo_root = Path(os.environ["REPO_ROOT"])
violations = additional_subnetcalc_compose_hardening_contract_violations(repo_root)
assert not violations, violations
validated = additional_subnetcalc_compose_hardening_validated_services()

print(f"validated {len(validated)} hardened compose service(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 7 hardened compose service(s)"* ]]
}

@test "docker optimization tests share additional subnetcalc compose hardening helpers" {
	run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import additional_subnetcalc_compose_hardening_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "compose files harden additional subnetcalc runtime services"'):
    content.index('\n@test "docker build audit script captures logs sizes and warnings"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "additional subnetcalc compose hardening policy should move" not in line
]

assert callable(additional_subnetcalc_compose_hardening_contract_violations)
assert "additional_subnetcalc_compose_hardening_contract_violations" in content
assert not any("nginx_tmpfs =" in line for line in contract_lines), "additional subnetcalc compose hardening policy should move to tests/app_contracts.py"
assert not any("app_tmpfs =" in line for line in contract_lines), "additional subnetcalc compose hardening policy should move to tests/app_contracts.py"
assert not any("yaml.safe_load" in line for line in contract_lines), "additional subnetcalc compose hardening policy should move to tests/app_contracts.py"
assert not any("subnetcalc-api-dev" in line for line in contract_lines), "additional subnetcalc compose hardening policy should move to tests/app_contracts.py"
assert not any("read_only" in line and "service.get" in line for line in contract_lines), "additional subnetcalc compose hardening policy should move to tests/app_contracts.py"

print("validated shared additional subnetcalc compose hardening helper usage")
PY

	[ "$status" -eq 0 ]
	[[ "${output}" == *"validated shared additional subnetcalc compose hardening helper usage"* ]]
}

@test "docker build audit script captures logs sizes and warnings" {
  run python3 - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import docker_build_audit_tooling_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = docker_build_audit_tooling_contract_violations(repo_root)
assert not violations, violations

print("validated docker build audit tooling contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated docker build audit tooling contract"* ]]
}

@test "docker optimization tests share docker build audit tooling helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import docker_build_audit_tooling_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "docker build audit script captures logs sizes and warnings"'):
    content.index('\n@test "grafana plugin image build uses a host-verified archive instead of downloading in Dockerfile"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "docker build audit tooling policy should move" not in line
]

assert callable(docker_build_audit_tooling_contract_violations)
assert "docker_build_audit_tooling_contract_violations" in content
assert not any("required_fragments =" in line for line in contract_lines), "docker build audit tooling policy should move to tests/app_contracts.py"
assert not any("--progress=plain" in line for line in contract_lines), "docker build audit tooling policy should move to tests/app_contracts.py"
assert not any("docker image inspect" in line for line in contract_lines), "docker build audit tooling policy should move to tests/app_contracts.py"
assert not any("apps/subnetcalc/app/Dockerfile" in line for line in contract_lines), "docker build audit tooling policy should move to tests/app_contracts.py"

print("validated shared docker build audit tooling helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared docker build audit tooling helper usage"* ]]
}

@test "grafana plugin image build uses a host-verified archive instead of downloading in Dockerfile" {
  run python3 - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import grafana_plugin_archive_mirroring_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = grafana_plugin_archive_mirroring_contract_violations(repo_root)
assert not violations, violations

print("validated grafana plugin archive mirroring contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated grafana plugin archive mirroring contract"* ]]
}

@test "docker optimization tests share grafana plugin archive mirroring helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import grafana_plugin_archive_mirroring_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "grafana plugin image build uses a host-verified archive instead of downloading in Dockerfile"'):
    content.index('\n@test "local platform image build and sync contracts include IDP images"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "grafana plugin archive mirroring policy should move" not in line
]

assert callable(grafana_plugin_archive_mirroring_contract_violations)
assert "grafana_plugin_archive_mirroring_contract_violations" in content
assert not any("grafana-victorialogs/Dockerfile" in line for line in contract_lines), "grafana plugin archive mirroring policy should move to tests/app_contracts.py"
assert not any("grafana_victoria_logs_plugin_sha256" in line for line in contract_lines), "grafana plugin archive mirroring policy should move to tests/app_contracts.py"
assert not any("curl -fsSL" in line for line in contract_lines), "grafana plugin archive mirroring policy should move to tests/app_contracts.py"
assert not any("victorialogs.zip" in line for line in contract_lines), "grafana plugin archive mirroring policy should move to tests/app_contracts.py"

print("validated shared grafana plugin archive mirroring helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared grafana plugin archive mirroring helper usage"* ]]
}

@test "local platform image build and sync contracts include IDP images" {
  run python3 - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

from tests.app_contracts import local_platform_image_sync_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = local_platform_image_sync_contract_violations(repo_root)
assert not violations, violations

print("validated local platform IDP image build and sync contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local platform IDP image build and sync contract"* ]]
}

@test "docker optimization tests share local platform image sync helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import local_platform_image_sync_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "local platform image build and sync contracts include IDP images"'):
    content.index('\n@test "local platform IDP image cache keys include source fingerprints"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "local platform image sync policy should move" not in line
]

assert callable(local_platform_image_sync_contract_violations)
assert "local_platform_image_sync_contract_violations" in content
assert not any("sync-gitea-policies.sh" in line for line in contract_lines), "local platform image sync policy should move to tests/app_contracts.py"
assert not any("EXTERNAL_PLATFORM_IMAGE_BACKSTAGE" in line for line in contract_lines), "local platform image sync policy should move to tests/app_contracts.py"
assert not any("external_platform_idp_core" in line for line in contract_lines), "local platform image sync policy should move to tests/app_contracts.py"
assert not any("GITEA_SYNC_TARGET_TFVARS_FILE" in line for line in contract_lines), "local platform image sync policy should move to tests/app_contracts.py"

print("validated shared local platform image sync helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared local platform image sync helper usage"* ]]
}

@test "local platform IDP image cache keys include source fingerprints" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import local_platform_source_fingerprint_cache_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = local_platform_source_fingerprint_cache_contract_violations(repo_root)
assert not violations, violations

print("validated local platform IDP source fingerprint cache keys")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local platform IDP source fingerprint cache keys"* ]]
}

@test "docker optimization tests share local platform source fingerprint cache helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import local_platform_source_fingerprint_cache_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "local platform IDP image cache keys include source fingerprints"'):
    content.index('\n@test "local Go workload image cache keys include embedded frontend sources"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "local platform source fingerprint cache policy should move" not in line
]

assert callable(local_platform_source_fingerprint_cache_contract_violations)
assert "local_platform_source_fingerprint_cache_contract_violations" in content
assert not any("source_fingerprint_tag()" in line for line in contract_lines), "local platform source fingerprint cache policy should move to tests/app_contracts.py"
assert not any("idp_core_source_tag=" in line for line in contract_lines), "local platform source fingerprint cache policy should move to tests/app_contracts.py"
assert not any("image_catalog_source_tag platform" in line for line in contract_lines), "local platform source fingerprint cache policy should move to tests/app_contracts.py"
assert not any("apps/platform-mcp/app/internal" in line for line in contract_lines), "local platform source fingerprint cache policy should move to tests/app_contracts.py"

print("validated shared local platform source fingerprint cache helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared local platform source fingerprint cache helper usage"* ]]
}

@test "local Go workload image cache keys include embedded frontend sources" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import local_go_workload_source_fingerprint_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = local_go_workload_source_fingerprint_contract_violations(repo_root)
assert not violations, violations

print("validated local Go workload source fingerprint cache keys")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go workload source fingerprint cache keys"* ]]
}

@test "image catalog shared source fingerprints match local Go module imports" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import image_catalog_shared_source_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = image_catalog_shared_source_contract_violations(repo_root)
assert not violations, violations
print("validated image catalog shared source fingerprints")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated image catalog shared source fingerprints"* ]]
}

@test "docker optimization tests share local Go workload source fingerprint helpers" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import local_go_workload_source_fingerprint_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-docker-optimization-contracts.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('@test "local Go workload image cache keys include embedded frontend sources"'):
    content.index('@test "image catalog shared source fingerprints match local Go module imports"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "local Go workload source fingerprint policy should move" not in line
]

assert callable(local_go_workload_source_fingerprint_contract_violations)
assert (
    "local_go_workload_source_fingerprint_contract_violations" in content
), "local Go workload source fingerprint contracts should call tests/app_contracts.py"
assert not any('"sentiment-api": [' in line for line in contract_lines), "local Go workload source fingerprint policy should move to tests/app_contracts.py"
assert not any('"subnetcalc-frontend": [' in line for line in contract_lines), "local Go workload source fingerprint policy should move to tests/app_contracts.py"
assert not any('"apps/shared/appshell"' in line for line in contract_lines), "local Go workload source fingerprint policy should move to tests/app_contracts.py"

print("validated shared local Go workload source fingerprint helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared local Go workload source fingerprint helper usage"* ]]
}

@test "image catalog owns local platform build specs" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import local_platform_image_build_spec_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = local_platform_image_build_spec_contract_violations(repo_root)
assert not violations, violations

print("validated image catalog local platform build specs")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated image catalog local platform build specs"* ]]
}

@test "docker optimization tests share local platform image build spec helpers" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import local_platform_image_build_spec_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-docker-optimization-contracts.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "image catalog owns local platform build specs"'):
    content.index('\n@test "image catalog owns local workload build specs for variant builders"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "local platform image build spec policy should move" not in line
]

assert callable(local_platform_image_build_spec_contract_violations)
assert (
    "local_platform_image_build_spec_contract_violations" in content
), "local platform image build spec contracts should call tests/app_contracts.py"
assert not any('"idp-core": {' in line for line in contract_lines), "local platform image build spec policy should move to tests/app_contracts.py"
assert not any('"langfuse-demos": {' in line for line in contract_lines), "local platform image build spec policy should move to tests/app_contracts.py"
assert not any('"apps/shared/appshell"' in line for line in contract_lines), "local platform image build spec policy should move to tests/app_contracts.py"

print("validated shared local platform image build spec helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared local platform image build spec helper usage"* ]]
}

@test "image catalog owns local workload build specs for variant builders" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import local_workload_image_build_spec_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = local_workload_image_build_spec_contract_violations(repo_root)
assert not violations, violations

print("validated catalog-owned workload build specs for variant builders")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated catalog-owned workload build specs for variant builders"* ]]
}

@test "docker optimization tests share local workload image build spec helpers" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import local_workload_image_build_spec_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
test_file = repo_root / "tests" / "validate-docker-optimization-contracts.bats"
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "image catalog owns local workload build specs for variant builders"'):
    content.index('\n@test "image catalog owns Grafana VictoriaLogs plugin image build inputs"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "local workload image build spec policy should move" not in line
]

assert callable(local_workload_image_build_spec_contract_violations)
assert (
    "local_workload_image_build_spec_contract_violations" in content
), "local workload image build spec contracts should call tests/app_contracts.py"
assert not any('"sentiment-api": {' in line for line in contract_lines), "local workload image build spec policy should move to tests/app_contracts.py"
assert not any('"subnetcalc-apim-simulator": {' in line for line in contract_lines), "local workload image build spec policy should move to tests/app_contracts.py"
assert not any('"apps/shared/appshell"' in line for line in contract_lines), "local workload image build spec policy should move to tests/app_contracts.py"

print("validated shared local workload image build spec helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared local workload image build spec helper usage"* ]]
}

@test "image catalog owns Grafana VictoriaLogs plugin image build inputs" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import grafana_plugin_catalog_build_input_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = grafana_plugin_catalog_build_input_contract_violations(repo_root)
assert not violations, violations

print("validated catalog-owned Grafana VictoriaLogs plugin build inputs")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated catalog-owned Grafana VictoriaLogs plugin build inputs"* ]]
}

@test "docker optimization tests share Grafana plugin catalog build input helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import grafana_plugin_catalog_build_input_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "image catalog owns Grafana VictoriaLogs plugin image build inputs"'):
    content.index('\n@test "image catalog entries declare version-check policy"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "Grafana plugin catalog build input policy should move" not in line
]

assert callable(grafana_plugin_catalog_build_input_contract_violations)
assert "grafana_plugin_catalog_build_input_contract_violations" in content
assert not any("grafana_base_image" in line for line in contract_lines), "Grafana plugin catalog build input policy should move to tests/app_contracts.py"
assert not any("plugin_fetch_image" in line for line in contract_lines), "Grafana plugin catalog build input policy should move to tests/app_contracts.py"
assert not any("version_tag_strategy" in line for line in contract_lines), "Grafana plugin catalog build input policy should move to tests/app_contracts.py"
assert not any("GRAFANA_IMAGE_TAG" in line for line in contract_lines), "Grafana plugin catalog build input policy should move to tests/app_contracts.py"
assert not any("catalog_grafana_build_value" in line for line in contract_lines), "Grafana plugin catalog build input policy should move to tests/app_contracts.py"

print("validated shared Grafana plugin catalog build input helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Grafana plugin catalog build input helper usage"* ]]
}

@test "image catalog entries declare version-check policy" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import (
    image_catalog_version_check_policy_contract_violations,
    image_catalog_version_check_policy_count,
)

repo_root = Path(os.environ["REPO_ROOT"])
violations = image_catalog_version_check_policy_contract_violations(repo_root)
assert not violations, violations
validated = image_catalog_version_check_policy_count(repo_root)

print(f"validated {validated} image catalog version-check policies")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 12 image catalog version-check policies"* ]]
}

@test "docker optimization tests share image catalog version-check helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import image_catalog_version_check_policy_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "image catalog entries declare version-check policy"'):
    content.index('\n@test "Lima external image refs match the image catalog"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "image catalog version-check policy should move" not in line
]

assert callable(image_catalog_version_check_policy_contract_violations)
assert "image_catalog_version_check_policy_contract_violations" in content
assert not any("allowed_modes =" in line for line in contract_lines), "image catalog version-check policy should move to tests/app_contracts.py"
assert not any("policy = image.get" in line for line in contract_lines), "image catalog version-check policy should move to tests/app_contracts.py"
assert not any("mode = policy.get" in line for line in contract_lines), "image catalog version-check policy should move to tests/app_contracts.py"
assert not any("reason = str" in line for line in contract_lines), "image catalog version-check policy should move to tests/app_contracts.py"
assert not any('image.get("default_tag")' in line for line in contract_lines), "image catalog version-check policy should move to tests/app_contracts.py"

print("validated shared image catalog version-check helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared image catalog version-check helper usage"* ]]
}

@test "Lima external image refs match the image catalog" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import image_catalog_target_ref_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = image_catalog_target_ref_contract_violations(repo_root)
assert not violations, violations

print("validated Lima external image refs against image catalog")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Lima external image refs against image catalog"* ]]
}

@test "docker optimization tests share image catalog target ref helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import image_catalog_target_ref_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "Lima external image refs match the image catalog"'):
    content.index('\n@test "image catalog renders target tfvars external image projection"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "image catalog target ref policy should move" not in line
]

assert callable(image_catalog_target_ref_contract_violations)
assert "image_catalog_target_ref_contract_violations" in content
assert not any("validate-image-catalog-target-refs.sh" in line for line in contract_lines), "image catalog target ref policy should move to tests/app_contracts.py"
assert not any("lima.tfvars" in line for line in contract_lines), "image catalog target ref policy should move to tests/app_contracts.py"
assert not any("lima.tfvars" in line for line in contract_lines), "image catalog target ref policy should move to tests/app_contracts.py"
assert not any("subprocess.run" in line for line in contract_lines), "image catalog target ref policy should move to tests/app_contracts.py"

print("validated shared image catalog target ref helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared image catalog target ref helper usage"* ]]
}

@test "image catalog renders target tfvars external image projection" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import image_catalog_target_tfvars_projection_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = image_catalog_target_tfvars_projection_contract_violations(repo_root)
assert not violations, violations

print("validated generated target tfvars projection from image catalog")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated generated target tfvars projection from image catalog"* ]]
}

@test "docker optimization tests share image catalog target tfvars projection helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import image_catalog_target_tfvars_projection_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "image catalog renders target tfvars external image projection"'):
    content.index('\n@test "local platform IDP cache hits are not invalidated by unrelated git commits"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "image catalog target tfvars projection policy should move" not in line
]

assert callable(image_catalog_target_tfvars_projection_contract_violations)
assert "image_catalog_target_tfvars_projection_contract_violations" in content
assert not any("--print-expected" in line for line in contract_lines), "image catalog target tfvars projection policy should move to tests/app_contracts.py"
assert not any("host.lima.internal:5002" in line for line in contract_lines), "image catalog target tfvars projection policy should move to tests/app_contracts.py"
assert not any("192.168.64.1:5002" in line for line in contract_lines), "image catalog target tfvars projection policy should move to tests/app_contracts.py"
assert not any("external_platform_image_refs" in line for line in contract_lines), "image catalog target tfvars projection policy should move to tests/app_contracts.py"
assert not any("subprocess.check_output" in line for line in contract_lines), "image catalog target tfvars projection policy should move to tests/app_contracts.py"

print("validated shared image catalog target tfvars projection helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared image catalog target tfvars projection helper usage"* ]]
}

@test "local platform IDP cache hits are not invalidated by unrelated git commits" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import local_platform_cache_hit_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = local_platform_cache_hit_contract_violations(repo_root)
assert not violations, violations

print("validated local platform IDP cache hits ignore unrelated git commits")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local platform IDP cache hits ignore unrelated git commits"* ]]
}

@test "docker optimization tests share local platform cache-hit helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import local_platform_cache_hit_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "local platform IDP cache hits are not invalidated by unrelated git commits"'):
    content.index('\n@test "image catalog shared image builder adapter owns variant build mechanics"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "local platform cache-hit policy should move" not in line
]

assert callable(local_platform_cache_hit_contract_violations)
assert "local_platform_cache_hit_contract_violations" in content
assert not any("image_build_cache_hit()" in line for line in contract_lines), "local platform cache-hit policy should move to tests/app_contracts.py"
assert not any("skip_condition" in line for line in contract_lines), "local platform cache-hit policy should move to tests/app_contracts.py"
assert not any("IMAGE_BUILD_REQUIRE_COMMIT_TAG" in line for line in contract_lines), "local platform cache-hit policy should move to tests/app_contracts.py"
assert not any("image_build_push_optional_tag" in line for line in contract_lines), "local platform cache-hit policy should move to tests/app_contracts.py"

print("validated shared local platform cache-hit helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared local platform cache-hit helper usage"* ]]
}

@test "image catalog shared image builder adapter owns variant build mechanics" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import image_builder_adapter_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = image_builder_adapter_contract_violations(repo_root)
assert not violations, violations

print("validated shared image builder adapter ownership")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared image builder adapter ownership"* ]]
}

@test "docker optimization tests share image builder adapter helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import image_builder_adapter_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "image catalog shared image builder adapter owns variant build mechanics"'):
    content.index('\n@test "image catalog context adapter owns generated Backstage build context"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "image builder adapter policy should move" not in line
]

assert callable(image_builder_adapter_contract_violations)
assert "image_builder_adapter_contract_violations" in content
assert not any("required_functions =" in line for line in contract_lines), "image builder adapter policy should move to tests/app_contracts.py"
assert not any("image_build_prepare_args()" in line for line in contract_lines), "image builder adapter policy should move to tests/app_contracts.py"
assert not any("variant_wrappers =" in line for line in contract_lines), "image builder adapter policy should move to tests/app_contracts.py"
assert not any("duplicated_function" in line for line in contract_lines), "image builder adapter policy should move to tests/app_contracts.py"

print("validated shared image builder adapter helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared image builder adapter helper usage"* ]]
}

@test "image catalog context adapter owns generated Backstage build context" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import image_catalog_context_adapter_contract_violations

repo_root = Path(os.environ["REPO_ROOT"])
violations = image_catalog_context_adapter_contract_violations(repo_root)
assert not violations, violations

print("validated image catalog Backstage context adapter")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated image catalog Backstage context adapter"* ]]
}

@test "docker optimization tests share image catalog context adapter helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import image_catalog_context_adapter_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "image catalog context adapter owns generated Backstage build context"'):
    content.index('\n@test "generated Backstage image build passes a lean concrete Docker context"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "image catalog context adapter policy should move" not in line
]

assert callable(image_catalog_context_adapter_contract_violations)
assert "image_catalog_context_adapter_contract_violations" in content
assert not any("context_lib =" in line for line in contract_lines), "image catalog context adapter policy should move to tests/app_contracts.py"
assert not any("duplicated_fragment" in line for line in contract_lines), "image catalog context adapter policy should move to tests/app_contracts.py"
assert not any("copy_backstage_app_catalog()" in line for line in contract_lines), "image catalog context adapter policy should move to tests/app_contracts.py"
assert not any("image_catalog_prepare_build_context_adapter" in line and "assert" in line for line in contract_lines), "image catalog context adapter policy should move to tests/app_contracts.py"

print("validated shared image catalog context adapter helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared image catalog context adapter helper usage"* ]]
}

@test "generated Backstage image build passes a lean concrete Docker context" {
  run bash -lc '
    set -euo pipefail
    cd "${REPO_ROOT}"
    source kubernetes/workflow/image-catalog-lib.sh
    source kubernetes/workflow/image-catalog-context-lib.sh
    source kubernetes/workflow/image-build-lib.sh

    export CACHE_PUSH_HOST=127.0.0.1:5002
    export IMAGE_NAMESPACE=platform
    export TAG=latest
    export FORCE_REBUILD=1
    export IMAGE_BUILD_CONTEXT_ARGS_FILE="${BATS_TEST_TMPDIR}/docker-build-args.txt"
    export IMAGE_BUILD_CONTEXT_PATH_FILE="${BATS_TEST_TMPDIR}/docker-build-context.txt"

    tag_exists_in_cache() { return 1; }
    docker_push_local_registry() { :; }
    docker() { :; }
    docker_build_local() {
      printf "%s\n" "$@" >"${IMAGE_BUILD_CONTEXT_ARGS_FILE}"
      printf "%s\n" "${@: -1}" >"${IMAGE_BUILD_CONTEXT_PATH_FILE}"
    }

    image_build_catalog_build_and_push platform backstage backstage src-test 1.0.0

    context_dir="$(cat "${IMAGE_BUILD_CONTEXT_PATH_FILE}")"
    test -d "${context_dir}"
    test -f "${context_dir}/Dockerfile"
    ! head -n 1 "${context_dir}/Dockerfile" | grep -Fq "# syntax=docker/dockerfile"
    test -f "${context_dir}/package.json"
    test -d "${context_dir}/catalog/apps/subnetcalc"
    test ! -e "${context_dir}/node_modules"
    test ! -e "${context_dir}/.yarn/cache"
    tail -n 1 "${IMAGE_BUILD_CONTEXT_ARGS_FILE}" | grep -Fx "${context_dir}" >/dev/null
    echo "validated generated Backstage Docker context"
  '

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated generated Backstage Docker context"* ]]
}

@test "image build prebuild hooks run once for identical commands" {
  catalog="${BATS_TEST_TMPDIR}/image-catalog.json"
  prebuild_log="${BATS_TEST_TMPDIR}/prebuild.log"
  build_log="${BATS_TEST_TMPDIR}/build.log"

  cat >"${catalog}" <<JSON
{
  "namespace": "platform",
  "platform_images": [],
  "workload_images": [
    {
      "id": "first",
      "image_name": "first",
      "default_tag": "0.1.0",
      "build": {
        "context": ".",
        "dockerfile": "Dockerfile",
        "prebuild": "printf '%s\\\\n' prebuild >> \\"${prebuild_log}\\""
      }
    },
    {
      "id": "second",
      "image_name": "second",
      "default_tag": "0.1.0",
      "build": {
        "context": ".",
        "dockerfile": "Dockerfile",
        "prebuild": "printf '%s\\\\n' prebuild >> \\"${prebuild_log}\\""
      }
    }
  ]
}
JSON

  touch "${BATS_TEST_TMPDIR}/Dockerfile"

  run bash -lc "
    set -euo pipefail
    export REPO_ROOT='${BATS_TEST_TMPDIR}'
    export IMAGE_CATALOG_FILE='${catalog}'
    export CACHE_PUSH_HOST=127.0.0.1:5002
    export IMAGE_NAMESPACE=platform
    export TAG=latest
    export FORCE_REBUILD=1
    source '${REPO_ROOT}/kubernetes/workflow/image-catalog-lib.sh'
    source '${REPO_ROOT}/kubernetes/workflow/image-build-lib.sh'

    tag_exists_in_cache() { return 1; }
    docker_push_local_registry() { :; }
    docker() { :; }
    docker_build_local() { printf '%s\n' \"\$*\" >>'${build_log}'; }

    image_build_catalog_build_loop workload workload
  "

  [ "${status}" -eq 0 ]
  prebuild_count="$(wc -l <"${prebuild_log}" | tr -d ' ')"
  build_count="$(wc -l <"${build_log}" | tr -d ' ')"
  [ "${prebuild_count}" -eq 1 ]
  [ "${build_count}" -eq 2 ]
}

@test "platform MCP Docker image uses the Go single-binary runtime" {
  run python3 - <<'PY'
from pathlib import Path
import os

from tests.app_contracts import (
    go_app_dockerfile_runtime_contract_violations,
    go_app_makefile_workflow_contract_violations,
)

repo_root = Path(os.environ["REPO_ROOT"])
violations = (
    go_app_dockerfile_runtime_contract_violations(repo_root)
    + go_app_makefile_workflow_contract_violations(repo_root)
)
assert not violations, violations

print("validated platform MCP Docker image contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform MCP Docker image contract"* ]]
}

@test "docker optimization tests share platform MCP runtime helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import go_app_dockerfile_runtime_contract_violations, go_app_makefile_workflow_contract_violations

test_file = Path("tests/validate-docker-optimization-contracts.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "platform MCP Docker image uses the Go single-binary runtime"'):
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "platform MCP runtime policy should move" not in line
]

assert callable(go_app_dockerfile_runtime_contract_violations)
assert callable(go_app_makefile_workflow_contract_violations)
assert "go_app_dockerfile_runtime_contract_violations" in content
assert "go_app_makefile_workflow_contract_violations" in content
assert not any("apps/platform-mcp/app/Dockerfile" in line for line in contract_lines), "platform MCP runtime policy should move to tests/app_contracts.py"
assert not any("COPY --chown=65532:65532 .run/platform-mcp /platform-mcp" in line for line in contract_lines), "platform MCP runtime policy should move to tests/app_contracts.py"
assert not any("ENTRYPOINT [\\\"/platform-mcp\\\"]" in line for line in contract_lines), "platform MCP runtime policy should move to tests/app_contracts.py"
assert not any("CGO_ENABLED=0 GOOS=linux" in line for line in contract_lines), "platform MCP runtime policy should move to tests/app_contracts.py"
assert not any("go build -trimpath" in line for line in contract_lines), "platform MCP runtime policy should move to tests/app_contracts.py"

print("validated shared platform MCP runtime helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared platform MCP runtime helper usage"* ]]
}
