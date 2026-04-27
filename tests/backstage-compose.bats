#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "docker compose has a Backstage portal profile with hardened local runtime" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "docker/compose/compose.yml").read_text(encoding="utf-8"))
services = compose["services"]

assert "backstage" in services, "compose must include Backstage before Kubernetes proof"
backstage = services["backstage"]
assert backstage["profiles"] == ["portal"]
assert backstage["build"] == {"context": "../../apps/backstage", "dockerfile": "Dockerfile"}
assert backstage["image"] == "platform-backstage:compose"
assert backstage["read_only"] is True
assert backstage["cap_drop"] == ["ALL"]
assert backstage["security_opt"] == ["no-new-privileges:true"]
assert "/tmp:rw,noexec,nosuid,nodev,mode=1777" in backstage["tmpfs"]
assert backstage["environment"]["BACKSTAGE_BASE_URL"] == "https://portal.compose.127.0.0.1.sslip.io:8443"
assert backstage["environment"]["GITEA_BASE_URL"] == "http://gitea-not-present.compose.invalid"
assert backstage["environment"]["GITEA_OWNER"] == "platform"
assert backstage["environment"]["GITEA_OWNER_IS_ORG"] == "true"
assert backstage["healthcheck"]["test"][:2] == ["CMD", "node"]
assert any("http://127.0.0.1:7007/api/app/health" in item for item in backstage["healthcheck"]["test"])
assert "shell" not in " ".join(backstage["healthcheck"]["test"]).lower()

print("validated compose Backstage portal runtime")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated compose Backstage portal runtime"* ]]
}

@test "docker compose routes Backstage through Dex and oauth2-proxy" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "docker/compose/compose.yml").read_text(encoding="utf-8"))
services = compose["services"]
dex = yaml.safe_load((repo_root / "docker/compose/dex/config.yaml").read_text(encoding="utf-8"))
gateway = (repo_root / "docker/compose/gateway/default.conf").read_text(encoding="utf-8")
certs = (repo_root / "docker/compose/pki/gen-certs.sh").read_text(encoding="utf-8")

proxy = services["oauth2-proxy-backstage"]
command = proxy["command"]

assert proxy["profiles"] == ["portal"]
assert proxy["image"] == "dhi.io/oauth2-proxy:7.15.2-debian13"
assert proxy["cap_drop"] == ["ALL"]
assert proxy["security_opt"] == ["no-new-privileges:true"]
assert "--provider=oidc" in command
assert "--oidc-issuer-url=https://dex.compose.127.0.0.1.sslip.io:8443/dex" in command
assert "--redirect-url=https://portal.compose.127.0.0.1.sslip.io:8443/oauth2/callback" in command
assert "--upstream=http://backstage:7007" in command
assert "--cookie-name=compose-sso-portal" in command
assert "--email-domain=*" in command
assert "--pass-user-headers=true" in command
assert proxy["depends_on"]["backstage"]["condition"] == "service_started"
assert proxy["depends_on"]["dex"]["condition"] == "service_started"

redirects = dex["staticClients"][0]["redirectURIs"]
assert "https://portal.compose.127.0.0.1.sslip.io:8443/oauth2/callback" in redirects

assert "portal.compose.127.0.0.1.sslip.io" in gateway
assert "set $upstream http://oauth2-proxy-backstage:4180;" in gateway
assert "portal.compose.127.0.0.1.sslip.io" in certs

print("validated compose Backstage SSO route")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated compose Backstage SSO route"* ]]
}

@test "docker compose make targets expose a Backstage-first red green proof" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
makefile = (repo_root / "docker/compose/Makefile").read_text(encoding="utf-8")
readme = (repo_root / "docker/compose/README.md").read_text(encoding="utf-8")
script = repo_root / "docker/compose/scripts/check-backstage.sh"
browser_spec = repo_root / "tests/kubernetes/sso/tests/compose-backstage-smoke.spec.ts"

assert script.is_file(), "compose Backstage smoke script must exist"
assert browser_spec.is_file(), "compose Backstage browser smoke test must exist"
script_text = script.read_text(encoding="utf-8")
browser_text = browser_spec.read_text(encoding="utf-8")
assert "portal.compose.127.0.0.1.sslip.io" in script_text
assert "/api/app/health" in script_text
assert "oauth2-proxy-backstage" in script_text
assert "portal.compose.127.0.0.1.sslip.io" in browser_text
assert "dex.compose.127.0.0.1.sslip.io" in browser_text
assert "Developer Portal" in browser_text
assert "Hello Platform" in browser_text
assert "isOauth2ProxyForbiddenPage" in browser_text

assert "up-portal" in makefile
assert "check-backstage" in makefile
assert "test-backstage" in makefile
assert "--profile dev --profile uat --profile portal config -q" in makefile
assert "--profile portal up -d --build edge dex backstage oauth2-proxy-backstage" in makefile
assert "bats ../../tests/backstage-compose.bats" in makefile
assert "COMPOSE_BACKSTAGE_E2E=1" in makefile
assert "bun x playwright test tests/compose-backstage-smoke.spec.ts --config playwright.config.ts" in makefile

assert "https://portal.compose.127.0.0.1.sslip.io:8443" in readme
assert "make -C docker/compose test-backstage" in readme
assert "Backstage" in readme

print("validated compose Backstage red green entrypoints")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated compose Backstage red green entrypoints"* ]]
}
