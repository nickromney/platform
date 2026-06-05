#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "Backstage portal SDK and MCP surfaces exist with an HTTP API boundary" {
  for path in \
    apps/backstage/package.json \
    apps/backstage/app-config.production.yaml \
    apps/backstage/catalog/entities.yaml \
    apps/backstage/catalog/templates/platform-service/template.yaml \
    apps/idp-sdk/package.json \
    apps/idp-sdk/src/index.ts \
    apps/idp-mcp/pyproject.toml \
    apps/idp-mcp/idp_mcp/server.py
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done

  run rg -n 'Backstage|scaffolder|catalog|Template|platform-service-request|portal-api\.127\.0\.0\.1\.sslip\.io|backstage' "${REPO_ROOT}/apps/backstage"
  [ "${status}" -eq 0 ]

  run rg -n 'class IdpClient|fetch\(|listApps|getRuntime|/api/v1/catalog/apps|/api/v1/environments|/api/v1/deployments/promote' "${REPO_ROOT}/apps/idp-sdk/src/index.ts"
  [ "${status}" -eq 0 ]

  for path in \
    apps/idp-sdk/src/index.ts
  do
    run rg -n 'credentials: "include"' "${REPO_ROOT}/${path}"
    [ "${status}" -eq 0 ]
  done

  run rg -n 'IDP_API_BASE_URL|urllib.request|platform_status|catalog_list|environment_create|/api/v1/catalog/apps|/api/v1/environments' "${REPO_ROOT}/apps/idp-mcp/idp_mcp/server.py"
  [ "${status}" -eq 0 ]
}

@test "IDP SDK, MCP, and Backstage default to public portal HTTPS FQDNs" {
  run rg -n 'DEFAULT_IDP_API_BASE_URL = "https://portal-api\.127\.0\.0\.1\.sslip\.io"' "${REPO_ROOT}/apps/idp-sdk/src/index.ts"
  [ "${status}" -eq 0 ]

  run rg -n 'https://portal-api\.127\.0\.0\.1\.sslip\.io|https://portal\.127\.0\.0\.1\.sslip\.io' "${REPO_ROOT}/apps/backstage"
  [ "${status}" -eq 0 ]

  run rg -n 'DEFAULT_IDP_API_BASE_URL = "https://portal-api\.127\.0\.0\.1\.sslip\.io"' "${REPO_ROOT}/apps/idp-mcp/idp_mcp/server.py"
  [ "${status}" -eq 0 ]

  run rg -n 'Developer Portal|Portal API' \
    "${REPO_ROOT}/apps/backstage" \
    "${REPO_ROOT}/terraform/kubernetes/config/platform-launchpad.apps.json" \
    "${REPO_ROOT}/catalog/platform-apps.json"
  [ "${status}" -eq 0 ]
}

@test "IDP MCP wrapper calls HTTP APIs rather than direct operator scripts" {
  run rg -n 'subprocess|os\\.system|Popen|kubectl|make -C|scripts/' \
    "${REPO_ROOT}/apps/idp-sdk" \
    "${REPO_ROOT}/apps/idp-mcp"
  [ "${status}" -ne 0 ]

  run uv run --isolated python - <<'PY'
from __future__ import annotations

import ast
import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
server = repo_root / "apps/idp-mcp/idp_mcp/server.py"
tree = ast.parse(server.read_text())

imports = {
    alias.name
    for node in ast.walk(tree)
    if isinstance(node, ast.Import)
    for alias in node.names
}
from_imports = {
    node.module
    for node in ast.walk(tree)
    if isinstance(node, ast.ImportFrom) and node.module
}

blocked = {"subprocess"}
assert not (imports | from_imports) & blocked

source = server.read_text()
assert "urllib.request.Request" in source
assert "POST" in source
assert "GET" in source
print("validated HTTP-only MCP wrapper")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated HTTP-only MCP wrapper"* ]]
}

@test "IDP SDK and MCP share named API path registries" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import ast
import os
import re
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
sdk = (repo_root / "apps/idp-sdk/src/index.ts").read_text(encoding="utf-8")
mcp = (repo_root / "apps/idp-mcp/idp_mcp/server.py").read_text(encoding="utf-8")

assert "IDP_API_PATHS" in sdk, "SDK should centralize endpoint strings in IDP_API_PATHS"
assert "IDP_API_PATHS" in mcp, "MCP should centralize endpoint strings in IDP_API_PATHS"

sdk_paths = dict(re.findall(r"(\w+):\s*\"(/[^\"]+)\"", sdk))
tree = ast.parse(mcp)
mcp_paths: dict[str, str] = {}
for node in tree.body:
    if isinstance(node, ast.Assign) and any(isinstance(target, ast.Name) and target.id == "IDP_API_PATHS" for target in node.targets):
        for key, value in zip(node.value.keys, node.value.values, strict=True):
            if isinstance(key, ast.Constant) and isinstance(value, ast.Constant):
                mcp_paths[str(key.value)] = str(value.value)

expected = {
    "runtime": "/api/v1/runtime",
    "status": "/api/v1/status",
    "catalogApps": "/api/v1/catalog/apps",
    "environments": "/api/v1/environments",
    "deploymentPromote": "/api/v1/deployments/promote",
}
for key, path in expected.items():
    assert sdk_paths.get(key) == path, (key, sdk_paths.get(key))
    assert mcp_paths.get(key) == path, (key, mcp_paths.get(key))

for raw_path in expected.values():
    assert sdk.count(f'"{raw_path}"') == 1, f"SDK should declare {raw_path} once"
    assert mcp.count(f'"{raw_path}"') == 1, f"MCP should declare {raw_path} once"

print("validated named IDP API path registries")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated named IDP API path registries"* ]]
}
