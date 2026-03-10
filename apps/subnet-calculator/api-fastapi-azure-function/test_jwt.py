"""
Tests for JWT authentication functionality.

This test suite covers:
- Configuration loading (JWT_SECRET_KEY, JWT_ALGORITHM, etc.)
- Login endpoint (POST /api/v1/auth/login)
- Token generation and validation
- Token expiration
- All endpoints protected
- Edge cases

Note: Tests currently fail because JWT functionality not yet implemented (TDD).
"""

import time
from datetime import UTC, datetime, timedelta

import jwt as pyjwt
import pytest
from fastapi.testclient import TestClient

from function_app import api

# Create test client
client = TestClient(api)


# Configuration Tests
class TestJWTConfiguration:
    """Test JWT configuration loading."""

    def test_jwt_mode_requires_secret_key(self, monkeypatch):
        """AUTH_METHOD=jwt without JWT_SECRET_KEY should raise error."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.delenv("JWT_SECRET_KEY", raising=False)

        # Test config function directly
        from config import get_jwt_secret_key

        with pytest.raises(ValueError, match="JWT_SECRET_KEY environment variable required"):
            get_jwt_secret_key()

    def test_jwt_mode_requires_long_secret(self, monkeypatch):
        """JWT_SECRET_KEY must be at least 32 characters."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "short")

        # Test config function directly
        from config import get_jwt_secret_key

        with pytest.raises(ValueError, match="JWT_SECRET_KEY must be at least 32 characters"):
            get_jwt_secret_key()

    def test_jwt_default_algorithm_hs256(self, monkeypatch):
        """Default JWT algorithm should be HS256."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "a" * 32)
        monkeypatch.delenv("JWT_ALGORITHM", raising=False)

        from config import get_jwt_algorithm

        assert get_jwt_algorithm() == "HS256"

    def test_jwt_default_expiration_30_minutes(self, monkeypatch):
        """Default token expiration should be 30 minutes."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "a" * 32)
        monkeypatch.delenv("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", raising=False)

        from config import get_jwt_expiration_minutes

        assert get_jwt_expiration_minutes() == 30

    def test_jwt_test_users_from_json(self, monkeypatch):
        """JWT_TEST_USERS should parse JSON correctly."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "a" * 32)
        # Note: In production, these would be Argon2 hashes, but for this test we just verify JSON parsing
        monkeypatch.setenv("JWT_TEST_USERS", '{"alice":"hash1","bob":"hash2"}')

        from config import get_jwt_test_users

        users = get_jwt_test_users()
        assert users == {"alice": "hash1", "bob": "hash2"}

    def test_jwt_invalid_algorithm_raises_error(self, monkeypatch):
        """Invalid JWT_ALGORITHM should raise error."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "a" * 32)
        monkeypatch.setenv("JWT_ALGORITHM", "MD5")

        from config import get_jwt_algorithm

        with pytest.raises(ValueError, match="Invalid JWT_ALGORITHM"):
            get_jwt_algorithm()


