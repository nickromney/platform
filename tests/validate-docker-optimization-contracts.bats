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

@test "local platform image build and sync contracts include IDP images" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")
sync_script = (repo_root / "terraform/kubernetes/scripts/sync-gitea.sh").read_text(encoding="utf-8")
policies_script = (repo_root / "terraform/kubernetes/scripts/sync-gitea-policies.sh").read_text(encoding="utf-8")
gitops_tf = (repo_root / "terraform/kubernetes/gitops.tf").read_text(encoding="utf-8")
variables_tf = (repo_root / "terraform/kubernetes/variables.tf").read_text(encoding="utf-8")
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")

for image_name, dockerfile_path in {
    "idp-core": "apps/idp-core/Dockerfile",
    "backstage": "apps/backstage/Dockerfile",
    "platform-mcp": "apps/platform-mcp/Dockerfile",
}.items():
    assert f'"{image_name}"' in build_script, image_name
    assert dockerfile_path in build_script, dockerfile_path
    if image_name == "idp-core":
        assert f'"${{REPO_ROOT}}" \\\n  "${{REPO_ROOT}}/{dockerfile_path}"' in build_script, dockerfile_path
    elif image_name == "backstage":
        assert '"${REPO_ROOT}/apps/backstage"' in build_script
        assert '"${REPO_ROOT}/apps/backstage/Dockerfile"' in build_script
    else:
        assert f'"${{REPO_ROOT}}" \\\n  "${{REPO_ROOT}}/{dockerfile_path}"' in build_script, dockerfile_path
    if image_name == "platform-mcp":
        assert f'lookup(var.external_workload_image_refs, "{image_name}", "")' in locals_tf, image_name
    else:
        assert f'lookup(var.external_platform_image_refs, "{image_name}", "")' in locals_tf, image_name
    assert image_name in variables_tf, image_name

assert "EXTERNAL_PLATFORM_IMAGE_BACKSTAGE" in sync_script
assert "EXTERNAL_PLATFORM_IMAGE_IDP_CORE" in sync_script
assert "export_resolved_bool_target_or_stage PREFER_EXTERNAL_WORKLOAD_IMAGES prefer_external_workload_images false" in sync_script
assert "resolve_external_workload_image()" in sync_script
assert "export_external_workload_image EXTERNAL_IMAGE_PLATFORM_MCP platform-mcp" in sync_script
assert "EXTERNAL_IMAGE_PLATFORM_MCP" in gitops_tf
assert "EXTERNAL_PLATFORM_IMAGE_BACKSTAGE" in policies_script
assert "EXTERNAL_PLATFORM_IMAGE_IDP_CORE" in policies_script
assert "EXTERNAL_IMAGE_PLATFORM_MCP" in policies_script
assert "ensure_grafana_dashboard_provider_paths" in policies_script
assert "/^    path:[[:space:]]*/" in policies_script
assert "/var/lib/grafana/dashboards/default" in policies_script
assert "/var/lib/grafana/dashboards/kubernetes" in policies_script
assert "/var/lib/grafana/dashboards/cilium" in policies_script
assert "/var/lib/grafana/dashboards/argocd" in policies_script
assert 'EXTERNAL_PLATFORM_IMAGE_BACKSTAGE             = lookup(var.external_platform_image_refs, "backstage", "")' in gitops_tf
assert 'EXTERNAL_PLATFORM_IMAGE_IDP_CORE              = lookup(var.external_platform_image_refs, "idp-core", "")' in gitops_tf
assert 'EXTERNAL_IMAGE_PLATFORM_MCP                   = lookup(var.external_workload_image_refs, "platform-mcp", "")' in gitops_tf
assert 'replace_image_ref "${idp_manifest}" "backstage" "${EXTERNAL_PLATFORM_IMAGE_BACKSTAGE}"' in policies_script
assert 'replace_image_ref "${idp_manifest}" "idp-core" "${EXTERNAL_PLATFORM_IMAGE_IDP_CORE}"' in policies_script
assert 'replace_image_ref "${workload_file}" "platform-mcp" "${EXTERNAL_IMAGE_PLATFORM_MCP}"' in policies_script
assert "external_platform_backstage" in locals_tf
assert "external_platform_idp_core" in locals_tf
assert "external_platform_mcp" in locals_tf

