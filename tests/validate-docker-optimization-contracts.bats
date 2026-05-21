#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
}

@test "subnetcalc Go runtime image stays package-manager-free" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])
content = (repo_root / "apps/subnetcalc/app/Dockerfile").read_text(encoding="utf-8")

assert "node_modules" not in content, content
assert "bun" not in content.lower(), content
assert "npm" not in content.lower(), content
assert "python" not in content.lower(), content
assert 'ENTRYPOINT ["/subnetcalc"]' in content, content

print("validated package-manager-free subnetcalc Go runtime image")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated package-manager-free subnetcalc Go runtime image"* ]]
}

@test "remaining app dockerfiles use only current cache mounts" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

expectations = {
    "apps/apim-simulator/Dockerfile": [
        "--mount=type=cache,target=/root/.cache/uv",
    ],
}

validated = 0
for relative_path, required_fragments in expectations.items():
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    assert not content.startswith("# syntax=docker/dockerfile"), relative_path
    for fragment in required_fragments:
        assert fragment in content, (relative_path, fragment)
        validated += 1

print(f"validated {validated} docker cache mount expectation(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 1 docker cache mount expectation(s)"* ]]
}

@test "remaining Python dockerfiles use uv cache mounts with explicit copy link mode" {
  run uv run --isolated python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

repo_root = Path(os.environ["REPO_ROOT"])

dockerfiles = [
    "apps/apim-simulator/Dockerfile",
]

for relative_path in dockerfiles:
    content = (repo_root / relative_path).read_text(encoding="utf-8")
    assert "--mount=type=cache,target=/root/.cache/uv" in content, relative_path
    assert "--link-mode=copy" in content, relative_path
    assert "--no-cache" not in content, relative_path

print(f"validated {len(dockerfiles)} uv dockerfile cache policy expectation(s)")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 1 uv dockerfile cache policy expectation(s)"* ]]
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
        "subnetcalc-backend": app_tmpfs,
        "subnetcalc-frontend": app_tmpfs,
    },
    "docker/compose/compose.yml": {
        "apim-simulator": app_tmpfs,
        "subnetcalc-api-dev": app_tmpfs,
        "subnetcalc-api-uat": app_tmpfs,
        "subnetcalc-frontend-dev": app_tmpfs,
        "subnetcalc-frontend-uat": app_tmpfs,
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
  [[ "${output}" == *"validated 7 hardened compose service(s)"* ]]
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
    "apps/subnetcalc/app/Dockerfile",
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
image_catalog = (repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8")
variables_tf = (repo_root / "terraform/kubernetes/variables.tf").read_text(encoding="utf-8")

assert 'grafana_victoria_logs_plugin_version' in variables_tf, "missing explicit plugin version variable"
assert 'grafana_victoria_logs_plugin_sha256' in variables_tf, "missing explicit plugin checksum variable"
assert "curl -fsSL" not in dockerfile, dockerfile
assert "apk add" not in dockerfile, dockerfile
assert "busybox unzip" in dockerfile, dockerfile
assert "COPY " in dockerfile and "victorialogs.zip" in dockerfile, dockerfile
assert '"terraform_version_variable": "grafana_victoria_logs_plugin_version"' in image_catalog, image_catalog
assert '"terraform_sha256_variable": "grafana_victoria_logs_plugin_sha256"' in image_catalog, image_catalog
assert 'tf_default_from_variables "${VICTORIA_LOGS_PLUGIN_VERSION_VAR}"' in build_script, build_script
assert 'tf_default_from_variables "${VICTORIA_LOGS_PLUGIN_SHA256_VAR}"' in build_script, build_script
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
image_catalog = (repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8")
sync_script = (repo_root / "terraform/kubernetes/scripts/sync-gitea.sh").read_text(encoding="utf-8")
policies_script = (repo_root / "terraform/kubernetes/scripts/sync-gitea-policies.sh").read_text(encoding="utf-8")
gitops_tf = (repo_root / "terraform/kubernetes/gitops.tf").read_text(encoding="utf-8")
variables_tf = (repo_root / "terraform/kubernetes/variables.tf").read_text(encoding="utf-8")
locals_tf = (repo_root / "terraform/kubernetes/locals.tf").read_text(encoding="utf-8")

for image_name, dockerfile_path in {
    "idp-core": "apps/idp-core/app/Dockerfile",
    "backstage": "apps/backstage/Dockerfile",
    "platform-mcp": "apps/platform-mcp/app/Dockerfile",
}.items():
    assert f'"id": "{image_name}"' in image_catalog, image_name
    assert f'lookup(var.external_platform_image_refs, "{image_name}", "")' in locals_tf, image_name
    assert image_name in variables_tf, image_name

assert "EXTERNAL_PLATFORM_IMAGE_BACKSTAGE" in sync_script
assert "EXTERNAL_PLATFORM_IMAGE_IDP_CORE" in sync_script
assert "EXTERNAL_PLATFORM_IMAGE_PLATFORM_MCP" in sync_script
assert "export_resolved_bool_target_or_stage PREFER_EXTERNAL_WORKLOAD_IMAGES prefer_external_workload_images false" in sync_script
assert "resolve_external_workload_image()" in sync_script
assert "EXTERNAL_PLATFORM_IMAGE_BACKSTAGE" in policies_script
assert "EXTERNAL_PLATFORM_IMAGE_IDP_CORE" in policies_script
assert "EXTERNAL_PLATFORM_IMAGE_PLATFORM_MCP" in policies_script
assert "EXTERNAL_IMAGE_PLATFORM_MCP" not in policies_script
assert "ensure_grafana_dashboard_provider_paths" in policies_script
assert "/^    path:[[:space:]]*/" in policies_script
assert "/var/lib/grafana/dashboards/default" in policies_script
assert "/var/lib/grafana/dashboards/kubernetes" in policies_script
assert "/var/lib/grafana/dashboards/cilium" in policies_script
assert "/var/lib/grafana/dashboards/argocd" in policies_script
assert 'EXTERNAL_PLATFORM_IMAGE_BACKSTAGE             = lookup(var.external_platform_image_refs, "backstage", "")' not in gitops_tf
assert 'EXTERNAL_PLATFORM_IMAGE_IDP_CORE              = lookup(var.external_platform_image_refs, "idp-core", "")' not in gitops_tf
assert 'EXTERNAL_IMAGE_PLATFORM_MCP                   = lookup(var.external_workload_image_refs, "platform-mcp", "")' not in gitops_tf
assert "GITOPS_RENDER_CONTRACT_FILE" in gitops_tf
assert "render_external_image_inputs" in policies_script
assert 'replace_image_ref "${manifest_file}" "${image_name}" "${image_ref}"' in policies_script
assert 'replace_image_ref "${workload_file}" "${image_name}" "${image_ref}"' in policies_script
assert 'HELM_REGISTRY_CONFIG="${tmp_registry_dir}/registry.json"' in policies_script
assert 'DOCKER_CONFIG="${tmp_registry_dir}"' in policies_script
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
image_catalog = (repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8")
catalog_lib = (repo_root / "kubernetes/workflow/image-catalog-lib.sh").read_text(encoding="utf-8")
image_build_lib = (repo_root / "kubernetes/workflow/image-build-lib.sh").read_text(encoding="utf-8")

assert "source_fingerprint_tag()" in catalog_lib
assert "idp_core_source_tag=" in build_script
assert "backstage_source_tag=" in build_script
assert "platform_mcp_source_tag=" in build_script
assert 'image_build_catalog_build_and_push platform idp-core idp-core "${idp_core_source_tag}"' in build_script
assert 'image_build_catalog_build_and_push platform backstage backstage "${backstage_source_tag}"' in build_script
assert 'image_build_catalog_build_and_push platform platform-mcp platform-mcp "${platform_mcp_source_tag}"' in build_script
assert 'image_build_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${fingerprint_tag}"' in image_build_lib

render_script = (repo_root / "kubernetes/kind/scripts/render-operator-overrides.sh").read_text(encoding="utf-8")
assert "platform_mcp_image_tag=" in render_script
assert "idp_core_image_tag=" in render_script
assert "backstage_image_tag=" in render_script
assert "write_external_platform_images()" in render_script
assert "prefer_external_platform_images = true" in render_script
assert "external_platform_image_refs = {" in render_script
assert "apps/platform-mcp/app/internal" in image_catalog
assert "apps/idp-core/app/go.mod" in image_catalog
assert "apps/idp-core/app/internal" in image_catalog
assert "make -C apps/idp-core/app build-linux" in image_catalog
assert "apps/backstage/packages" in image_catalog
assert "apps/apim-simulator/catalog-info.yaml" in image_catalog
assert "image_catalog_source_tag platform platform-mcp" in render_script
assert "image_catalog_source_tag platform backstage" in render_script
assert "image_catalog_source_tag platform idp-core" in render_script
assert "image_catalog_hcl_refs platform" in render_script
assert "image_catalog_hcl_refs workload" in render_script
assert "write_external_workload_images()" in render_script
assert "image_catalog_external_ids workload" in render_script
assert "image_catalog_source_tag workload" in render_script
assert "image_catalog_external_ids()" in catalog_lib

print("validated local platform IDP source fingerprint cache keys")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local platform IDP source fingerprint cache keys"* ]]
}

@test "local Go workload image cache keys include embedded frontend sources" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import json
import os

repo_root = Path(os.environ["REPO_ROOT"])
catalog = json.loads((repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8"))
workloads = {image["id"]: image for image in catalog["workload_images"]}

expected_sources = {
    "sentiment-api": ["apps/sentiment/app/go.sum", "apps/sentiment/app/internal", "apps/sentiment/app/cmd", "apps/shared/idpauth", "apps/shared/web"],
    "sentiment-auth-ui": ["apps/sentiment/app/go.sum", "apps/sentiment/app/internal", "apps/sentiment/app/cmd", "apps/shared/idpauth", "apps/shared/web"],
    "subnetcalc-api": ["apps/subnetcalc/app/go.sum", "apps/subnetcalc/app/internal", "apps/subnetcalc/app/cmd", "apps/shared/idpauth", "apps/shared/web"],
    "subnetcalc-frontend": ["apps/subnetcalc/app/go.sum", "apps/subnetcalc/app/internal", "apps/subnetcalc/app/internal/app/web", "apps/shared/idpauth", "apps/shared/web"],
}

for image_id, expected in expected_sources.items():
    sources = workloads[image_id].get("fingerprint_sources", [])
    for source in expected:
        assert source in sources, (image_id, source, sources)

print("validated local Go workload source fingerprint cache keys")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local Go workload source fingerprint cache keys"* ]]
}

@test "image catalog owns local platform build specs" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import json
import os

repo_root = Path(os.environ["REPO_ROOT"])
catalog = json.loads((repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8"))
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")
image_build_lib = (repo_root / "kubernetes/workflow/image-build-lib.sh").read_text(encoding="utf-8")

expected = {
    "idp-core": {
        "context": ".",
        "dockerfile": "apps/idp-core/app/Dockerfile",
        "tag": "default",
        "prebuild": "make -C apps/idp-core/app build-linux",
    },
    "platform-mcp": {
        "context": "apps/platform-mcp/app",
        "dockerfile": "Dockerfile",
        "tag": "default",
        "prebuild": "make -C apps/platform-mcp/app build-linux",
    },
    "backstage": {
        "context": "generated-backstage",
        "dockerfile": "Dockerfile",
        "tag": "default",
    },
    "keycloak": {
        "context": "apps/keycloak",
        "dockerfile": "Dockerfile",
        "tag": "default",
    },
}

images = {
    image["id"]: image
    for category in ("platform_images", "workload_images")
    for image in catalog[category]
}

for image_id, build in expected.items():
    catalog_build = images[image_id].get("build")
    assert catalog_build == build, f"{image_id} catalog build spec drifted: {catalog_build!r}"

assert "image_build_catalog_build_and_push" in build_script
assert "image_catalog_build_field" in image_build_lib
assert "image_catalog_default_tag" in image_build_lib
assert '"${REPO_ROOT}/apps/idp-core/app/Dockerfile"' not in build_script
assert '"${REPO_ROOT}/apps/platform-mcp/Dockerfile"' not in build_script
assert '"${REPO_ROOT}/apps/keycloak/Dockerfile"' not in build_script

print("validated image catalog local platform build specs")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated image catalog local platform build specs"* ]]
}

@test "image catalog owns local workload build specs for variant builders" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import json
import os

repo_root = Path(os.environ["REPO_ROOT"])
catalog = json.loads((repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8"))

expected = {
    "sentiment-api": {
        "context": "apps/sentiment/app",
        "dockerfile": "Dockerfile",
        "tag": "default",
        "prebuild": "make -C apps/sentiment/app build-linux",
    },
    "sentiment-auth-ui": {
        "context": "apps/sentiment/app",
        "dockerfile": "Dockerfile",
        "tag": "default",
        "prebuild": "make -C apps/sentiment/app build-linux",
    },
    "subnetcalc-api": {
        "context": "apps/subnetcalc/app",
        "dockerfile": "Dockerfile",
        "tag": "default",
        "prebuild": "make -C apps/subnetcalc/app build-linux",
    },
    "subnetcalc-apim-simulator": {
        "context": "apps/apim-simulator",
        "dockerfile": "Dockerfile",
        "tag": "default",
    },
    "subnetcalc-frontend": {
        "context": "apps/subnetcalc/app",
        "dockerfile": "Dockerfile",
        "tag": "default",
        "prebuild": "make -C apps/subnetcalc/app build-linux",
    },
}

workloads = {image["id"]: image for image in catalog["workload_images"]}
for image_id, build in expected.items():
    catalog_build = workloads[image_id].get("build")
    assert catalog_build == build, f"{image_id} catalog build spec drifted: {catalog_build!r}"

scripts = [
    repo_root / "kubernetes/kind/scripts/build-local-workload-images.sh",
    repo_root / "kubernetes/scripts/build-local-workload-images.sh",
]
variant_wrappers = [
    repo_root / "kubernetes/lima/scripts/build-local-workload-images.sh",
    repo_root / "kubernetes/slicer/scripts/build-local-workload-images.sh",
]
image_build_lib = (repo_root / "kubernetes/workflow/image-build-lib.sh").read_text(encoding="utf-8")
hard_coded_paths = [
    "apps/sentiment/app/Dockerfile",
    "apps/apim-simulator/Dockerfile",
]

for script in scripts:
    content = script.read_text(encoding="utf-8")
    assert "image_build_catalog_build_loop workload workload" in content, script
    assert "kubernetes/workflow/image-build-lib.sh" in content, script
    for hard_coded_path in hard_coded_paths:
        assert hard_coded_path not in content, (script, hard_coded_path)

for script in variant_wrappers:
    content = script.read_text(encoding="utf-8")
    assert "kubernetes/scripts/build-local-workload-images.sh" in content, script
    for hard_coded_path in hard_coded_paths:
        assert hard_coded_path not in content, (script, hard_coded_path)

assert "image_catalog_build_specs" in image_build_lib
assert "image_catalog_build_arg_specs" in image_build_lib
assert "image_catalog_default_tag" in image_build_lib
assert "image_build_catalog_build_and_push" in image_build_lib
assert "image_build_run_prebuild" in image_build_lib
assert '"${TAG:-latest}"' not in image_build_lib[image_build_lib.index("image_build_catalog_build_loop()"):]

print("validated catalog-owned workload build specs for variant builders")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated catalog-owned workload build specs for variant builders"* ]]
}

@test "image catalog owns Grafana VictoriaLogs plugin image build inputs" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import json
import os

repo_root = Path(os.environ["REPO_ROOT"])
catalog = json.loads((repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8"))
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")

grafana = next(image for image in catalog["platform_images"] if image["id"] == "grafana-victorialogs")
build = grafana["build"]

assert build["grafana_base_image"] == {
    "source": "docker.io/grafana/grafana",
    "tag": "12.3.1",
    "cache_repo": "platform-cache/grafana-grafana",
}
assert build["plugin_fetch_image"] == {
    "source": "docker.io/library/alpine",
    "tag": "3.22",
    "cache_repo": "platform-cache/library-alpine",
}
assert build["plugin_archive"]["terraform_version_variable"] == "grafana_victoria_logs_plugin_version"
assert build["plugin_archive"]["terraform_sha256_variable"] == "grafana_victoria_logs_plugin_sha256"
assert build["plugin_archive"]["url_template"].count("{version}") == 2
assert build["plugin_archive"]["cache_dir"] == ".run/kind/plugin-cache"
assert build["version_tag_strategy"] == "grafana-tag-plus-plugin-version"

for removed_default in (
    'GRAFANA_IMAGE_TAG="${GRAFANA_IMAGE_TAG:-12.3.1}"',
    'PLUGIN_FETCH_IMAGE_SOURCE="${PLUGIN_FETCH_IMAGE_SOURCE:-docker.io/library/alpine:3.22}"',
    'GRAFANA_BASE_IMAGE_SOURCE="${GRAFANA_BASE_IMAGE_SOURCE:-docker.io/grafana/grafana:${GRAFANA_IMAGE_TAG}}"',
):
    assert removed_default not in build_script, removed_default

assert "image_catalog_build_json platform grafana-victorialogs" in build_script
assert "catalog_grafana_build_value" in build_script

print("validated catalog-owned Grafana VictoriaLogs plugin build inputs")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated catalog-owned Grafana VictoriaLogs plugin build inputs"* ]]
}

@test "image catalog entries declare version-check policy" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import json
import os

repo_root = Path(os.environ["REPO_ROOT"])
catalog = json.loads((repo_root / "kubernetes/workflow/image-catalog.json").read_text(encoding="utf-8"))

allowed_modes = {
    "local",
    "external",
    "pinned-digest",
    "checked-elsewhere",
    "non-comparable",
}

validated = 0
for category in ("platform_images", "workload_images"):
    for image in catalog[category]:
        policy = image.get("version_check")
        assert isinstance(policy, dict), f"{category}.{image['id']} missing version_check"
        mode = policy.get("mode")
        reason = str(policy.get("reason", "")).strip()
        assert mode in allowed_modes, f"{category}.{image['id']} has unsupported version_check mode {mode!r}"
        assert reason, f"{category}.{image['id']} version_check must explain the policy"
        assert image.get("default_tag") != "latest", (
            f"{category}.{image['id']} must pin its local registry default tag"
        )
        validated += 1

print(f"validated {validated} image catalog version-check policies")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated 11 image catalog version-check policies"* ]]
}

@test "Lima and Slicer external image refs match the image catalog" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os
import subprocess
import sys

repo_root = Path(os.environ["REPO_ROOT"])
validator = repo_root / "kubernetes/workflow/validate-image-catalog-target-refs.py"
catalog = repo_root / "kubernetes/workflow/image-catalog.json"

expectations = {
    "lima": repo_root / "kubernetes/lima/targets/lima.tfvars",
    "slicer": repo_root / "kubernetes/slicer/targets/slicer.tfvars",
}

for target, tfvars in expectations.items():
    subprocess.run(
        [
            sys.executable,
            str(validator),
            "--catalog",
            str(catalog),
            "--target",
            target,
            "--tfvars",
            str(tfvars),
        ],
        check=True,
    )

print("validated Lima and Slicer external image refs against image catalog")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated Lima and Slicer external image refs against image catalog"* ]]
}

@test "image catalog renders target tfvars external image projection" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os
import subprocess
import sys

repo_root = Path(os.environ["REPO_ROOT"])
validator = repo_root / "kubernetes/workflow/validate-image-catalog-target-refs.py"
catalog = repo_root / "kubernetes/workflow/image-catalog.json"
script_text = validator.read_text(encoding="utf-8")

assert "--print-expected" in script_text

for target, host in {
    "lima": "host.lima.internal:5002",
    "slicer": "192.168.64.1:5002",
}.items():
    rendered = subprocess.check_output(
        [
            sys.executable,
            str(validator),
            "--catalog",
            str(catalog),
            "--target",
            target,
            "--print-expected",
        ],
        text=True,
    )
    assert "external_platform_image_refs = {" in rendered, target
    assert "external_workload_image_refs = {" in rendered, target
    assert f'"platform-mcp" = "{host}/platform/platform-mcp:0.1.0"' in rendered, rendered
    assert '"sentiment-api"' in rendered and f'{host}/platform/sentiment-api:0.1.0' in rendered, rendered

print("validated generated target tfvars projection from image catalog")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated generated target tfvars projection from image catalog"* ]]
}

@test "local platform IDP cache hits are not invalidated by unrelated git commits" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])
build_script = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")
image_build_lib = (repo_root / "kubernetes/workflow/image-build-lib.sh").read_text(encoding="utf-8")

skip_start = image_build_lib.index("image_build_cache_hit()")
skip_end = image_build_lib.index("return 0", skip_start)
skip_condition = image_build_lib[skip_start:skip_end]

assert "${fingerprint_tag}" in skip_condition
assert 'IMAGE_BUILD_REQUIRE_COMMIT_TAG:-0}" = "1"' in skip_condition
assert "IMAGE_BUILD_REQUIRE_COMMIT_TAG=1" not in build_script
assert 'image_build_push_optional_tag "${build_ref}" "${commit_ref}"' in image_build_lib

print("validated local platform IDP cache hits ignore unrelated git commits")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated local platform IDP cache hits ignore unrelated git commits"* ]]
}

@test "image catalog shared image builder adapter owns variant build mechanics" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])
shared = (repo_root / "kubernetes/workflow/image-build-lib.sh").read_text(encoding="utf-8")

