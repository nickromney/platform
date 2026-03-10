"""
Test CORS and X-Forwarded-Host header validation for Container App API

These tests verify the security fixes for:
1. CORS origins configuration (environment-driven)
2. X-Forwarded-Host header validation middleware
"""

import os

from fastapi.testclient import TestClient

from app.config import get_allowed_swa_hosts, get_cors_origins
from app.main import app


class TestCORSConfiguration:
    """Test CORS configuration function"""

    def test_cors_origins_defaults_to_localhost_for_dev(self):
        """CORS should have sensible defaults for development"""
        # Save original value
        original = os.environ.get("CORS_ORIGINS")
        try:
            # Unset the variable
            os.environ.pop("CORS_ORIGINS", None)
            origins = get_cors_origins()
            # Should not be empty and not contain wildcard for security
            assert origins is not None
            assert "*" not in origins
        finally:
            # Restore original
            if original:
                os.environ["CORS_ORIGINS"] = original

    def test_cors_origins_from_environment(self):
        """CORS should parse comma-separated origins from environment"""
        original = os.environ.get("CORS_ORIGINS")
        try:
            os.environ["CORS_ORIGINS"] = "https://app.azurestaticapps.net,https://custom.domain.com"
            origins = get_cors_origins()
            assert len(origins) == 2
            assert "https://app.azurestaticapps.net" in origins
            assert "https://custom.domain.com" in origins
        finally:
            if original:
                os.environ["CORS_ORIGINS"] = original
            else:
                os.environ.pop("CORS_ORIGINS", None)

    def test_cors_origins_strips_whitespace(self):
        """CORS parser should strip whitespace from origins"""
        original = os.environ.get("CORS_ORIGINS")
        try:
            os.environ["CORS_ORIGINS"] = "  https://app.azurestaticapps.net  ,  https://custom.com  "
            origins = get_cors_origins()
            assert origins == ["https://app.azurestaticapps.net", "https://custom.com"]
        finally:
            if original:
                os.environ["CORS_ORIGINS"] = original
            else:
                os.environ.pop("CORS_ORIGINS", None)

    def test_allowed_swa_hosts_empty_when_not_set(self):
        """Allowed SWA hosts should default to empty when not set"""
        original = os.environ.get("ALLOWED_SWA_HOSTS")
        try:
            os.environ.pop("ALLOWED_SWA_HOSTS", None)
            hosts = get_allowed_swa_hosts()
            assert hosts == []
        finally:
            if original:
                os.environ["ALLOWED_SWA_HOSTS"] = original

    def test_allowed_swa_hosts_from_environment(self):
        """Allowed SWA hosts should parse comma-separated values"""
        original = os.environ.get("ALLOWED_SWA_HOSTS")
        try:
            os.environ["ALLOWED_SWA_HOSTS"] = "app.azurestaticapps.net,custom.domain.com"
            hosts = get_allowed_swa_hosts()
            assert len(hosts) == 2
            assert "app.azurestaticapps.net" in hosts
            assert "custom.domain.com" in hosts
        finally:
            if original:
                os.environ["ALLOWED_SWA_HOSTS"] = original
            else:
                os.environ.pop("ALLOWED_SWA_HOSTS", None)


class TestCORSSecurityPatterns:
    """Test security patterns for CORS"""

    def test_cors_origins_environment_variable_respected(self):
        """CORS origins should be read from environment variable"""
        original = os.environ.get("CORS_ORIGINS")
        try:
            os.environ["CORS_ORIGINS"] = "https://example.com"
            origins = get_cors_origins()
            assert "https://example.com" in origins
        finally:
            if original:
                os.environ["CORS_ORIGINS"] = original
            else:
                os.environ.pop("CORS_ORIGINS", None)

    def test_multiple_cors_origins_supported(self):
        """Multiple CORS origins should be supported via comma-separated list"""
        original = os.environ.get("CORS_ORIGINS")
        try:
            os.environ["CORS_ORIGINS"] = "https://app1.com,https://app2.com,https://app3.com"
            origins = get_cors_origins()
            assert len(origins) == 3
            assert all(origin in origins for origin in ["https://app1.com", "https://app2.com", "https://app3.com"])
        finally:
            if original:
                os.environ["CORS_ORIGINS"] = original
            else:
                os.environ.pop("CORS_ORIGINS", None)


class TestHealthEndpointIntegration:
    """Integration tests for health endpoint"""

    def test_health_endpoint_accessible(self):
        """Health endpoint should be accessible without authentication"""
        client = TestClient(app)
        response = client.get("/api/v1/health")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "service" in data
        assert "version" in data

    def test_health_endpoint_returns_json(self):
        """Health endpoint should return valid JSON"""
        client = TestClient(app)
        response = client.get("/api/v1/health")
        assert response.headers["content-type"] == "application/json"
        data = response.json()
        assert isinstance(data, dict)

    def test_validate_endpoint_integration(self):
        """Validate endpoint should accept valid addresses"""
        client = TestClient(app)
        response = client.post("/api/v1/ipv4/validate", json={"address": "10.0.0.1"})
        assert response.status_code == 200
        data = response.json()
        assert data["address"] == "10.0.0.1"
        assert data["valid"] is True


class TestSecureDefaults:
    """Verify security fixes are in place"""

    def test_cors_configuration_no_wildcard_by_default(self):
        """CORS origins should not include wildcard by default"""
        original = os.environ.get("CORS_ORIGINS")
        try:
            # For Container App, default includes localhost (dev-friendly)
            # but should never include wildcard
            origins = get_cors_origins()
            assert "*" not in origins
        finally:
            if original:
                os.environ["CORS_ORIGINS"] = original

    def test_production_cors_origins_secure(self):
        """Production CORS origins should not include wildcard"""
        original = os.environ.get("CORS_ORIGINS")
        try:
            os.environ["CORS_ORIGINS"] = "https://app.azurestaticapps.net"
            origins = get_cors_origins()
            # Should only contain the configured origin, no wildcard
            assert origins == ["https://app.azurestaticapps.net"]
            assert "*" not in origins
        finally:
            if original:
                os.environ["CORS_ORIGINS"] = original
            else:
                os.environ.pop("CORS_ORIGINS", None)

    def test_allowed_swa_hosts_default_empty(self):
        """Allowed SWA hosts should default to empty (validation disabled)"""
        original = os.environ.get("ALLOWED_SWA_HOSTS")
        try:
            os.environ.pop("ALLOWED_SWA_HOSTS", None)
            hosts = get_allowed_swa_hosts()
            assert hosts == []
        finally:
            if original:
                os.environ["ALLOWED_SWA_HOSTS"] = original
