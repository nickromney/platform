#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "canonical browser apps use Biome lint-format and Deno semantic checks" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    browser_app_deno_config_contract_violations,
    browser_app_js_check_command_contract_violations,
)

repo = Path("${REPO_ROOT}")
violations = (
    browser_app_js_check_command_contract_violations(repo)
    + browser_app_deno_config_contract_violations(repo)
)
assert not violations, violations
print("validated browser app js-check command contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app js-check command contract"* ]]

  run make -C "${REPO_ROOT}/apps" js-check

  [ "${status}" -eq 0 ]
}

@test "browser JavaScript tests share js-check command helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_js_check_command_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser app js-check command policy should move" not in line
]

assert callable(browser_app_js_check_command_contract_violations)
assert "browser_app_js_check_command_contract_violations" in content
assert not any("browser_apps()" in line for line in contract_lines), "browser app js-check command policy should move to tests/app_contracts.py"
assert not any("while IFS= read -r app" in line for line in contract_lines), "browser app js-check command policy should move to tests/app_contracts.py"
assert not any("make -C \"${REPO_ROOT}/apps/${app}/app\" js-check" in line for line in contract_lines), "browser app js-check command policy should move to tests/app_contracts.py"
assert not any("deno check --check-js internal/app/web/app.js" in line for line in contract_lines), "browser app js-check command policy should move to tests/app_contracts.py"

print("validated shared browser app js-check command helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser app js-check command helper usage"* ]]
}

@test "checked JavaScript app roots do not introduce package-manager manifests" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_package_manifest_contract_violations

violations = browser_app_package_manifest_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser app package-manager manifest contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app package-manager manifest contract"* ]]
}

@test "browser JavaScript declares checked source and app-local API types" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_checked_source_contract_violations

violations = browser_app_checked_source_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser app checked source contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app checked source contract"* ]]
}

@test "browser JavaScript tests share package and checked-source helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    browser_app_deno_config_contract_violations,
    browser_app_checked_source_contract_violations,
    browser_app_package_manifest_contract_violations,
)

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser JavaScript package/source policy should move" not in line
]

assert callable(browser_app_checked_source_contract_violations)
assert callable(browser_app_deno_config_contract_violations)
assert callable(browser_app_package_manifest_contract_violations)
assert "browser_app_deno_config_contract_violations" in content
assert "browser_app_checked_source_contract_violations" in content
assert "browser_app_package_manifest_contract_violations" in content
assert not any("package-lock.json" in line for line in contract_lines), "browser JavaScript package/source policy should move to tests/app_contracts.py"
assert not any("sed -n '1p'" in line for line in contract_lines), "browser JavaScript package/source policy should move to tests/app_contracts.py"
assert not any("api-types.d.ts; done" in line for line in contract_lines), "browser JavaScript package/source policy should move to tests/app_contracts.py"

print("validated shared browser JavaScript package/source helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser JavaScript package/source helper usage"* ]]
}

@test "shared browser API types are part of the app JavaScript contract" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_browser_api_types_makefile_contract_violations

violations = shared_browser_api_types_makefile_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared browser API type Makefile contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser API type Makefile contract"* ]]

  run bash -lc "cd '${REPO_ROOT}' && biome check apps/shared/web/api-types.d.ts"

  [ "${status}" -eq 0 ]
}

@test "browser JavaScript tests share API type Makefile helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_browser_api_types_makefile_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "shared browser API type Makefile policy should move" not in line
]

assert callable(shared_browser_api_types_makefile_contract_violations)
assert "shared_browser_api_types_makefile_contract_violations" in content
assert not any("make -n -C" in line for line in contract_lines), "shared browser API type Makefile policy should move to tests/app_contracts.py"
assert not any("biome check ./shared/web/api-types.d.ts" in line for line in contract_lines), "shared browser API type Makefile policy should move to tests/app_contracts.py"

print("validated shared browser API type Makefile helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser API type Makefile helper usage"* ]]
}

@test "shared app shell JSON helpers expose named JSON results" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_json_contract_violations

violations = shared_appshell_json_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell JSON contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell JSON contract"* ]]
}

@test "browser JavaScript tests share app shell JSON helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_json_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "shared app shell JSON policy should move" not in line
]

