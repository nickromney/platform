"""Regression tests for the APIM simulator dependency footprint."""

from __future__ import annotations

from pathlib import Path
import tomllib


APP_DIR = Path(__file__).resolve().parent.parent


def test_runtime_dependencies_use_explicit_uvicorn_instead_of_fastapi_bundle() -> None:
    """The simulator should avoid FastAPI's large standard extra bundle."""
    project = tomllib.loads((APP_DIR / "pyproject.toml").read_text(encoding="utf-8"))
    dependencies = list(project["project"]["dependencies"])

    assert "fastapi[standard]>=0.115.0" not in dependencies
    assert any(dep.startswith("fastapi>=") for dep in dependencies)
    assert any(dep.startswith("uvicorn>=") for dep in dependencies)
