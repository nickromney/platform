"""
Tests for API authentication functionality.

This test suite covers:
- Configuration loading (AUTH_METHOD, API_KEYS)
- No auth mode (backward compatibility)
- API key authentication mode
- All endpoints protected
- Edge cases and security

Note: Tests currently fail because auth functionality not yet implemented (TDD).
"""

import pytest
from fastapi.testclient import TestClient

from function_app import api

# Create test client
client = TestClient(api)


# Configuration Tests
class TestAuthConfiguration:
    """Test authentication configuration loading."""

    def test_default_auth_method_is_none(self, monkeypatch):
        """Default AUTH_METHOD should be 'none' for backward compatibility."""
        monkeypatch.delenv("AUTH_METHOD", raising=False)
        monkeypatch.delenv("API_KEYS", raising=False)

        # Should work without any auth headers
        response = client.get("/api/v1/health")
        assert response.status_code == 200

    def test_auth_method_from_environment(self, monkeypatch):
        """AUTH_METHOD should be read from environment variable."""
        monkeypatch.setenv("AUTH_METHOD", "api_key")
        monkeypatch.setenv("API_KEYS", "test-key-123")

        # Should require API key now
        response = client.get("/api/v1/health")
        assert response.status_code == 401

    def test_api_keys_from_environment(self, monkeypatch):
        """API_KEYS should be read from environment variable."""
        monkeypatch.setenv("AUTH_METHOD", "api_key")
        monkeypatch.setenv("API_KEYS", "key1,key2,key3")

        # All keys should work
        response = client.get("/api/v1/health", headers={"X-API-Key": "key1"})
        assert response.status_code == 200

        response = client.get("/api/v1/health", headers={"X-API-Key": "key2"})
        assert response.status_code == 200

        response = client.get("/api/v1/health", headers={"X-API-Key": "key3"})
        assert response.status_code == 200

    def test_invalid_auth_method_raises_error(self, monkeypatch):
        """Invalid AUTH_METHOD should raise configuration error."""
        monkeypatch.setenv("AUTH_METHOD", "invalid_method")

        # Test config function directly
        from config import get_auth_method

        with pytest.raises(ValueError, match="Invalid AUTH_METHOD"):
            get_auth_method()

    def test_api_key_mode_without_keys_raises_error(self, monkeypatch):
        """AUTH_METHOD=api_key without API_KEYS should raise error."""
        monkeypatch.setenv("AUTH_METHOD", "api_key")
        monkeypatch.delenv("API_KEYS", raising=False)

        # Test config function directly
        from config import get_api_keys

        with pytest.raises(ValueError, match="API_KEYS environment variable required"):
            get_api_keys()

    def test_empty_api_keys_raises_error(self, monkeypatch):
        """Empty API_KEYS string should raise error."""
        monkeypatch.setenv("AUTH_METHOD", "api_key")
        monkeypatch.setenv("API_KEYS", "")

        # Test config function directly
        from config import get_api_keys

        with pytest.raises(ValueError, match="API_KEYS environment variable required"):
            get_api_keys()


# No Auth Mode Tests (Backward Compatibility)
class TestNoAuthMode:
    """Test that AUTH_METHOD=none maintains backward compatibility."""

    @pytest.fixture(autouse=True)
    def setup_no_auth(self, monkeypatch):
        """Set up environment for no auth mode."""
        monkeypatch.setenv("AUTH_METHOD", "none")
        monkeypatch.delenv("API_KEYS", raising=False)

    def test_no_auth_allows_all_requests(self):
        """All requests should succeed without auth headers."""
        response = client.get("/api/v1/health")
        assert response.status_code == 200

    def test_no_auth_ignores_api_key_header(self):
        """X-API-Key header should be ignored in no auth mode."""
        response = client.get("/api/v1/health", headers={"X-API-Key": "any-key"})
        assert response.status_code == 200

    def test_no_auth_all_endpoints_accessible(self):
        """All endpoints should be accessible without auth."""
        # Health check
        response = client.get("/api/v1/health")
        assert response.status_code == 200

        # Validation endpoint
        response = client.post("/api/v1/ipv4/validate", json={"address": "192.168.1.0/24"})
        assert response.status_code == 200


