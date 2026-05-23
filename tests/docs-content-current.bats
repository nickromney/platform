#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
  export DOCS_CONTENT="${REPO_ROOT}/sites/docs/content"
}

@test "docs site covers current platform app surfaces" {
  [ -f "${DOCS_CONTENT}/apps/apim-simulator.mdx" ]
  [ -f "${DOCS_CONTENT}/apps/platform-mcp.mdx" ]
  [ -f "${DOCS_CONTENT}/apps/backstage-idp.mdx" ]

  run grep -R "apps/platform-mcp\\|apps/backstage\\|apps/idp-core\\|apps/idp-mcp\\|apps/idp-sdk" "${DOCS_CONTENT}/apps"
  [ "${status}" -eq 0 ]
}

@test "docs site describes current stage 800/900 observability defaults" {
  run grep -R "VictoriaLogs" "${DOCS_CONTENT}"
  [ "${status}" -eq 0 ]

  run grep -R "enable_loki = false" "${DOCS_CONTENT}"
  [ "${status}" -eq 0 ]
}

@test "docs site treats app-of-apps as optional, not the default" {
  run grep -R "app-of-apps" "${DOCS_CONTENT}"
  [ "${status}" -eq 0 ]

  run grep -R "app-of-apps.*default" "${DOCS_CONTENT}"
  [ "${status}" -ne 0 ]
}

@test "docs site has no references to removed generated media" {
  run grep -R "generated-media\\|ThemeVideo\\|media:render\\|media:still\\|media:studio" "${REPO_ROOT}/sites/docs"
  [ "${status}" -ne 0 ]
}

@test "source docs describe the canonical Go app layout" {
  run rg -n "app-go|apps/apim-simulator/ui|Python/FastAPI simulator|Python backend" \
    "${REPO_ROOT}/docs" \
    "${REPO_ROOT}/apps/README.md"

  [ "${status}" -ne 0 ]
}

@test "apps README covers the canonical Go apps and shared modules" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import (
    apps_readme_go_app_coverage_contract_violations,
    canonical_shared_app_module_names,
)

repo = Path(os.environ["REPO_ROOT"])
violations = apps_readme_go_app_coverage_contract_violations(repo)
assert not violations, violations
print("validated apps README canonical Go app coverage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated apps README canonical Go app coverage"* ]]
}

@test "docs content tests share apps README coverage helpers" {
  run python3 - <<'PY'
from pathlib import Path

from tests.app_contracts import (
    apps_readme_go_app_coverage_contract_violations,
    canonical_shared_app_module_names,
)

test_file = Path("tests/docs-content-current.bats")
content = test_file.read_text(encoding="utf-8")
test_body = content[
    content.index('\n@test "apps README covers the canonical Go apps and shared modules"'):
    content.index('\n@test "source docs use canonical APIM simulator console asset names"')
]
contract_lines = [
    line
    for line in test_body.splitlines()
    if "apps README coverage policy should move" not in line
]

assert callable(apps_readme_go_app_coverage_contract_violations)
assert callable(canonical_shared_app_module_names)
assert "apps_readme_go_app_coverage_contract_violations" in test_body
assert "canonical_shared_app_module_names" in test_body
assert not any("chatgpt-sim" in line for line in contract_lines), "apps README coverage policy should move to tests/app_contracts.py"
assert not any("shared/apphttp" in line for line in contract_lines), "apps README coverage policy should move to tests/app_contracts.py"

print("validated shared apps README coverage helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared apps README coverage helper usage"* ]]
}

@test "source docs use canonical APIM simulator console asset names" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import docs_app_no_npm_apim_asset_contract_violations

repo = Path(os.environ["REPO_ROOT"])
violations = docs_app_no_npm_apim_asset_contract_violations(repo)
assert not violations, violations
PY

  [ "${status}" -eq 0 ]
}

@test "docs content tests share APIM asset contract helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import docs_app_no_npm_apim_asset_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "docs-content-current.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "APIM asset docs policy should move" not in line
]