required_functions = [
    "image_build_prepare_args()",
    "image_build_cache_hit()",
    "image_build_build_and_push_cached()",
    "image_build_catalog_build_loop()",
]
for function_name in required_functions:
    assert function_name in shared, function_name

assert 'fingerprint_tag="$(image_catalog_source_tag "${category}" "${image_id}")"' in shared
assert 'image_build_catalog_build_and_push "${category}" "${image_id}" "${image_name}"' in shared
assert 'image_build_tag_exists "${CACHE_PUSH_HOST}" "${repo}" "${fingerprint_tag}"' in shared

scripts = [
    repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh",
    repo_root / "kubernetes/kind/scripts/build-local-workload-images.sh",
    repo_root / "kubernetes/scripts/build-local-workload-images.sh",
]
for script in scripts:
    content = script.read_text(encoding="utf-8")
    assert "kubernetes/workflow/image-build-lib.sh" in content, script
    assert "image_build_catalog_build_loop" in content or "image_build_catalog_build_and_push" in content, script

variant_wrappers = [
    repo_root / "kubernetes/lima/scripts/build-local-workload-images.sh",
    repo_root / "kubernetes/slicer/scripts/build-local-workload-images.sh",
]
for script in variant_wrappers:
    content = script.read_text(encoding="utf-8")
    assert "kubernetes/scripts/build-local-workload-images.sh" in content, script

