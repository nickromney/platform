"""Regression tests for the Flask frontend dependency footprint."""

from __future__ import annotations

from pathlib import Path
import tomllib


APP_DIR = Path(__file__).resolve().parent


def _dependency_names() -> set[str]:
    project = tomllib.loads((APP_DIR / "pyproject.toml").read_text(encoding="utf-8"))
    names: set[str] = set()
    for dependency in project["project"]["dependencies"]:
        name = dependency.split(";", 1)[0].strip()
        for separator in ("[", ">", "<", "=", "!", "~"):
            name = name.split(separator, 1)[0]
        names.add(name.strip())
    return names


def test_runtime_dependencies_avoid_flask_session_extension() -> None:
    """The app should rely on Flask's built-in session support."""
    assert "flask-session" not in _dependency_names()


def test_app_source_avoids_external_session_backend() -> None:
    """The Flask app should not wire up the filesystem session extension."""
    source = (APP_DIR / "app.py").read_text(encoding="utf-8")

    assert "flask_session" not in source
    assert 'SESSION_TYPE' not in source


def test_auth_callback_does_not_persist_raw_token_blobs() -> None:
    """Cookie-backed sessions should keep only the minimum auth state."""
    source = (APP_DIR / "auth.py").read_text(encoding="utf-8")

    assert 'session["access_token"]' not in source
    assert 'session["id_token"]' not in source