assert callable(docs_app_no_npm_apim_asset_contract_violations)
assert "docs_app_no_npm_apim_asset_contract_violations" in content
assert not any("apps-no-npm.md" in line for line in contract_lines), "APIM asset docs policy should move to tests/app_contracts.py"
assert not any("styles.css" in line for line in contract_lines), "APIM asset docs policy should move to tests/app_contracts.py"
assert not any("style.css" in line and "APIM" in line for line in contract_lines), "APIM asset docs policy should move to tests/app_contracts.py"

print("validated shared APIM asset docs helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared APIM asset docs helper usage"* ]]
}

@test "ubiquitous language describes sentiment classifier without legacy SST default" {
  run python3 - <<'PY'
import os
from pathlib import Path

text = (Path(os.environ["REPO_ROOT"]) / "docs/ddd/ubiquitous-language.md").read_text()
assert "| classifier | the classification engine | Deterministic lexicon classifier in the default Go runtime; legacy model-backed variants are historical experiments. |" in text
assert "| classifier | the classification model | SST-based analysis engine. |" not in text
PY

  [ "${status}" -eq 0 ]
}

@test "ubiquitous language describes sentiment readiness without legacy warmup default" {
  run python3 - <<'PY'
import os
from pathlib import Path

text = (Path(os.environ["REPO_ROOT"]) / "docs/ddd/ubiquitous-language.md").read_text()
assert "| classifier readiness | whether the classifier can accept requests | The default Go lexicon classifier is available at process start; legacy model-backed warmup is not part of the shipped path. |" in text
assert "| warm on start | preloading the classifier | Readiness state. |" not in text
PY

  [ "${status}" -eq 0 ]
}

@test "ubiquitous language describes subnetcalc lookup without legacy React default" {
  run python3 - <<'PY'
import os
from pathlib import Path

text = (Path(os.environ["REPO_ROOT"]) / "docs/ddd/ubiquitous-language.md").read_text()
expected = (
    "- `lookup` is a **frontend orchestration term**, not a domain term. It is\n"
    "  the browser frontend's name for the composed call over validation,\n"
    "  private-range classification, Cloudflare membership, and subnet info. The\n"
    "  backend does not need a `lookup` endpoint to ship."
)
stale = "the React client's name for the composed call"
assert expected in text
assert stale not in text
PY

  [ "${status}" -eq 0 ]
}

@test "ubiquitous language lists the current service catalog surfaces" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import ddd_current_service_catalog_surface_contract_violations

repo = Path(os.environ["REPO_ROOT"])
violations = ddd_current_service_catalog_surface_contract_violations(repo)
assert not violations, violations
PY

  [ "${status}" -eq 0 ]
}

@test "docs content tests share service catalog surface helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import ddd_current_service_catalog_surface_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "docs-content-current.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "service catalog docs policy should move" not in line
]

assert callable(ddd_current_service_catalog_surface_contract_violations)
assert "ddd_current_service_catalog_surface_contract_violations" in content
assert not any("catalog/platform-apps.json" in line for line in contract_lines), "service catalog docs policy should move to tests/app_contracts.py"
assert not any("for app in catalog" in line for line in contract_lines), "service catalog docs policy should move to tests/app_contracts.py"
assert not any("Current app/environment surfaces include" in line for line in contract_lines), "service catalog docs policy should move to tests/app_contracts.py"

print("validated shared service catalog docs helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared service catalog docs helper usage"* ]]
}

@test "DDD contracts describe vanilla browser app shared types" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import ddd_shared_browser_types_contract_violations

repo = Path(os.environ["REPO_ROOT"])
violations = ddd_shared_browser_types_contract_violations(repo)
assert not violations, violations
PY

  [ "${status}" -eq 0 ]
}

@test "docs content tests share browser type contract helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import ddd_shared_browser_types_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "docs-content-current.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "browser type docs policy should move" not in line
]

assert callable(ddd_shared_browser_types_contract_violations)
assert "ddd_shared_browser_types_contract_violations" in content
assert not any("Shared browser types:" in line for line in contract_lines), "browser type docs policy should move to tests/app_contracts.py"
assert not any("@subnetcalc/shared-frontend" in line for line in contract_lines), "browser type docs policy should move to tests/app_contracts.py"
assert not any("React and TypeScript-Vite" in line for line in contract_lines), "browser type docs policy should move to tests/app_contracts.py"

