from __future__ import annotations

import re
import subprocess
import sys
import zipfile
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parents[1]

PINNED_RELEASE_ACTION_REFS = {
    "actions/checkout": "de0fac2e4500dabe0009e67214ff5f5447ce83dd",
    "actions/setup-python": "a309ff8b426b58ec0e2a45f0f869d46889d02405",
    "actions/upload-artifact": "ea165f8d65b6e75b540449e92b4886f43607fa02",
    "actions/attest-build-provenance": "a2bbfa25375fe432b6a289bc6b6cd05ecd0c4c32",
    "docker/setup-buildx-action": "4d04d5d9486b7bd6fa91e7baf45bbb4f8b9deedd",
    "docker/login-action": "4907a6ddec9925e35a0a9e82d7399ccc52663121",
    "docker/metadata-action": "030e881283bb7a6894de51c315a6bfe6a94e05cf",
    "docker/build-push-action": "bcafcacb16a39f128d818304e6c9c0c18556b85f",
}


def _load_yaml(relative_path: str) -> dict:
    return yaml.safe_load((REPO_ROOT / relative_path).read_text())


def _workflow_step_by_name(job: dict, step_name: str) -> dict:
    return next(step for step in job["steps"] if step["name"] == step_name)


def test_runtime_artifact_contains_only_gitea_build_inputs(tmp_path: Path) -> None:
    result = subprocess.run(
        [
            sys.executable,
            "scripts/build_runtime_artifact.py",
            "--output-dir",
            str(tmp_path),
            "--name",
            "apim-simulator-runtime-test.zip",
        ],
        cwd=REPO_ROOT,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )

    archive_path = tmp_path / "apim-simulator-runtime-test.zip"
    checksum_path = tmp_path / "apim-simulator-runtime-test.zip.sha256"
    assert archive_path.exists()
    assert checksum_path.exists()
    assert f"Wrote {archive_path}" in result.stdout

    with zipfile.ZipFile(archive_path) as archive:
        names = set(archive.namelist())
        dockerfile = archive.read("Dockerfile").decode("utf-8")

    assert ".dockerignore" in names
    assert "catalog-info.yaml" in names
    assert "Dockerfile" in names
    assert "LICENSE.md" in names
    assert "pyproject.toml" in names
    assert "uv.lock" in names
    assert "app/main.py" in names
    assert "contracts/contract_matrix.yml" in names
    assert "ARG PYTHON_BUILD_IMAGE=dhi.io/python:3.13-debian13-dev" in dockerfile
    assert "ARG PYTHON_RUNTIME_IMAGE=dhi.io/python:3.13-debian13" in dockerfile
    assert "COPY --chown=${APP_UID}:${APP_GID} app ./app" in dockerfile
    assert "examples ./examples" not in dockerfile

    excluded_prefixes = (
        ".github/",
        ".githooks/",
        "backstage/",
        "docs/",
        "examples/",
        "observability/",
        "scripts/",
        "tests/",
        "ui/",
    )
    assert not any(name.startswith(excluded_prefixes) for name in names)
    assert checksum_path.read_text(encoding="utf-8").endswith("  apim-simulator-runtime-test.zip\n")