# API Key Mode Tests
class TestAPIKeyMode:
    """Test API key authentication."""

    @pytest.fixture(autouse=True)
    def setup_api_key_auth(self, monkeypatch):
        """Set up environment for API key auth."""
        monkeypatch.setenv("AUTH_METHOD", "api_key")
        monkeypatch.setenv("API_KEYS", "valid-key-123,another-valid-key")

    def test_missing_api_key_returns_401(self):
        """Request without X-API-Key header should return 401."""
        response = client.get("/api/v1/health")
        assert response.status_code == 401
        assert response.json()["detail"] == "Missing X-API-Key header"

    def test_invalid_api_key_returns_401(self):
        """Request with invalid API key should return 401."""
        response = client.get("/api/v1/health", headers={"X-API-Key": "invalid-key"})
        assert response.status_code == 401
        assert response.json()["detail"] == "Invalid API key"

    def test_valid_api_key_returns_200(self):
        """Request with valid API key should succeed."""
        response = client.get("/api/v1/health", headers={"X-API-Key": "valid-key-123"})
        assert response.status_code == 200

    def test_multiple_valid_keys_all_work(self):
        """All configured API keys should work."""
        response = client.get("/api/v1/health", headers={"X-API-Key": "valid-key-123"})
        assert response.status_code == 200

        response = client.get("/api/v1/health", headers={"X-API-Key": "another-valid-key"})
        assert response.status_code == 200


# All Endpoints Protected
class TestAllEndpointsProtected:
    """Test that all endpoints require authentication when enabled."""

    @pytest.fixture(autouse=True)
    def setup_api_key_auth(self, monkeypatch):
        """Set up environment for API key auth."""
        monkeypatch.setenv("AUTH_METHOD", "api_key")
        monkeypatch.setenv("API_KEYS", "test-key-123")

    @pytest.mark.parametrize(
        "endpoint,method,body",
        [
            ("/api/v1/health", "GET", None),
            ("/api/v1/ipv4/validate", "POST", {"address": "192.168.1.1"}),
            ("/api/v1/ipv4/check-private", "POST", {"address": "192.168.1.1"}),
            ("/api/v1/ipv4/check-cloudflare", "POST", {"address": "1.1.1.1"}),
            ("/api/v1/ipv4/subnet-info", "POST", {"network": "192.168.1.0/24"}),
        ],
    )
    def test_endpoint_requires_auth(self, endpoint, method, body):
        """All endpoints should require authentication."""
        if method == "GET":
            response = client.get(endpoint)
        else:
            response = client.post(endpoint, json=body)

        assert response.status_code == 401

    @pytest.mark.parametrize(
        "endpoint,method,body",
        [
            ("/api/v1/health", "GET", None),
            ("/api/v1/ipv4/validate", "POST", {"address": "192.168.1.1"}),
            ("/api/v1/ipv4/check-private", "POST", {"address": "192.168.1.1"}),
            ("/api/v1/ipv4/check-cloudflare", "POST", {"address": "1.1.1.1"}),
            ("/api/v1/ipv4/subnet-info", "POST", {"network": "192.168.1.0/24"}),
        ],
    )
    def test_endpoint_works_with_valid_key(self, endpoint, method, body):
        """All endpoints should work with valid API key."""
        headers = {"X-API-Key": "test-key-123"}

        if method == "GET":
            response = client.get(endpoint, headers=headers)
        else:
            response = client.post(endpoint, json=body, headers=headers)

        assert response.status_code == 200


# Edge Cases and Security
class TestEdgeCases:
    """Test edge cases and security scenarios."""

    @pytest.fixture(autouse=True)
    def setup_api_key_auth(self, monkeypatch):
        """Set up environment for API key auth."""
        monkeypatch.setenv("AUTH_METHOD", "api_key")
        monkeypatch.setenv("API_KEYS", "valid-key-123")

    def test_empty_api_key_header_returns_401(self):
        """Empty X-API-Key header should return 401."""
        response = client.get("/api/v1/health", headers={"X-API-Key": ""})
        assert response.status_code == 401

    def test_whitespace_api_key_returns_401(self):
        """Whitespace-only API key should return 401."""
        response = client.get("/api/v1/health", headers={"X-API-Key": "   "})
        assert response.status_code == 401

    def test_api_key_case_sensitive(self):
        """API keys should be case-sensitive."""
        # Valid key
        response = client.get("/api/v1/health", headers={"X-API-Key": "valid-key-123"})
        assert response.status_code == 200

        # Same key but different case should fail
        response = client.get("/api/v1/health", headers={"X-API-Key": "VALID-KEY-123"})
        assert response.status_code == 401

    def test_api_key_with_extra_whitespace_stripped(self):
        """API keys should have whitespace stripped during validation."""
        # Key with leading/trailing whitespace should work
        response = client.get("/api/v1/health", headers={"X-API-Key": "  valid-key-123  "})
        assert response.status_code == 200
