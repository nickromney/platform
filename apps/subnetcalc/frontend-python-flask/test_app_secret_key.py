"""Regression tests for Flask secret-key handling."""

from __future__ import annotations

import inspect

import app as flask_app


def test_secret_key_assignment_uses_app_property_not_config_literal() -> None:
    """Keep the Flask secret assignment off the hard-coded config key path."""
    source = inspect.getsource(flask_app)

    assert 'app.config["SECRET_KEY"]' not in source


def test_secret_key_comes_from_environment(monkeypatch) -> None:
    """Environment-provided secrets should still be honored."""
    monkeypatch.setenv("FLASK_SECRET_KEY", "test-session-secret-value")

    assert flask_app.get_flask_secret_key() == "test-session-secret-value"


def test_secret_key_falls_back_to_ephemeral_value(monkeypatch) -> None:
    """Local development should still get a usable runtime secret."""
    monkeypatch.delenv("FLASK_SECRET_KEY", raising=False)

    secret = flask_app.get_flask_secret_key()

    assert secret
    assert len(secret) >= 32
