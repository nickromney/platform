"""Tests for authentication functionality."""

import pytest
from fastapi.testclient import TestClient


class TestNoAuthMode:
    """Tests for AUTH_METHOD=none."""

    @pytest.fixture(autouse=True)
    def setup_env(self, monkeypatch):
        """Set environment to no auth mode."""
        monkeypatch.setenv("AUTH_METHOD", "none")
        # Reload app to pick up new env vars
        from importlib import reload

        from app import config, main

        reload(config)
        reload(main)

    @pytest.fixture
    def client(self):
        """Create test client."""
        from app.main import app

        return TestClient(app)

    def test_no_auth_allows_all_requests(self, client):
        """Test that no auth mode allows requests without credentials."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24", "mode": "Azure"})
        assert response.status_code == 200

    def test_no_auth_ignores_api_key_header(self, client):
        """Test that API keys are ignored in no auth mode."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"X-API-Key": "invalid-key"},
        )
        assert response.status_code == 200


class TestAPIKeyMode:
    """Tests for AUTH_METHOD=api_key."""

    @pytest.fixture(autouse=True)
    def setup_env(self, monkeypatch):
        """Set environment to API key mode."""
        monkeypatch.setenv("AUTH_METHOD", "api_key")
        monkeypatch.setenv("API_KEYS", "test-key-123,test-key-456")
        # Reload app to pick up new env vars
        from importlib import reload

        from app import config, main

        reload(config)
        reload(main)

    @pytest.fixture
    def client(self):
        """Create test client."""
        from app.main import app

        return TestClient(app)

    def test_missing_api_key_returns_401(self, client):
        """Test that missing API key returns 401."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24", "mode": "Azure"})
        assert response.status_code == 401

    def test_invalid_api_key_returns_401(self, client):
        """Test that invalid API key returns 401."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"X-API-Key": "invalid-key"},
        )
        assert response.status_code == 401

    def test_valid_api_key_returns_200(self, client):
        """Test that valid API key allows access."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"X-API-Key": "test-key-123"},
        )
        assert response.status_code == 200

    def test_multiple_valid_keys_all_work(self, client):
        """Test that all configured keys work."""
        for key in ["test-key-123", "test-key-456"]:
            response = client.post(
                "/api/v1/ipv4/subnet-info",
                json={"network": "192.168.1.0/24", "mode": "Azure"},
                headers={"X-API-Key": key},
            )
            assert response.status_code == 200

    def test_health_endpoint_requires_no_auth(self, client):
        """Test that health endpoint doesn't require auth."""
        response = client.get("/api/v1/health")
        assert response.status_code == 200

    def test_docs_endpoint_requires_no_auth(self, client):
        """Test that docs endpoint doesn't require auth."""
        response = client.get("/api/v1/docs")
        assert response.status_code == 200

    def test_empty_api_key_header_returns_401(self, client):
        """Test that empty API key header returns 401."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"X-API-Key": ""},
        )
        assert response.status_code == 401

    def test_whitespace_api_key_returns_401(self, client):
        """Test that whitespace-only API key returns 401."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"X-API-Key": "   "},
        )
        assert response.status_code == 401