assert callable(shared_appshell_json_contract_violations)
assert "shared_appshell_json_contract_violations" in content
assert not any("Promise<any>|data: any" in line for line in contract_lines), "shared app shell JSON policy should move to tests/app_contracts.py"
assert not any("Promise<unknown>|data: unknown" in line for line in contract_lines), "shared app shell JSON policy should move to tests/app_contracts.py"

print("validated shared app shell JSON helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell JSON helper usage"* ]]
}

@test "shared app shell exposes typed APIM trace timing" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_apim_trace_contract_violations

violations = shared_appshell_apim_trace_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell APIM trace contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell APIM trace contract"* ]]
}

@test "browser JavaScript tests share app shell APIM trace helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_apim_trace_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "shared app shell APIM trace policy should move" not in line
]

assert callable(shared_appshell_apim_trace_contract_violations)
assert "shared_appshell_apim_trace_contract_violations" in content
assert not any("APIMTrace \\\\| unknown" in line for line in contract_lines), "shared app shell APIM trace policy should move to tests/app_contracts.py"
assert not any("apimTrace: unknown" in line for line in contract_lines), "shared app shell APIM trace policy should move to tests/app_contracts.py"
assert not any("(value: string) => unknown" in line for line in contract_lines), "shared app shell APIM trace policy should move to tests/app_contracts.py"

print("validated shared app shell APIM trace helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell APIM trace helper usage"* ]]
}

@test "shared app shell owns JSON request headers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_json_headers_contract_violations

violations = shared_appshell_json_headers_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell JSON header contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell JSON header contract"* ]]
}

@test "shared app shell uses RuntimeConfigBase for network path config" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_runtime_config_contract_violations

violations = shared_appshell_runtime_config_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell runtime config contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell runtime config contract"* ]]
}

@test "browser JavaScript tests share app shell runtime config helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_runtime_config_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "shared app shell runtime config policy should move" not in line
]

assert callable(shared_appshell_runtime_config_contract_violations)
assert "shared_appshell_runtime_config_contract_violations" in content
assert not any("networkHops\\\\\\\\?: unknown" in line for line in contract_lines), "shared app shell runtime config policy should move to tests/app_contracts.py"
assert not any("showNetworkPath\\\\\\\\?: unknown" in line for line in contract_lines), "shared app shell runtime config policy should move to tests/app_contracts.py"

print("validated shared app shell runtime config helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell runtime config helper usage"* ]]
}

@test "shared app shell owns runtime API path construction" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_api_path_contract_violations

violations = shared_appshell_api_path_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell API path contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell API path contract"* ]]
}

@test "shared app shell owns API timing diagnostics rendering" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_api_timing_contract_violations

violations = shared_appshell_api_timing_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell API timing contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell API timing contract"* ]]
}

@test "shared app shell owns timestamp display formatting" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_timestamp_contract_violations

violations = shared_appshell_timestamp_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell timestamp contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell timestamp contract"* ]]
}

@test "shared app shell owns API health status formatting" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_api_health_status_contract_violations

violations = shared_appshell_api_health_status_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell API health status contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell API health status contract"* ]]
}

@test "browser app JavaScript avoids explicit any in public JSDoc contracts" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_explicit_any_contract_violations

violations = browser_app_explicit_any_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser app explicit-any contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app explicit-any contract"* ]]
}

@test "browser JavaScript tests share explicit-any helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_explicit_any_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser explicit-any policy should move" not in line
]

assert callable(browser_app_explicit_any_contract_violations)
assert "browser_app_explicit_any_contract_violations" in content
assert not any("Array<any>|Promise<any>" in line for line in contract_lines), "browser explicit-any policy should move to tests/app_contracts.py"
assert not any("\\\\{any\\\\}" in line for line in contract_lines), "browser explicit-any policy should move to tests/app_contracts.py"

print("validated shared browser explicit-any helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser explicit-any helper usage"* ]]
}

@test "browser app JSON responses bind named types without direct fetch casts" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_json_response_binding_contract_violations

violations = browser_app_json_response_binding_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated app JSON response type binding")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated app JSON response type binding"* ]]
}

