"""Regression tests for the APIM simulator dependency footprint."""

from __future__ import annotations

import tomllib
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent


def test_runtime_dependencies_use_explicit_uvicorn_instead_of_fastapi_bundle() -> None:
    """The simulator should avoid FastAPI's large standard extra bundle."""
    project = tomllib.loads((APP_DIR / "pyproject.toml").read_text(encoding="utf-8"))
    dependencies = list(project["project"]["dependencies"])

    assert "fastapi[standard]>=0.115.0" not in dependencies
    assert any(dep.startswith("fastapi>=") for dep in dependencies)
    assert any(dep.startswith("uvicorn>=") for dep in dependencies)


def test_operator_console_has_no_npm_build_dependency() -> None:
    """The default operator console should be static HTML/CSS/JS."""
    ui_dir = APP_DIR / "ui"
    dockerfile = (ui_dir / "Dockerfile").read_text(encoding="utf-8")
    index = (ui_dir / "index.html").read_text(encoding="utf-8")

    assert not (ui_dir / "package.json").exists()
    assert not (ui_dir / "package-lock.json").exists()
    assert not (ui_dir / ".npmrc").exists()
    assert not (ui_dir / "node_modules").exists()
    assert "FROM ${UI_BUILD_IMAGE} AS builder" not in dockerfile
    assert "npm" not in dockerfile
    assert "/app/dist" not in dockerfile
    assert 'src="/app.js"' in index


def test_todo_frontend_has_no_npm_build_dependency() -> None:
    """The todo demo frontend should stay static HTML/CSS/JS."""
    frontend_dir = APP_DIR / "examples" / "todo-app" / "frontend-astro"
    dockerfile = (frontend_dir / "Dockerfile").read_text(encoding="utf-8")
    index = (frontend_dir / "index.html").read_text(encoding="utf-8")

    assert not (frontend_dir / "package.json").exists()
    assert not (frontend_dir / "package-lock.json").exists()
    assert not (frontend_dir / ".npmrc").exists()
    assert not (frontend_dir / "node_modules").exists()
    assert "FROM node:" not in dockerfile
    assert "npm" not in dockerfile
    assert "/app/dist" not in dockerfile
    assert 'src="/app.js"' in index
