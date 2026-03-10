"""
Tests for Azure Static Web Apps (SWA) EasyAuth integration.

Azure SWA injects the x-ms-client-principal header after authentication.
This header contains base64-encoded JSON with user claims.
"""

import base64
import json

import pytest
from fastapi.testclient import TestClient

from function_app import api

client = TestClient(api)


# Helper function to create SWA principal header
def create_swa_principal(
    user_details: str | None = None,
    user_id: str | None = None,
    identity_provider: str = "aad",
    extra_claims: dict[str, object] | None = None,
    claim_list: list[dict[str, object]] | None = None,
) -> str:
    """
    Create a fake Azure SWA x-ms-client-principal header.

    Args:
        user_details: User email or name
        user_id: Unique user ID
        identity_provider: Auth provider (aad, github, google, etc.)

    Returns:
        str: Base64-encoded JSON principal
    """
    claims: dict[str, object] = {
        "identityProvider": identity_provider,
        "userRoles": ["authenticated"],
    }
    if user_id is not None:
        claims["userId"] = user_id
    if user_details is not None:
        claims["userDetails"] = user_details
    if extra_claims:
        claims.update(extra_claims)
    if claim_list is not None:
        claims["claims"] = claim_list
    principal_json = json.dumps(claims)
    return base64.b64encode(principal_json.encode()).decode()


# Configuration Tests
class TestAzureSWAConfiguration:
    """Test Azure SWA configuration and setup."""

    @pytest.fixture(autouse=True)
    def setup_azure_swa_auth(self, monkeypatch):
        """Set up environment for Azure SWA auth."""
        monkeypatch.setenv("AUTH_METHOD", "azure_swa")

    def test_azure_swa_mode_works(self):
        """Azure SWA mode should be recognized."""
        from config import AuthMethod, get_auth_method

        assert get_auth_method() == AuthMethod.AZURE_SWA


# Authentication Tests
class TestAzureSWAAuthentication:
    """Test Azure SWA authentication with x-ms-client-principal header."""

    @pytest.fixture(autouse=True)
    def setup_azure_swa_auth(self, monkeypatch):
        """Set up environment for Azure SWA auth."""
        monkeypatch.setenv("AUTH_METHOD", "azure_swa")

    def test_valid_principal_with_email_returns_200(self):
        """Valid SWA principal with userDetails should authenticate."""
        principal = create_swa_principal(
            user_details="alice@example.com",
            user_id="aad-user-123",
            identity_provider="aad",
        )

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": principal},
        )

        assert response.status_code == 200
        data = response.json()
        assert data["valid"] is True

    def test_valid_principal_without_email_returns_200(self):
        """Valid SWA principal without userDetails should use userId."""
        principal = create_swa_principal(
            user_details=None,  # No email
            user_id="github-user-456",
            identity_provider="github",
        )

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": principal},
        )

        assert response.status_code == 200

    def test_missing_principal_returns_401(self):
        """Request without x-ms-client-principal should return 401."""
        response = client.post("/api/v1/ipv4/validate", json={"address": "192.168.1.1"})

        assert response.status_code == 401
        assert "principal" in response.json()["detail"].lower()

    def test_invalid_base64_returns_401(self):
        """Invalid base64 in principal should return 401."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": "not-valid-base64!!!"},
        )

        assert response.status_code == 401
        assert "Invalid Easy Auth principal" in response.json()["detail"]

    def test_invalid_json_returns_401(self):
        """Invalid JSON in principal should return 401."""
        invalid_json = base64.b64encode(b"not valid json").decode()

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": invalid_json},
        )

        assert response.status_code == 401
        assert "Invalid Easy Auth principal" in response.json()["detail"]

    def test_principal_missing_user_identity_returns_401(self):
        """Principal without userId or userDetails should return 401."""
        claims = {
            "identityProvider": "aad",
            "userRoles": ["authenticated"],
            # Missing userId and userDetails
        }
        principal = base64.b64encode(json.dumps(claims).encode()).decode()

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": principal},
        )

        assert response.status_code == 401
        assert "missing user identity" in response.json()["detail"].lower()

    def test_principal_with_nested_claims_returns_200(self):
        """Principal that only includes nested claim list should still authenticate."""
        nested_claims = [
            {"typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress", "val": "proxy@example.com"},
        ]
        principal = create_swa_principal(
            user_details=None,
            user_id=None,
            claim_list=nested_claims,
        )

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": principal},
        )

        assert response.status_code == 200

    def test_missing_identity_allows_managed_identity_header(self):
        """Proxy mode should accept requests that include managed identity headers."""
        principal = create_swa_principal(user_details=None, user_id=None)

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={
                "x-ms-client-principal": principal,
                "x-ms-managed-identity-principal-id": "mi-12345",
            },
        )

        assert response.status_code == 200

    def test_health_endpoint_requires_no_auth(self):
        """Health endpoint should not require authentication."""
        response = client.get("/api/v1/health")
        assert response.status_code == 200


# All Endpoints Protected
class TestAllEndpointsProtectedSWA:
    """Test that all API endpoints require Azure SWA authentication."""

    @pytest.fixture(autouse=True)
    def setup_azure_swa_auth(self, monkeypatch):
        """Set up environment for Azure SWA auth."""
        monkeypatch.setenv("AUTH_METHOD", "azure_swa")

    def test_all_endpoints_work_with_valid_principal(self):
        """All endpoints should work with valid SWA principal."""
        principal = create_swa_principal(user_details="test@example.com", user_id="test-user-789")

        endpoints = [
            ("/api/v1/ipv4/validate", {"address": "192.168.1.1"}),
            ("/api/v1/ipv4/check-private", {"address": "192.168.1.1"}),
            ("/api/v1/ipv4/check-cloudflare", {"address": "104.16.1.1"}),
            ("/api/v1/ipv4/subnet-info", {"network": "192.168.1.0/24"}),
        ]

        for path, body in endpoints:
            response = client.post(path, json=body, headers={"x-ms-client-principal": principal})
            assert response.status_code == 200, f"Failed for {path}"


# Different Identity Providers
class TestDifferentIdentityProviders:
    """Test Azure SWA with different identity providers."""

    @pytest.fixture(autouse=True)
    def setup_azure_swa_auth(self, monkeypatch):
        """Set up environment for Azure SWA auth."""
        monkeypatch.setenv("AUTH_METHOD", "azure_swa")

    def test_azure_ad_provider(self):
        """Test with Azure AD identity provider."""
        principal = create_swa_principal(user_details="user@company.com", identity_provider="aad")

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": principal},
        )

        assert response.status_code == 200

    def test_github_provider(self):
        """Test with GitHub identity provider."""
        principal = create_swa_principal(user_details="githubuser", identity_provider="github")

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": principal},
        )

        assert response.status_code == 200

    def test_google_provider(self):
        """Test with Google identity provider."""
        principal = create_swa_principal(user_details="user@gmail.com", identity_provider="google")

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"x-ms-client-principal": principal},
        )

        assert response.status_code == 200