# Login Endpoint Tests
class TestLoginEndpoint:
    """Test the /api/v1/auth/login endpoint."""

    @pytest.fixture(autouse=True)
    def setup_jwt_auth(self, monkeypatch):
        """Set up environment for JWT auth with Argon2 hashed passwords."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key-minimum-32-chars-long")
        # Use Argon2 hashed passwords (alice=password123, bob=securepass)
        monkeypatch.setenv(
            "JWT_TEST_USERS",
            '{"alice":"$argon2id$v=19$m=65536,t=3,p=4$3MKxLJSv0Ol1eueygZAV6w$mb8m63Id29lRAjPrYv+K180PAqxhRyoqkWBLQMPZ0ZM",'
            '"bob":"$argon2id$v=19$m=65536,t=3,p=4$2QqZOyq9uYoLXvPnS2cRtA$w3sYdUCtbDNu2myGr8Z9g9qi9Ya2NDGdXBs5f6cbjR0"}',
        )

    def test_login_with_valid_credentials_returns_token(self):
        """Login with valid credentials should return access token."""
        response = client.post("/api/v1/auth/login", data={"username": "alice", "password": "password123"})
        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"

    def test_login_with_invalid_username_returns_401(self):
        """Login with invalid username should return 401."""
        response = client.post(
            "/api/v1/auth/login",
            data={"username": "invalid", "password": "password123"},
        )
        assert response.status_code == 401
        assert "incorrect username or password" in response.json()["detail"].lower()

    def test_login_with_invalid_password_returns_401(self):
        """Login with invalid password should return 401."""
        response = client.post(
            "/api/v1/auth/login",
            data={"username": "alice", "password": "wrongpassword"},
        )
        assert response.status_code == 401

    def test_login_missing_username_returns_422(self):
        """Login without username should return 422 (validation error)."""
        response = client.post("/api/v1/auth/login", data={"password": "password123"})
        assert response.status_code == 422

    def test_login_missing_password_returns_422(self):
        """Login without password should return 422."""
        response = client.post("/api/v1/auth/login", data={"username": "alice"})
        assert response.status_code == 422

    def test_login_returns_different_tokens(self):
        """Each login should generate a different token (iat differs)."""
        response1 = client.post("/api/v1/auth/login", data={"username": "alice", "password": "password123"})
        time.sleep(1)
        response2 = client.post("/api/v1/auth/login", data={"username": "alice", "password": "password123"})

        token1 = response1.json()["access_token"]
        token2 = response2.json()["access_token"]
        assert token1 != token2

    def test_login_token_contains_username(self):
        """JWT payload should contain username in 'sub' claim."""
        response = client.post("/api/v1/auth/login", data={"username": "alice", "password": "password123"})
        token = response.json()["access_token"]

        # Decode without verification (for testing only)
        payload = pyjwt.decode(token, options={"verify_signature": False})
        assert payload["sub"] == "alice"

    def test_login_token_has_expiration(self):
        """JWT should have 'exp' claim set to 30 minutes from now."""
        response = client.post("/api/v1/auth/login", data={"username": "alice", "password": "password123"})
        token = response.json()["access_token"]

        payload = pyjwt.decode(token, options={"verify_signature": False})

        exp = datetime.fromtimestamp(payload["exp"], tz=UTC)
        now = datetime.now(UTC)
        delta = exp - now

        # Should be approximately 30 minutes (allow 1 second variance)
        assert 1799 <= delta.total_seconds() <= 1801


# Token Validation Tests
class TestJWTTokenValidation:
    """Test JWT token validation in middleware."""

    @pytest.fixture(autouse=True)
    def setup_jwt_auth(self, monkeypatch):
        """Set up environment for JWT auth with Argon2 hashed password."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key-minimum-32-chars-long")
        # Use Argon2 hashed password (alice=password123)
        monkeypatch.setenv(
            "JWT_TEST_USERS",
            '{"alice":"$argon2id$v=19$m=65536,t=3,p=4$3MKxLJSv0Ol1eueygZAV6w$mb8m63Id29lRAjPrYv+K180PAqxhRyoqkWBLQMPZ0ZM"}',
        )

    def get_valid_token(self):
        """Helper to get a valid JWT token."""
        response = client.post("/api/v1/auth/login", data={"username": "alice", "password": "password123"})
        return response.json()["access_token"]

    def test_missing_authorization_header_returns_401(self):
        """Request without Authorization header should return 401."""
        response = client.post("/api/v1/ipv4/validate", json={"address": "192.168.1.1"})
        assert response.status_code == 401
        assert "authorization header" in response.json()["detail"].lower()

    def test_invalid_authorization_scheme_returns_401(self):
        """Authorization header without 'Bearer' should return 401."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": "Basic abc123"},
        )
        assert response.status_code == 401
        assert "bearer" in response.json()["detail"].lower()

    def test_malformed_token_returns_401(self):
        """Malformed JWT should return 401."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": "Bearer not.a.valid.jwt"},
        )
        assert response.status_code == 401
        assert "invalid token" in response.json()["detail"].lower()

    def test_tampered_token_returns_401(self):
        """Token with modified payload should fail signature verification."""
        token = self.get_valid_token()
        # Modify token by changing a character
        tampered = token[:-5] + "XXXXX"
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": f"Bearer {tampered}"},
        )
        assert response.status_code == 401

    def test_expired_token_returns_401(self, monkeypatch):
        """Expired token should return 401."""
        # Create token that expires in 1 second
        monkeypatch.setenv("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", "0")

        # Need to get a fresh token with the new expiration
        response = client.post("/api/v1/auth/login", data={"username": "alice", "password": "password123"})
        token = response.json()["access_token"]

        time.sleep(2)  # Wait for expiration

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 401
        assert "expired" in response.json()["detail"].lower()

    def test_valid_token_returns_200(self):
        """Request with valid token should succeed."""
        token = self.get_valid_token()
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 200

    def test_token_works_for_all_endpoints(self):
        """Valid token should work for all protected API endpoints."""
        token = self.get_valid_token()
        headers = {"Authorization": f"Bearer {token}"}

        endpoints = [
            ("POST", "/api/v1/ipv4/validate", {"address": "192.168.1.1"}),
            ("POST", "/api/v1/ipv4/check-private", {"address": "192.168.1.1"}),
        ]

        for method, url, body in endpoints:
            response = client.post(url, json=body, headers=headers)
            assert response.status_code == 200, f"Failed for {method} {url}"

    def test_token_signed_with_different_key_fails(self):
        """Token signed with different secret should fail verification."""
        # Create a token manually with a different secret
        payload = {
            "sub": "alice",
            "iat": datetime.now(UTC),
            "exp": datetime.now(UTC) + timedelta(minutes=30),
        }
        token = pyjwt.encode(payload, "different-secret-key-32-chars-long", algorithm="HS256")

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 401

    def test_token_with_missing_sub_claim_returns_401(self):
        """Token without 'sub' claim should return 401."""
        # Manually create token without 'sub'
        payload = {
            "iat": datetime.now(UTC),
            "exp": datetime.now(UTC) + timedelta(minutes=30),
        }
        token = pyjwt.encode(payload, "test-secret-key-minimum-32-chars-long", algorithm="HS256")

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": f"Bearer {token}"},
        )
        assert response.status_code == 401

    def test_case_sensitivity_in_bearer_scheme(self):
        """'Bearer' should be case-insensitive per RFC 6750."""
        token = self.get_valid_token()

        # Test different cases
        for scheme in ["Bearer", "bearer", "BEARER"]:
            response = client.post(
                "/api/v1/ipv4/validate",
                json={"address": "192.168.1.1"},
                headers={"Authorization": f"{scheme} {token}"},
            )
            assert response.status_code == 200, f"Failed for scheme: {scheme}"