kind_makefile = (repo_root / "kubernetes/kind/Makefile").read_text(encoding="utf-8")
assert 'GITEA_SYNC_TARGET_TFVARS_FILE="$${GITEA_SYNC_TARGET_TFVARS_FILE:-$(KIND_OPERATOR_OVERRIDES_FILE)}"' in kind_makefile

print("validated local platform IDP image build and sync contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local platform IDP image build and sync contract"* ]]
}

@test "local platform IDP image cache keys include source fingerprints" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")

assert "source_fingerprint_tag()" in build_script
assert "idp_core_source_tag=" in build_script
assert "backstage_source_tag=" in build_script
assert "platform_mcp_source_tag=" in build_script
assert '"idp-core" \\' in build_script and '"${idp_core_source_tag}"' in build_script
assert '"backstage" \\' in build_script and '"${backstage_source_tag}"' in build_script
assert '"platform-mcp" \\' in build_script and '"${platform_mcp_source_tag}"' in build_script
assert 'tag_exists_in_cache "${CACHE_PUSH_HOST}" "${repo}" "${fingerprint_tag}"' in build_script

render_script = (repo_root / "kubernetes/kind/scripts/render-operator-overrides.sh").read_text(encoding="utf-8")
assert "platform_mcp_image_tag=" in render_script
assert "idp_core_image_tag=" in render_script
assert "backstage_image_tag=" in render_script
assert "write_external_platform_images()" in render_script
assert "prefer_external_platform_images = true" in render_script
assert "external_platform_image_refs = {" in render_script
assert "apps/platform-mcp/platform_mcp" in render_script
assert "apps/idp-core/app" in render_script
assert "apps/backstage/packages" in render_script
assert "platform/platform-mcp:${platform_mcp_image_tag}" in render_script
assert "platform/backstage:${backstage_image_tag:-latest}" in render_script
assert "platform/idp-core:${idp_core_image_tag}" in render_script
assert "platform/grafana-victorialogs:latest" in render_script

print("validated local platform IDP source fingerprint cache keys")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local platform IDP source fingerprint cache keys"* ]]
}

@test "Lima and Slicer targets route local platform IDP images through their host cache" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])

expectations = {
    "kubernetes/lima/targets/lima.tfvars": "host.lima.internal:5002",
    "kubernetes/slicer/targets/slicer.tfvars": "192.168.64.1:5002",
}

for relative_path, registry_host in expectations.items():
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    assert "prefer_external_platform_images = true" in content, relative_path
    assert f'"idp-core"   = "{registry_host}/platform/idp-core:latest"' in content, relative_path
    assert f'backstage   = "{registry_host}/platform/backstage:latest"' in content, relative_path

print("validated Lima and Slicer IDP image cache refs")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Lima and Slicer IDP image cache refs"* ]]
}

@test "local platform IDP cache hits are not invalidated by unrelated git commits" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")

skip_start = build_script.index('if [ "${FORCE_REBUILD}" != "1" ]')
skip_end = build_script.index('echo "OK   cached ${version_ref}"', skip_start)
skip_condition = build_script[skip_start:skip_end]

assert "${fingerprint_tag}" in skip_condition
assert "${commit_tag}" not in skip_condition
assert 'docker_push_local_registry "${commit_ref}"' in build_script

print("validated local platform IDP cache hits ignore unrelated git commits")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local platform IDP cache hits ignore unrelated git commits"* ]]
}

@test "platform MCP Docker image uses DHI bases and installs gzip for pinned D2 tarball extraction" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])
dockerfile = (repo_root / "apps/platform-mcp/Dockerfile").read_text(encoding="utf-8")

assert "FROM dhi.io/python:3.13-debian13-dev AS builder" in dockerfile
assert "FROM dhi.io/python:3.13-debian13-dev AS d2" in dockerfile
assert "FROM dhi.io/python:3.13-debian13 AS runtime" in dockerfile
assert "ARG D2_VERSION=0.7.1" in dockerfile
assert "sha256sum -c -" in dockerfile
assert "apt-get install -y --no-install-recommends ca-certificates curl gzip tar" in dockerfile
assert "mkdir -p /usr/local/bin" in dockerfile
assert "tar -xzf /tmp/d2.tar.gz" in dockerfile
assert "USER 65532:65532" in dockerfile

print("validated platform MCP Docker image contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform MCP Docker image contract"* ]]
}