@test "browser JavaScript tests share JSON response binding helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_json_response_binding_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser JSON response binding policy should move" not in line
]

assert callable(browser_app_json_response_binding_contract_violations)
assert "browser_app_json_response_binding_contract_violations" in content
assert not any('glob("*/app/internal/app/web/app.js")' in line for line in contract_lines), "browser JSON response binding policy should move to tests/app_contracts.py"
assert not any("await fetchJSON(" in line for line in contract_lines), "browser JSON response binding policy should move to tests/app_contracts.py"
assert not any("re.finditer" in line for line in contract_lines), "browser JSON response binding policy should move to tests/app_contracts.py"

print("validated shared browser JSON response binding helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser JSON response binding helper usage"* ]]
}

@test "shared browser globals avoid explicit any casts" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_browser_global_any_cast_contract_violations

violations = shared_browser_global_any_cast_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared browser global any-cast contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser global any-cast contract"* ]]
}

@test "browser JavaScript tests share global any-cast helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_browser_global_any_cast_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "shared browser any-cast policy should move" not in line
]

assert callable(shared_browser_global_any_cast_contract_violations)
assert "shared_browser_global_any_cast_contract_violations" in content
assert not any("@type \\\\{any\\\\}" in line for line in contract_lines), "shared browser any-cast policy should move to tests/app_contracts.py"
assert not any("apps/shared/idpauth/web/idpauth.js" in line and "rg" in line for line in contract_lines), "shared browser any-cast policy should move to tests/app_contracts.py"

print("validated shared browser global any-cast helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser global any-cast helper usage"* ]]
}

@test "shared IDP browser helper uses named config and session contracts" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_idp_browser_contract_violations

violations = shared_idp_browser_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared IDP browser contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared IDP browser contract"* ]]
}

@test "shared IDP browser helper owns API error display messages" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_idp_browser_api_error_contract_violations

violations = shared_idp_browser_api_error_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared IDP browser API error contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared IDP browser API error contract"* ]]
}

@test "APIM browser API contract names management collections" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import apim_browser_api_contract_violations

violations = apim_browser_api_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated APIM browser API contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated APIM browser API contract"* ]]
}

@test "ChatGPT Sim browser API contract names chat route metadata" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import chatgpt_browser_api_contract_violations

violations = chatgpt_browser_api_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated ChatGPT Sim browser chat API contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated ChatGPT Sim browser chat API contract"* ]]
}

@test "ChatGPT Sim browser API contract names discovery and tool payloads" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import chatgpt_browser_api_contract_violations

violations = chatgpt_browser_api_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated ChatGPT Sim browser discovery API contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated ChatGPT Sim browser discovery API contract"* ]]
}

@test "Langfuse browser capability renderer keeps typed config strings" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import langfuse_browser_capability_contract_violations

violations = langfuse_browser_capability_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated Langfuse browser capability contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Langfuse browser capability contract"* ]]
}

@test "browser JavaScript tests share public unknown contract helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    apim_browser_api_contract_violations,
    browser_public_unknown_contract_violations,
    chatgpt_browser_api_contract_violations,
    langfuse_browser_capability_contract_violations,
    shared_idp_browser_contract_violations,
)

repo = Path("${REPO_ROOT}")
violations = browser_public_unknown_contract_violations(repo)
assert not violations, violations

content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser public unknown policy should move" not in line
]

assert callable(apim_browser_api_contract_violations)
assert callable(browser_public_unknown_contract_violations)
assert callable(chatgpt_browser_api_contract_violations)
assert callable(langfuse_browser_capability_contract_violations)
assert callable(shared_idp_browser_contract_violations)
assert "apim_browser_api_contract_violations" in content
assert "browser_public_unknown_contract_violations" in content
assert "chatgpt_browser_api_contract_violations" in content
assert "langfuse_browser_capability_contract_violations" in content
assert "shared_idp_browser_contract_violations" in content
assert not any("Record<string, unknown>" in line for line in contract_lines), "browser public unknown policy should move to tests/app_contracts.py"
assert not any("unknown\\\\[\\\\]" in line for line in contract_lines), "browser public unknown policy should move to tests/app_contracts.py"
assert not any("@param \\\\{unknown" in line for line in contract_lines), "browser public unknown policy should move to tests/app_contracts.py"