# Edge Cases
class TestJWTEdgeCases:
    """Test JWT edge cases and security scenarios."""

    @pytest.fixture(autouse=True)
    def setup_jwt_auth(self, monkeypatch):
        """Set up environment for JWT auth with Argon2 hashed password."""
        monkeypatch.setenv("AUTH_METHOD", "jwt")
        monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key-minimum-32-chars-long")
        # Use Argon2 hashed password (alice=password123)
        monkeypatch.setenv(
            "JWT_TEST_USERS",
            '{"alice":"$argon2id$v=19$m=65536,t=3,p=4$3MKxLJSv0Ol1eueygZAV6w$mb8m63Id29lRAjPrYv+K180PAqxhRyoqkWBLQMPZ0ZM"}',
        )

    def get_valid_token(self):
        """Helper to get a valid JWT token."""
        response = client.post("/api/v1/auth/login", data={"username": "alice", "password": "password123"})
        return response.json()["access_token"]

    def test_empty_authorization_header_returns_401(self):
        """Empty Authorization header should return 401."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": ""},
        )
        assert response.status_code == 401

    def test_authorization_header_with_only_bearer_returns_401(self):
        """'Bearer' without token should return 401."""
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": "Bearer"},
        )
        assert response.status_code == 401

    def test_authorization_header_with_extra_whitespace(self):
        """Token should work with extra whitespace in Authorization header."""
        token = self.get_valid_token()

        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": f"  Bearer   {token}  "},
        )
        assert response.status_code == 200

    def test_multiple_bearer_tokens_returns_401(self):
        """Authorization header with multiple tokens should return 401."""
        token = self.get_valid_token()
        response = client.post(
            "/api/v1/ipv4/validate",
            json={"address": "192.168.1.1"},
            headers={"Authorization": f"Bearer {token} extra-token"},
        )
        assert response.status_code == 401