class TestJWTMode:
    """Tests for AUTH_METHOD=jwt."""

    @pytest.fixture(autouse=True)
    def setup_env(self, monkeypatch):
        """Set environment to JWT mode."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key-minimum-32-chars-long-123456789")
        monkeypatch.setenv("JWT_ALGORITHM", "HS256")
        monkeypatch.setenv("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", "30")
        # Use pre-hashed password for "demo" user with password "password123"
        monkeypatch.setenv(
            "JWT_TEST_USERS",
            '{"demo": "$argon2id$v=19$m=65536,t=3,p=4$OT3Rp/FENYROxqB7RxEc7A$stcjNX4fdarJH+GbxTyQeiyCOJi15GjQA2U8uTJlhII"}',
        )
        # Reload app to pick up new env vars
        from importlib import reload

        from app import auth, auth_utils, config, main

        reload(config)
        reload(auth)
        reload(auth_utils)
        reload(main)

    @pytest.fixture
    def client(self):
        """Create test client."""
        from app.main import app

        return TestClient(app)

    @pytest.fixture
    def valid_token(self, client):
        """Get a valid JWT token."""
        response = client.post("/api/v1/auth/login", data={"username": "demo", "password": "password123"})
        assert response.status_code == 200
        return response.json()["access_token"]

    def test_login_with_valid_credentials(self, client):
        """Test login with valid credentials returns token."""
        response = client.post("/api/v1/auth/login", data={"username": "demo", "password": "password123"})
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"

    def test_login_with_invalid_username(self, client):
        """Test login with invalid username returns 401."""
        response = client.post("/api/v1/auth/login", data={"username": "invalid", "password": "password123"})
        assert response.status_code == 401

    def test_login_with_invalid_password(self, client):
        """Test login with invalid password returns 401."""
        response = client.post("/api/v1/auth/login", data={"username": "demo", "password": "wrong"})
        assert response.status_code == 401

    def test_missing_authorization_header_returns_401(self, client):
        """Test that missing Authorization header returns 401."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24", "mode": "Azure"})
        assert response.status_code == 401

    def test_invalid_authorization_scheme_returns_401(self, client, valid_token):
        """Test that non-Bearer scheme returns 401."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"Authorization": f"Basic {valid_token}"},
        )
        assert response.status_code == 401

    def test_valid_token_returns_200(self, client, valid_token):
        """Test that valid token allows access."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"Authorization": f"Bearer {valid_token}"},
        )
        assert response.status_code == 200

    def test_health_endpoint_requires_no_auth(self, client):
        """Test that health endpoint doesn't require auth."""
        response = client.get("/api/v1/health")
        assert response.status_code == 200

    def test_empty_authorization_header_returns_401(self, client):
        """Test that empty Authorization header returns 401."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"Authorization": ""},
        )
        assert response.status_code == 401

    def test_malformed_token_returns_401(self, client):
        """Test that malformed token returns 401."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"Authorization": "Bearer not-a-valid-token"},
        )
        assert response.status_code == 401


class TestAzureSWAMode:
    """Tests for AUTH_METHOD=azure_swa."""

    @pytest.fixture(autouse=True)
    def setup_env(self, monkeypatch):
        """Set environment to Azure SWA mode."""
        monkeypatch.setenv("AUTH_METHOD", "azure_swa")
        # Reload app to pick up new env vars
        from importlib import reload

        from app import auth_utils, config, main

        reload(config)
        reload(auth_utils)
        reload(main)

    @pytest.fixture
    def client(self):
        """Create test client."""
        from app.main import app

        return TestClient(app)

    def test_valid_principal_with_email(self, client):
        """Test valid principal with email."""
        import base64
        import json

        principal = {
            "userId": "user123",
            "userDetails": "user@example.com",
            "identityProvider": "aad",
        }
        encoded = base64.b64encode(json.dumps(principal).encode()).decode()

        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"x-ms-client-principal": encoded},
        )
        assert response.status_code == 200

    def test_missing_principal_returns_401(self, client):
        """Test that missing principal header returns 401."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24", "mode": "Azure"})
        assert response.status_code == 401


class TestAPIMMode:
    """Tests for AUTH_METHOD=apim."""

    @pytest.fixture(autouse=True)
    def setup_env(self, monkeypatch):
        """Set environment to APIM mode."""
        monkeypatch.setenv("AUTH_METHOD", "apim")
        # Reload app to pick up new env vars
        from importlib import reload

        from app import auth_utils, config, main

        reload(config)
        reload(auth_utils)
        reload(main)

    @pytest.fixture
    def client(self):
        """Create test client."""
        from app.main import app

        return TestClient(app)

    def test_valid_user_id_header(self, client):
        """Test valid X-User-ID header."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"X-User-ID": "user123"},
        )
        assert response.status_code == 200

    def test_valid_user_email_header(self, client):
        """Test valid X-User-Email header."""
        response = client.post(
            "/api/v1/ipv4/subnet-info",
            json={"network": "192.168.1.0/24", "mode": "Azure"},
            headers={"X-User-Email": "user@example.com"},
        )
        assert response.status_code == 200

    def test_missing_user_headers_returns_401(self, client):
        """Test that missing user headers returns 401."""
        response = client.post("/api/v1/ipv4/subnet-info", json={"network": "192.168.1.0/24", "mode": "Azure"})
        assert response.status_code == 401
