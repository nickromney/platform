"""Pytest configuration and shared fixtures."""

import os

import pytest


@pytest.fixture(autouse=True)
def reset_environment():
    """Reset environment variables before each test."""
    # Store original env vars
    original_env = os.environ.copy()

    # Set default test environment
    os.environ["AUTH_METHOD"] = "none"

    yield

    # Restore original env vars after test
    os.environ.clear()
    os.environ.update(original_env)