workload_scripts = scripts[1:] + variant_wrappers
for script in workload_scripts:
    content = script.read_text(encoding="utf-8")
    for duplicated_function in (
        "build_and_push()",
        "catalog_build_context()",
        "catalog_dockerfile_path()",
        "catalog_prepare_build_args()",
        "catalog_build_and_push()",
    ):
        assert duplicated_function not in content, (script, duplicated_function)

print("validated shared image builder adapter ownership")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated shared image builder adapter ownership"* ]]
}

@test "image catalog context adapter owns generated Backstage build context" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])
context_lib = (repo_root / "kubernetes/workflow/image-catalog-context-lib.sh").read_text(encoding="utf-8")
image_build_lib = (repo_root / "kubernetes/workflow/image-build-lib.sh").read_text(encoding="utf-8")
platform_builder = (repo_root / "kubernetes/kind/scripts/build-local-platform-images.sh").read_text(encoding="utf-8")

for fragment in (
    "image_catalog_prepare_build_context_adapter()",
    "image_catalog_prepare_backstage_build_context()",
    "copy_backstage_app_catalog()",
    "generated-backstage",
    "apps/apim-simulator/catalog-info.yaml",
):
    assert fragment in context_lib, fragment

for duplicated_fragment in (
    "copy_backstage_app_catalog()",
    "copy_backstage_apim_simulator_catalog()",
    'cp -R "${REPO_ROOT}/apps/backstage/."',
    'copy_backstage_app_catalog "${context_dir}" "subnetcalc"',
):
    assert duplicated_fragment not in platform_builder, duplicated_fragment

assert "kubernetes/workflow/image-catalog-context-lib.sh" in platform_builder
assert "image_catalog_prepare_build_context_adapter" in image_build_lib

print("validated image catalog Backstage context adapter")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated image catalog Backstage context adapter"* ]]
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

@test "platform MCP Docker image uses the Go single-binary runtime" {
  run uv run --isolated python - <<'PY'
from pathlib import Path
import os

repo_root = Path(os.environ["REPO_ROOT"])
dockerfile = (repo_root / "apps/platform-mcp/app/Dockerfile").read_text(encoding="utf-8")
makefile = (repo_root / "apps/platform-mcp/app/Makefile").read_text(encoding="utf-8")

assert "FROM dhi.io/static:20260413-alpine3.23" in dockerfile
assert "COPY .run/platform-mcp /platform-mcp" in dockerfile
assert "USER 65532:65532" in dockerfile
assert "ENTRYPOINT [\"/platform-mcp\"]" in dockerfile
assert "CGO_ENABLED=0 GOOS=linux" in makefile
assert "go build -trimpath -ldflags=\"-s -w\"" in makefile

print("validated platform MCP Docker image contract")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated platform MCP Docker image contract"* ]]
}