print("validated shared browser public unknown helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser public unknown helper usage"* ]]
}

@test "browser apps share the same app-folder color tokens" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_color_token_contract_violations

violations = browser_app_color_token_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser app color token contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app color token contract"* ]]
}

@test "browser app headers expose the shared auth and theme controls" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_header_controls_contract_violations

violations = browser_app_header_controls_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser app header controls contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app header controls contract"* ]]
}

@test "browser JavaScript tests share color and header helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    browser_app_color_token_contract_violations,
    browser_app_header_controls_contract_violations,
    browser_app_shell_css_boundary_contract_violations,
)

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser color/header policy should move" not in line
]

assert callable(browser_app_color_token_contract_violations)
assert callable(browser_app_header_controls_contract_violations)
assert callable(browser_app_shell_css_boundary_contract_violations)
assert "browser_app_color_token_contract_violations" in content
assert "browser_app_header_controls_contract_violations" in content
assert "browser_app_shell_css_boundary_contract_violations" in content
assert not any("--page: #f6f8fb;" in line for line in contract_lines), "browser color/header policy should move to tests/app_contracts.py"
assert not any('id=\\"auth-state\\"' in line for line in contract_lines), "browser color/header policy should move to tests/app_contracts.py"
assert not any("theme-switcher" in line and "grep" in line for line in contract_lines), "browser color/header policy should move to tests/app_contracts.py"

print("validated shared browser color/header helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser color/header helper usage"* ]]
}

@test "browser app CSS leaves shared shell controls to app-shell.css" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_shell_css_boundary_contract_violations

violations = browser_app_shell_css_boundary_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser app shell CSS boundary contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app shell CSS boundary contract"* ]]
}

@test "browser apps expose a polite status region" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_status_region_contract_violations

violations = browser_app_status_region_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations

print("validated browser app status region contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app status region contract"* ]]
}

@test "browser app landmark layout keeps header and main as body-level siblings" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_landmark_layout_contract_violations

violations = browser_app_landmark_layout_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations

print("validated browser app landmark layout contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app landmark layout contract"* ]]
}

@test "browser app user-facing web sources avoid unknown placeholders" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_unknown_placeholder_contract_violations

violations = browser_app_unknown_placeholder_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations

print("validated browser app user-facing placeholder contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app user-facing placeholder contract"* ]]
}

@test "browser JavaScript tests share HTML layout and placeholder helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    browser_app_asset_order_contract_violations,
    browser_app_landmark_layout_contract_violations,
    browser_app_status_region_contract_violations,
    browser_app_unknown_placeholder_contract_violations,
)

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser HTML layout policy should move" not in line
]

assert callable(browser_app_asset_order_contract_violations)
assert callable(browser_app_landmark_layout_contract_violations)
assert callable(browser_app_status_region_contract_violations)
assert callable(browser_app_unknown_placeholder_contract_violations)
assert "browser_app_asset_order_contract_violations" in content
assert "browser_app_landmark_layout_contract_violations" in content
assert "browser_app_status_region_contract_violations" in content
assert "browser_app_unknown_placeholder_contract_violations" in content
assert not any("HTMLParser" in line for line in contract_lines), "browser HTML layout policy should move to tests/app_contracts.py"
assert not any('role") == "status"' in line for line in contract_lines), "browser HTML layout policy should move to tests/app_contracts.py"
assert not any('children[:3] == ["a", "header", "main"]' in line for line in contract_lines), "browser HTML layout policy should move to tests/app_contracts.py"
assert not any('"/runtime-config.js"' in line for line in contract_lines), "browser HTML layout policy should move to tests/app_contracts.py"
assert not any("re.search" in line for line in contract_lines), "browser HTML layout policy should move to tests/app_contracts.py"

print("validated shared browser HTML layout helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser HTML layout helper usage"* ]]
}

@test "browser apps load shared assets in the common order" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import browser_app_asset_order_contract_violations

violations = browser_app_asset_order_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated browser app shared asset order contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated browser app shared asset order contract"* ]]
}

@test "shared app shell renders network paths as route traces" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_route_trace_css_contract_violations

