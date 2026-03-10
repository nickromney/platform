"""Tests for main FastAPI application routes."""

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client():
    """Create test client with no authentication."""
    return TestClient(app)


def test_root_endpoint(client):
    """Test root endpoint returns API information."""
    response = client.get("/")
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "Subnet Calculator API"
    assert data["version"] == "1.0.0"
    assert data["docs"] == "/api/v1/docs"
    assert data["openapi"] == "/api/v1/openapi.json"
    assert data["health"] == "/api/v1/health"


def test_health_endpoint(client):
    """Test health endpoint is accessible without auth."""
    response = client.get("/api/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "healthy"


def test_health_ready_endpoint(client):
    """Test health/ready endpoint."""
    response = client.get("/api/v1/health/ready")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ready"


def test_health_live_endpoint(client):
    """Test health/live endpoint."""
    response = client.get("/api/v1/health/live")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "alive"


def test_docs_accessible(client):
    """Test Swagger UI is accessible."""
    response = client.get("/api/v1/docs")
    assert response.status_code == 200
    assert b"Swagger UI" in response.content or b"swagger" in response.content


def test_redoc_accessible(client):
    """Test ReDoc is accessible."""
    response = client.get("/api/v1/redoc")
    assert response.status_code == 200


def test_openapi_schema_accessible(client):
    """Test OpenAPI schema is accessible."""
    response = client.get("/api/v1/openapi.json")
    assert response.status_code == 200
    schema = response.json()
    assert schema["info"]["title"] == "Subnet Calculator API"
    assert schema["info"]["version"] == "1.0.0"
    assert "/api/v1/ipv4/subnet-info" in schema["paths"]
    assert "/api/v1/ipv6/subnet-info" in schema["paths"]
    assert "/api/v1/ipv4/validate" in schema["paths"]
    assert "/api/v1/ipv4/check-private" in schema["paths"]
    assert "/api/v1/ipv4/check-cloudflare" in schema["paths"]
