#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "platform MCP app compose file runs the server and inspector with local hardening" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "apps/platform-mcp/compose.yml").read_text(encoding="utf-8"))
services = compose["services"]

server = services["platform-mcp"]
assert server["build"] == {"context": "../..", "dockerfile": "apps/platform-mcp/Dockerfile"}
assert server["image"] == "platform-mcp:compose"
assert server["read_only"] is True
assert server["cap_drop"] == ["ALL"]
assert server["security_opt"] == ["no-new-privileges:true"]
assert "/tmp:rw,noexec,nosuid,nodev,mode=1777" in server["tmpfs"]
assert server["environment"]["PLATFORM_MCP_PATH"] == "/mcp"
assert server["environment"]["PLATFORM_MCP_METRICS_ENABLED"] == "true"
assert server["environment"]["OTEL_SERVICE_NAME"] == "platform-mcp"
assert "${PLATFORM_MCP_COMPOSE_HTTP_PORT:-8089}:8080" in server["ports"]
assert "${PLATFORM_MCP_COMPOSE_METRICS_PORT:-9099}:9090" in server["ports"]
assert any("http://127.0.0.1:8080/health" in item for item in server["healthcheck"]["test"])

inspector = services["mcp-inspector"]
assert inspector["image"] == "ghcr.io/modelcontextprotocol/inspector:0.21.2"
assert inspector["read_only"] is True
assert inspector["cap_drop"] == ["ALL"]
assert inspector["security_opt"] == ["no-new-privileges:true"]
assert inspector["environment"]["MCP_AUTO_OPEN_ENABLED"] == "false"
assert inspector["environment"]["MCP_PROXY_AUTH_TOKEN"] == ""
assert inspector["environment"]["MCP_SERVER_URL"] == "http://platform-mcp:8080/mcp"
assert inspector["environment"]["MCP_TRANSPORT_TYPE"] == "streamable-http"
assert "${MCP_INSPECTOR_COMPOSE_UI_PORT:-6274}:6274" in inspector["ports"]
assert "${MCP_INSPECTOR_COMPOSE_PROXY_PORT:-6277}:6277" in inspector["ports"]
assert inspector["depends_on"]["platform-mcp"]["condition"] == "service_healthy"

print("validated platform MCP compose topology")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform MCP compose topology"* ]]
}

@test "platform MCP compose smoke is exposed through the apps Makefile" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
script = repo_root / "apps/platform-mcp/tests/compose-smoke.sh"
makefile = (repo_root / "apps/Makefile").read_text(encoding="utf-8")
readme = (repo_root / "apps/platform-mcp/README.md").read_text(encoding="utf-8")

assert script.is_file(), "compose smoke script must exist"
script_text = script.read_text(encoding="utf-8")
assert "compose_cli -f \"${APP_DIR}/compose.yml\"" in script_text
assert "platform-mcp mcp-inspector" in script_text
assert "PLATFORM_MCP_URL=\"http://localhost:${http_port}/mcp\"" in script_text
assert "platform_mcp.smoke" in script_text
assert "compose-smoke-platform-mcp" in makefile
assert "./platform-mcp/tests/compose-smoke.sh --execute" in makefile
assert "apps/platform-mcp/compose.yml" in readme
assert "http://localhost:8089/mcp" in readme
assert "http://localhost:6274" in readme

print("validated platform MCP compose smoke entrypoint")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform MCP compose smoke entrypoint"* ]]
}
