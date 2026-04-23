#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "react server runtime image stays dependency-free" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
content = (repo_root / "apps/subnetcalc/frontend-react/Dockerfile.server").read_text(encoding="utf-8")

assert " AS deps" not in content, content
assert "node_modules" not in content, content
assert "--production" not in content, content
assert 'CMD ["node", "server.js"]' in content, content

print("validated dependency-free react server runtime image")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated dependency-free react server runtime image"* ]]
}

@test "dockerfiles use package-manager and compiler cache mounts" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

expectations = {
    "apps/subnetcalc/frontend-typescript-vite/Dockerfile": [
        "--mount=type=cache,target=/root/.bun/install/cache",
        "--mount=type=cache,target=/root/.cache/go-build",
        "--mount=type=cache,target=/go/pkg/mod",
    ],
    "apps/subnetcalc/frontend-react/Dockerfile": [
        "--mount=type=cache,target=/root/.bun/install/cache",
        "--mount=type=cache,target=/root/.cache/go-build",
        "--mount=type=cache,target=/go/pkg/mod",
    ],
    "apps/subnetcalc/frontend-react/Dockerfile.server": [
        "--mount=type=cache,target=/root/.bun/install/cache",
    ],
    "apps/subnetcalc/frontend-python-flask/Dockerfile": [
        "--mount=type=cache,target=/root/.cache/uv",
    ],
    "apps/subnetcalc/api-fastapi-container-app/Dockerfile": [
        "--mount=type=cache,target=/root/.cache/uv",
    ],
    "apps/subnetcalc/api-fastapi-azure-function/Dockerfile": [
        "--mount=type=cache,target=/root/.cache/uv",
    ],
    "apps/subnetcalc/api-fastapi-azure-function/Dockerfile.uvicorn": [
        "--mount=type=cache,target=/root/.cache/uv",
    ],
    "apps/subnetcalc/apim-simulator/Dockerfile": [
        "--mount=type=cache,target=/root/.cache/uv",
    ],
}

validated = 0
for relative_path, required_fragments in expectations.items():
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    for fragment in required_fragments:
        assert fragment in content, (relative_path, fragment)
        validated += 1

print(f"validated {validated} docker cache mount expectation(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 12 docker cache mount expectation(s)"* ]]
}

@test "python dockerfiles use uv cache mounts with explicit copy link mode" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

dockerfiles = [
    "apps/subnetcalc/frontend-python-flask/Dockerfile",
    "apps/subnetcalc/api-fastapi-container-app/Dockerfile",
    "apps/subnetcalc/api-fastapi-azure-function/Dockerfile",
    "apps/subnetcalc/api-fastapi-azure-function/Dockerfile.uvicorn",
    "apps/subnetcalc/apim-simulator/Dockerfile",
]

for relative_path in dockerfiles:
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    assert "--mount=type=cache,target=/root/.cache/uv" in content, relative_path
    assert "--link-mode=copy" in content, relative_path
    assert "--no-cache" not in content, relative_path

print(f"validated {len(dockerfiles)} uv dockerfile cache policy expectation(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 5 uv dockerfile cache policy expectation(s)"* ]]
}

@test "compose files harden additional subnetcalc runtime services" {
  run uv run --isolated --with pyyaml python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])

nginx_tmpfs = [
    "/tmp:rw,noexec,nosuid,nodev,uid=65532,gid=65532,mode=1777",
    "/var/cache/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
    "/var/run/nginx:rw,noexec,nosuid,nodev,uid=65532,gid=65532",
]
app_tmpfs = ["/tmp:rw,noexec,nosuid,nodev,mode=1777"]

expectations = {
    "apps/subnetcalc/compose.yml": {
        "frontend-html-static": nginx_tmpfs,
        "frontend-python-flask": app_tmpfs,
        "frontend-python-flask-container-app": app_tmpfs,
        "frontend-typescript-vite-jwt": nginx_tmpfs,
        "frontend-react-jwt": nginx_tmpfs,
        "frontend-react-msal": nginx_tmpfs,
        "frontend-react-server-jwt": app_tmpfs,
        "frontend-react-proxy": app_tmpfs,
        "frontend-react-keycloak": nginx_tmpfs,
        "frontend-typescript-vite-gateway": nginx_tmpfs,
        "frontend-typescript-vite-gateway-admin": nginx_tmpfs,
        "apim-simulator": app_tmpfs,
        "frontend-typescript-vite-easyauth-mock": nginx_tmpfs,
        "easyauth-router": nginx_tmpfs,
    },
    "docker/compose/compose.yml": {
        "apim-simulator": app_tmpfs,
    },
}

validated = 0
for relative_path, services in expectations.items():
    compose = yaml.safe_load((repo_root / relative_path).read_text(encoding="utf-8"))
    for service_name, required_tmpfs in services.items():
        service = compose["services"][service_name]
        assert service.get("read_only") is True, (relative_path, service_name, "read_only", service.get("read_only"))
        assert service.get("cap_drop") == ["ALL"], (relative_path, service_name, "cap_drop", service.get("cap_drop"))
        assert service.get("security_opt") == ["no-new-privileges:true"], (
            relative_path,
            service_name,
            "security_opt",
            service.get("security_opt"),
        )
        tmpfs_entries = service.get("tmpfs", [])
        for required in required_tmpfs:
            assert required in tmpfs_entries, (relative_path, service_name, required, tmpfs_entries)
        validated += 1

print(f"validated {validated} hardened compose service(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 15 hardened compose service(s)"* ]]
}

@test "docker build audit script captures logs sizes and warnings" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
script = repo_root / "scripts/audit-docker-builds.sh"

assert script.exists(), script
content = script.read_text(encoding="utf-8")

required_fragments = [
    "--progress=plain",
    "docker history",
    "docker image inspect",
    "warning",
    "frontend-typescript-vite/Dockerfile",
    "frontend-react/Dockerfile",
    "frontend-react/Dockerfile.server",
    "frontend-python-flask/Dockerfile",
    "api-fastapi-container-app/Dockerfile",
    "apim-simulator/Dockerfile",
]

for fragment in required_fragments:
    assert fragment in content, fragment

print("validated docker build audit tooling contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated docker build audit tooling contract"* ]]
}

@test "grafana plugin image build uses a host-verified archive instead of downloading in Dockerfile" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
dockerfile = (repo_root / "kubernetes/kind/images/grafana-victorialogs/Dockerfile").read_text(encoding="utf-8")
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")
variables_tf = (repo_root / "terraform/kubernetes/variables.tf").read_text(encoding="utf-8")

assert 'grafana_victoria_logs_plugin_version' in variables_tf, "missing explicit plugin version variable"
assert 'grafana_victoria_logs_plugin_sha256' in variables_tf, "missing explicit plugin checksum variable"
assert "curl -fsSL" not in dockerfile, dockerfile
assert "apk add" not in dockerfile, dockerfile
assert "busybox unzip" in dockerfile, dockerfile
assert "COPY " in dockerfile and "victorialogs.zip" in dockerfile, dockerfile
assert "tf_default_from_variables grafana_victoria_logs_plugin_version" in build_script, build_script
assert "tf_default_from_variables grafana_victoria_logs_plugin_sha256" in build_script, build_script
assert "shasum -a 256" in build_script, build_script

print("validated grafana plugin archive mirroring contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated grafana plugin archive mirroring contract"* ]]
}
