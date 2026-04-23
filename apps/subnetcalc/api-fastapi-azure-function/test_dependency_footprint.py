"""Regression tests for the Azure Function dependency footprint."""

from __future__ import annotations

from pathlib import Path
import tomllib


APP_DIR = Path(__file__).resolve().parent


def test_runtime_dependencies_avoid_fastapi_standard_bundle() -> None:
    """The function app should depend on only the FastAPI pieces it uses."""
    project = tomllib.loads((APP_DIR / "pyproject.toml").read_text(encoding="utf-8"))
    dependencies = list(project["project"]["dependencies"])

    assert "fastapi[standard]>=0.118.0" not in dependencies
    assert any(dep.startswith("fastapi>=") for dep in dependencies)