def test_release_workflow_publishes_attested_zip_and_ghcr_image() -> None:
    workflow_text = (REPO_ROOT / ".github/workflows/release.yml").read_text()
    workflow = _load_yaml(".github/workflows/release.yml")
    runtime_job = workflow["jobs"]["runtime-source"]
    image_job = workflow["jobs"]["image"]

    assert '- "v*.*.*"' in workflow_text
    assert "build_image:" in workflow_text
    assert "image_base:" in workflow_text
    assert "push_image:" in workflow_text
    assert "- public" in workflow_text
    assert "- dhi" in workflow_text
    assert image_job["if"] == "github.event_name != 'workflow_dispatch' || inputs.build_image"

    assert runtime_job["permissions"] == {
        "attestations": "write",
        "contents": "write",
        "id-token": "write",
    }
    assert image_job["permissions"] == {
        "attestations": "write",
        "contents": "read",
        "id-token": "write",
        "packages": "write",
    }

    build_archive = _workflow_step_by_name(runtime_job, "Build runtime source archive")
    assert build_archive["run"] == "python scripts/build_runtime_artifact.py --output-dir dist"

    upload_archive = _workflow_step_by_name(runtime_job, "Upload runtime source archive")
    assert "dist/apim-simulator-runtime-*.zip" in upload_archive["with"]["path"]
    assert "dist/apim-simulator-runtime-*.zip.sha256" in upload_archive["with"]["path"]

    attest_archive = _workflow_step_by_name(runtime_job, "Attest runtime source archive")
    assert attest_archive["with"]["subject-path"] == "dist/apim-simulator-runtime-*.zip"

    build_context = _workflow_step_by_name(image_job, "Build runtime image context")
    assert "scripts/build_runtime_artifact.py" in build_context["run"]
    assert "apim-simulator-runtime-context" in build_context["run"]

    build_profile = _workflow_step_by_name(image_job, "Resolve image build profile")
    assert 'image_base="dhi"' in build_profile["run"]
    assert 'push_image="true"' in build_profile["run"]
    assert "github.event.inputs.image_base" in build_profile["run"]
    assert "github.event.inputs.push_image" in build_profile["run"]
    assert "PYTHON_BUILD_IMAGE=python:3.13-slim" in build_profile["run"]
    assert "PYTHON_RUNTIME_IMAGE=python:3.13-slim" in build_profile["run"]

    require_dhi = _workflow_step_by_name(image_job, "Require Docker Hardened Images credentials")
    assert require_dhi["if"] == "steps.build-profile.outputs.image_base == 'dhi'"
    assert "DHI_USERNAME" in require_dhi["env"]
    assert "DHI_TOKEN" in require_dhi["env"]["DHI_PASSWORD"]
    assert "DHI_PASSWORD" in require_dhi["env"]["DHI_PASSWORD"]

    dhi_login = _workflow_step_by_name(image_job, "Log in to Docker Hardened Images")
    assert dhi_login["if"] == "steps.build-profile.outputs.image_base == 'dhi'"
    assert dhi_login["uses"] == f"docker/login-action@{PINNED_RELEASE_ACTION_REFS['docker/login-action']}"
    assert dhi_login["with"]["registry"] == "dhi.io"

    verify_dhi = _workflow_step_by_name(image_job, "Verify Docker Hardened Images access")
    assert verify_dhi["if"] == "steps.build-profile.outputs.image_base == 'dhi'"
    assert "docker buildx imagetools inspect dhi.io/python:3.13-debian13-dev" in verify_dhi["run"]
    assert "docker buildx imagetools inspect dhi.io/python:3.13-debian13" in verify_dhi["run"]

    ghcr_login = _workflow_step_by_name(image_job, "Log in to GHCR")
    assert ghcr_login["if"] == "steps.build-profile.outputs.push_image == 'true'"

    build_image = _workflow_step_by_name(image_job, "Build and push GHCR image")
    assert build_image["with"]["context"] == "${{ runner.temp }}/apim-simulator-runtime-context"
    assert build_image["with"]["push"] == "${{ steps.build-profile.outputs.push_image == 'true' }}"
    assert build_image["with"]["build-args"] == "${{ steps.build-profile.outputs.build_args }}"
    assert build_image["with"]["provenance"] == "mode=max"
    assert build_image["with"]["sbom"] is True

    attest_image = _workflow_step_by_name(image_job, "Attest GHCR image")
    assert attest_image["if"] == "steps.build-profile.outputs.push_image == 'true'"
    assert attest_image["with"]["subject-name"] == "${{ env.IMAGE_NAME }}"
    assert attest_image["with"]["subject-digest"] == "${{ steps.build.outputs.digest }}"
    assert attest_image["with"]["push-to-registry"] is True


def test_release_workflow_uses_pinned_action_shas() -> None:
    workflow = _load_yaml(".github/workflows/release.yml")
    seen_actions: set[str] = set()

    for job in workflow["jobs"].values():
        for step in job.get("steps", []):
            uses = step.get("uses")
            if not uses:
                continue
            action, ref = uses.split("@", 1)
            seen_actions.add(action)
            assert re.fullmatch(r"[0-9a-f]{40}", ref), f"{uses} is not commit-pinned"
            assert ref == PINNED_RELEASE_ACTION_REFS[action]

    assert seen_actions == set(PINNED_RELEASE_ACTION_REFS)
