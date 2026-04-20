"""Shared pytest fixtures for frontend testing."""

import socket

import pytest


def is_service_available(host: str, port: int) -> bool:
    """Check if a service is available on the given host and port."""
    try:
        with socket.create_connection((host, port), timeout=1):
            return True
    except (OSError, socket.timeout):
        return False


@pytest.fixture(scope="session")
def base_url():
    """Base URL for the frontend application."""
    return "http://localhost:8001"


@pytest.fixture(scope="session", autouse=True)
def check_service_available(base_url: str):
    """Skip all tests if the frontend service is not available."""
    # Extract host and port from base_url
    host = "localhost"
    port = 8001

    if not is_service_available(host, port):
        pytest.skip(
            f"Frontend service not available on {base_url}. "
            "Start services with 'podman-compose up' to run these tests.",
            allow_module_level=True,
        )
