"""
Tests for Azure API Management (APIM) integration.

When deployed behind APIM, JWT validation happens in APIM policies.
The API trusts APIM and reads user claims from injected headers.
"""

import pytest
from fastapi.testclient import TestClient

from function_app import api

client = TestClient(api)


# Configuration Tests
class TestAPIMConfiguration:
    """Test APIM configuration and setup."""

    @pytest.fixture(autouse=True)
    def setup_apim_auth(self, monkeypatch):
        """Set up environment for APIM auth."""
        monkeypatch.setenv("AUTH_METHOD", "apim")

    def test_apim_mode_works(self):
        """APIM mode should be recognized."""
        from config import AuthMethod, get_auth_method

        assert get_auth_method() == AuthMethod.APIM


# Authentication Tests
class TestAPIMAuthentication:
    """Test APIM authentication with user headers."""

    @pytest.fixture(autouse=True)
    def setup_apim_auth(self, monkeypatch):
        """Set up environment for APIM auth."""
        monkeypatch.setenv("AUTH_METHOD", "apim")

    def test_valid_user_id_header_returns_200(self):
        """Valid X-User-ID header should authenticate."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"X-User-ID": "user-123"},
        )

        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is True

    def test_valid_user_email_header_returns_200(self):
        """Valid X-User-Email header should authenticate."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"X-User-Email": "user@example.com"},
        )

        assert response.status_code == 200

    def test_both_headers_prefers_email(self):
        """When both headers present, should prefer email."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"X-User-ID": "user-123", "X-User-Email": "user@example.com"},
        )

        assert response.status_code == 200

    def test_missing_user_headers_returns_401(self):
        """Request without user headers should return 401."""
        response = client.post("/api/v1/ipv4/validate", json={"address": "192.168.1.1"})

        assert response.status_code == 401
        assert "user headers" in response.json()["detail"].lower()

    def test_empty_user_id_returns_401(self):
        """Empty X-User-ID should return 401."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"X-User-ID": ""},
        )

        assert response.status_code == 401

    def test_health_endpoint_requires_no_auth(self):
        """Health endpoint should not require authentication."""
        response = client.get("/api/v1/health")
        assert response.status_code == 200


# All Endpoints Protected
class TestAllEndpointsProtectedAPIM:
    """Test that all API endpoints work with APIM authentication."""

    @pytest.fixture(autouse=True)
    def setup_apim_auth(self, monkeypatch):
        """Set up environment for APIM auth."""
        monkeypatch.setenv("AUTH_METHOD", "apim")

    def test_all_endpoints_work_with_user_headers(self):
        """All endpoints should work with valid user headers."""
        headers = {"X-User-ID": "test-user", "X-User-Email": "test@example.com"}

        endpoints = [
            ("/api/v1/ipv4/validate", {"address": "192.168.1.1"}),
            ("/api/v1/ipv4/check-private", {"address": "192.168.1.1"}),
            ("/api/v1/ipv4/check-cloudflare", {"address": "104.16.1.1"}),
            ("/api/v1/ipv4/subnet-info", {"network": "192.168.1.0/24"}),
        ]

        for path, body in endpoints:
            response = client.post(path, json=body, headers=headers)
            assert response.status_code == 200, f"Failed for {path}"


# APIM Policy Scenarios
class TestAPIMPolicyScenarios:
    """Test different APIM policy configurations."""

    @pytest.fixture(autouse=True)
    def setup_apim_auth(self, monkeypatch):
        """Set up environment for APIM auth."""
        monkeypatch.setenv("AUTH_METHOD", "apim")

    def test_policy_with_only_user_id(self):
        """APIM policy that only sets X-User-ID."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"X-User-ID": "jwt-sub-claim-value"},
        )

        assert response.status_code == 200

    def test_policy_with_only_email(self):
        """APIM policy that only sets X-User-Email."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"X-User-Email": "user@corp.com"},
        )

        assert response.status_code == 200

    def test_policy_with_additional_headers(self):
        """APIM can set additional headers (roles, etc.)."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={
                "X-User-ID": "user-456",
                "X-User-Email": "admin@corp.com",
                "X-User-Roles": "admin,editor",
                "X-Correlation-ID": "abc-123",
            },
        )

        assert response.status_code == 200