print("validated shared browser type docs helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared browser type docs helper usage"* ]]
}

@test "Kubernetes app C4 docs describe shipped Go runtimes" {
  run python3 - <<'PY'
import os
from pathlib import Path

from tests.app_contracts import kubernetes_app_c4_go_runtime_docs_contract_violations

repo = Path(os.environ["REPO_ROOT"])
violations = kubernetes_app_c4_go_runtime_docs_contract_violations(repo)
assert not violations, violations
PY

  [ "${status}" -eq 0 ]
}

@test "docs content tests share Kubernetes app C4 runtime helpers" {
  run python3 - <<PY
from pathlib import Path

from tests.app_contracts import kubernetes_app_c4_go_runtime_docs_contract_violations

repo = Path("${REPO_ROOT}")
content = (repo / "tests" / "docs-content-current.bats").read_text(encoding="utf-8")
contract_lines = [
    line
    for line in content.splitlines()
    if "Kubernetes app C4 docs policy should move" not in line
]

assert callable(kubernetes_app_c4_go_runtime_docs_contract_violations)
assert "kubernetes_app_c4_go_runtime_docs_contract_violations" in content
assert not any("apps-c4.md" in line for line in contract_lines), "Kubernetes app C4 docs policy should move to tests/app_contracts.py"
assert not any("SST classifier" in line for line in contract_lines), "Kubernetes app C4 docs policy should move to tests/app_contracts.py"
assert not any("in-process Go lexicon classifier" in line for line in contract_lines), "Kubernetes app C4 docs policy should move to tests/app_contracts.py"

print("validated shared Kubernetes app C4 docs helper usage")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared Kubernetes app C4 docs helper usage"* ]]
}

@test "docs site has reader paths, contracts, and footguns pages in navigation" {
  [ -f "${DOCS_CONTENT}/concepts/reader-paths.mdx" ]
  [ -f "${DOCS_CONTENT}/reference/contracts.mdx" ]
  [ -f "${DOCS_CONTENT}/operations/footguns.mdx" ]

  run grep -E "reader-paths|contracts|footguns" "${REPO_ROOT}/sites/docs/app/_meta.global.tsx"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"reader-paths"* ]]
  [[ "${output}" == *"contracts"* ]]
  [[ "${output}" == *"footguns"* ]]
}

@test "contracts page defines the platform's operational boundaries" {
  run grep -E "Operator entrypoints|Stage shape|GitOps source|Route surface|Identity|Policy|Docs media" "${DOCS_CONTENT}/reference/contracts.mdx"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Operator entrypoints"* ]]
  [[ "${output}" == *"Stage shape"* ]]
  [[ "${output}" == *"GitOps source"* ]]
  [[ "${output}" == *"Route surface"* ]]
  [[ "${output}" == *"Docs media"* ]]
}

@test "reader paths page serves beginners and experienced engineers" {
  run grep -E "TLDR For Experienced Engineers|New To This Project|New To The Technology|Daily Operators" "${DOCS_CONTENT}/concepts/reader-paths.mdx"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"TLDR For Experienced Engineers"* ]]
  [[ "${output}" == *"New To This Project"* ]]
  [[ "${output}" == *"New To The Technology"* ]]
  [[ "${output}" == *"Daily Operators"* ]]
}

@test "footguns page covers high-risk local platform mistakes" {
  run grep -E "Stage And Runtime Gotchas|Kubeconfig Gotchas|GitOps Gotchas|Image Gotchas|Route And Auth Gotchas|Policy Gotchas|Docs Gotchas" "${DOCS_CONTENT}/operations/footguns.mdx"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Stage And Runtime Gotchas"* ]]
  [[ "${output}" == *"Kubeconfig Gotchas"* ]]
  [[ "${output}" == *"GitOps Gotchas"* ]]
  [[ "${output}" == *"Route And Auth Gotchas"* ]]
  [[ "${output}" == *"Docs Gotchas"* ]]
}