violations = shared_appshell_route_trace_css_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell route trace CSS contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell route trace CSS contract"* ]]
}

@test "shared app shell keeps theme toggle fixed inside wrapped header actions" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_theme_toggle_css_contract_violations

violations = shared_appshell_theme_toggle_css_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell theme toggle CSS contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell theme toggle CSS contract"* ]]
}

@test "shared app shell keeps keyboard accessibility polish centralized" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_accessibility_css_contract_violations

violations = shared_appshell_accessibility_css_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell accessibility CSS contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell accessibility CSS contract"* ]]
}

@test "shared app shell header text survives narrow screens" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_header_text_resilience_contract_violations

violations = shared_appshell_header_text_resilience_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell resilient header text")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell resilient header text"* ]]
}

@test "shared app shell control text survives narrow screens" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_control_text_resilience_contract_violations

violations = shared_appshell_control_text_resilience_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell resilient control text")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell resilient control text"* ]]
}

@test "shared app shell diagnostic text stays contained" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_diagnostic_text_resilience_contract_violations

violations = shared_appshell_diagnostic_text_resilience_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell resilient diagnostic text")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell resilient diagnostic text"* ]]
}

@test "shared app shell form controls stay within panels" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_form_control_sizing_contract_violations

violations = shared_appshell_form_control_sizing_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell form control sizing")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell form control sizing"* ]]
}

@test "shared app shell owns form label and textarea rhythm" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_form_label_textarea_contract_violations

violations = shared_appshell_form_label_textarea_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell form label and textarea rhythm")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell form label and textarea rhythm"* ]]
}

@test "shared app shell owns code block surface styling" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_code_block_surface_contract_violations

violations = shared_appshell_code_block_surface_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell code block surface")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell code block surface"* ]]
}

@test "shared app shell owns simple paragraph message rendering" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_message_render_contract_violations

violations = shared_appshell_message_render_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell message renderer")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell message renderer"* ]]
}

@test "shared app shell centralizes DOM id lookup" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_dom_lookup_contract_violations

violations = shared_appshell_dom_lookup_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell DOM lookup helper")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell DOM lookup helper"* ]]
}

@test "shared app shell owns status text rendering" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_status_render_contract_violations

violations = shared_appshell_status_render_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell status renderer")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell status renderer"* ]]
}

@test "shared app shell owns select option rendering" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_select_option_render_contract_violations

violations = shared_appshell_select_option_render_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell select option renderer")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell select option renderer"* ]]
}

@test "shared app shell owns element list rendering" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_element_list_render_contract_violations

violations = shared_appshell_element_list_render_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell element list renderer")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell element list renderer"* ]]
}

@test "sentiment comments render through shared element lists" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import sentiment_comment_list_render_contract_violations

violations = sentiment_comment_list_render_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated sentiment comment element renderer")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment comment element renderer"* ]]
}

@test "sentiment diagnostics render through shared DOM helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import sentiment_diagnostics_render_contract_violations

violations = sentiment_diagnostics_render_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated sentiment diagnostics DOM renderer")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated sentiment diagnostics DOM renderer"* ]]
}

@test "subnetcalc result cards render through shared DOM diagnostics" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import subnetcalc_result_card_render_contract_violations

violations = subnetcalc_result_card_render_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated subnetcalc result card renderer")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated subnetcalc result card renderer"* ]]
}

@test "shared app shell owns summary list rendering" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_summary_list_render_contract_violations

violations = shared_appshell_summary_list_render_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell summary list renderer")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell summary list renderer"* ]]
}

@test "shared app shell buttons keep long labels contained" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_global_button_resilience_contract_violations

violations = shared_appshell_global_button_resilience_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell global button resilience")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell global button resilience"* ]]
}

@test "shared app shell owns status and table presentation" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import shared_appshell_status_table_css_contract_violations

violations = shared_appshell_status_table_css_contract_violations(Path("${REPO_ROOT}"))
assert not violations, violations
print("validated shared app shell status and table CSS")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell status and table CSS"* ]]
}

