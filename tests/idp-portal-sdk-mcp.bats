#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "developer portal SDK and MCP surfaces exist with an HTTP API boundary" {
  for path in \
    apps/idp-portal/package.json \
    apps/idp-portal/index.html \
    apps/idp-portal/src/App.tsx \
    apps/idp-portal/src/main.tsx \
    apps/idp-sdk/package.json \
    apps/idp-sdk/src/index.ts \
    apps/idp-mcp/pyproject.toml \
    apps/idp-mcp/idp_mcp/server.py
  do
    [ -f "${REPO_ROOT}/${path}" ]
  done

  run rg -n 'createRoot|<App />|VITE_IDP_API_BASE_URL|/api/v1/catalog/apps|/api/v1/runtime' "${REPO_ROOT}/apps/idp-portal"
  [ "${status}" -eq 0 ]

  run rg -n 'class IdpClient|fetch\(|listApps|getRuntime|/api/v1/catalog/apps|/api/v1/environments|/api/v1/deployments/promote' "${REPO_ROOT}/apps/idp-sdk/src/index.ts"
  [ "${status}" -eq 0 ]

  run rg -n 'IDP_API_BASE_URL|urllib.request|platform_status|catalog_list|environment_create|/api/v1/catalog/apps|/api/v1/environments' "${REPO_ROOT}/apps/idp-mcp/idp_mcp/server.py"
  [ "${status}" -eq 0 ]
}

@test "IDP browser SDK portal and MCP default to public portal HTTPS FQDNs" {
  run rg -n 'DEFAULT_IDP_API_BASE_URL = "https://portal-api\.127\.0\.0\.1\.sslip\.io"' "${REPO_ROOT}/apps/idp-sdk/src/index.ts"
  [ "${status}" -eq 0 ]

  run rg -n 'DEFAULT_IDP_API_BASE_URL = "https://portal-api\.127\.0\.0\.1\.sslip\.io"' "${REPO_ROOT}/apps/idp-portal/src/App.tsx"
  [ "${status}" -eq 0 ]

  run rg -n 'DEFAULT_IDP_API_BASE_URL = "https://portal-api\.127\.0\.0\.1\.sslip\.io"' "${REPO_ROOT}/apps/idp-mcp/idp_mcp/server.py"
  [ "${status}" -eq 0 ]

  run rg -n 'Developer Portal|Portal API' \
    "${REPO_ROOT}/apps/idp-portal/src/App.tsx" \
    "${REPO_ROOT}/terraform/kubernetes/config/platform-launchpad.apps.json" \
    "${REPO_ROOT}/catalog/platform-apps.json"
  [ "${status}" -eq 0 ]
}

@test "IDP MCP wrapper calls HTTP APIs rather than direct operator scripts" {
  run rg -n 'subprocess|os\\.system|Popen|kubectl|make -C|scripts/' \
    "${REPO_ROOT}/apps/idp-portal" \
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