@test "browser JavaScript tests share app shell CSS helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import (
    shared_appshell_accessibility_css_contract_violations,
    shared_appshell_code_block_surface_contract_violations,
    shared_appshell_control_text_resilience_contract_violations,
    shared_appshell_diagnostic_text_resilience_contract_violations,
    shared_appshell_form_control_sizing_contract_violations,
    shared_appshell_form_label_textarea_contract_violations,
    shared_appshell_global_button_resilience_contract_violations,
    shared_appshell_header_text_resilience_contract_violations,
    shared_appshell_element_list_render_contract_violations,
    shared_appshell_message_render_contract_violations,
    shared_appshell_dom_lookup_contract_violations,
    shared_appshell_status_render_contract_violations,
    shared_appshell_route_trace_css_contract_violations,
    shared_appshell_select_option_render_contract_violations,
    shared_appshell_status_table_css_contract_violations,
    shared_appshell_summary_list_render_contract_violations,
    shared_appshell_theme_toggle_css_contract_violations,
    sentiment_comment_list_render_contract_violations,
    sentiment_diagnostics_render_contract_violations,
    subnetcalc_result_card_render_contract_violations,
)

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "vanilla-js-typecheck.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "shared app shell CSS policy should move" not in line
]

assert callable(shared_appshell_route_trace_css_contract_violations)
assert callable(shared_appshell_theme_toggle_css_contract_violations)
assert callable(shared_appshell_accessibility_css_contract_violations)
assert callable(shared_appshell_code_block_surface_contract_violations)
assert callable(shared_appshell_control_text_resilience_contract_violations)
assert callable(shared_appshell_diagnostic_text_resilience_contract_violations)
assert callable(shared_appshell_form_control_sizing_contract_violations)
assert callable(shared_appshell_form_label_textarea_contract_violations)
assert callable(shared_appshell_global_button_resilience_contract_violations)
assert callable(shared_appshell_header_text_resilience_contract_violations)
assert callable(shared_appshell_element_list_render_contract_violations)
assert callable(shared_appshell_message_render_contract_violations)
assert callable(shared_appshell_dom_lookup_contract_violations)
assert callable(shared_appshell_status_render_contract_violations)
assert callable(shared_appshell_select_option_render_contract_violations)
assert callable(shared_appshell_status_table_css_contract_violations)
assert callable(shared_appshell_summary_list_render_contract_violations)
assert callable(sentiment_comment_list_render_contract_violations)
assert callable(sentiment_diagnostics_render_contract_violations)
assert callable(subnetcalc_result_card_render_contract_violations)
assert "shared_appshell_route_trace_css_contract_violations" in content
assert "shared_appshell_theme_toggle_css_contract_violations" in content
assert "shared_appshell_accessibility_css_contract_violations" in content
assert "shared_appshell_code_block_surface_contract_violations" in content
assert "shared_appshell_control_text_resilience_contract_violations" in content
assert "shared_appshell_diagnostic_text_resilience_contract_violations" in content
assert "shared_appshell_form_control_sizing_contract_violations" in content
assert "shared_appshell_form_label_textarea_contract_violations" in content
assert "shared_appshell_global_button_resilience_contract_violations" in content
assert "shared_appshell_header_text_resilience_contract_violations" in content
assert "shared_appshell_element_list_render_contract_violations" in content
assert "shared_appshell_message_render_contract_violations" in content
assert "shared_appshell_dom_lookup_contract_violations" in content
assert "shared_appshell_status_render_contract_violations" in content
assert "shared_appshell_select_option_render_contract_violations" in content
assert "shared_appshell_status_table_css_contract_violations" in content
assert "shared_appshell_summary_list_render_contract_violations" in content
assert "sentiment_comment_list_render_contract_violations" in content
assert "sentiment_diagnostics_render_contract_violations" in content
assert "subnetcalc_result_card_render_contract_violations" in content
assert not any("box-sizing: border-box" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any("counter-reset: hop" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any("grid-template-columns: 28px minmax(0, 1fr)" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any("flex: 0 0 42px" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any(".skip-link:focus-visible" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any("overflow-x: auto" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any("overflow-wrap: anywhere" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any("text-align: center" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any(":where(table)" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"
assert not any(".notice" in line for line in contract_lines), "shared app shell CSS policy should move to tests/app_contracts.py"

print("validated shared app shell CSS helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared app shell CSS helper usage"* ]]
}
