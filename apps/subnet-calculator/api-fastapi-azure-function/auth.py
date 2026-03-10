"""
Authentication utilities.

Provides functions for validating API keys, JWT tokens, OIDC tokens, and password hashing.
"""

import logging
from datetime import UTC, datetime, timedelta
from typing import Any

import httpx
import jwt
from jose import jwt as jose_jwt
from jose.exceptions import JWTError
from pwdlib import PasswordHash

# Configure logger
logger = logging.getLogger(__name__)

# Password hasher (uses Argon2 - modern, secure)
pwd_hash = PasswordHash.recommended()

# Cache for OIDC JWKS (JSON Web Key Sets)
# TODO: Implement TTL-based cache with expiration for production use.
# Consider using cachetools.TTLCache to refresh keys periodically (e.g., 1-hour TTL)
# to handle OIDC provider key rotation. Example:
#   from cachetools import TTLCache
#   _oidc_jwks_cache: TTLCache[str, Any] = TTLCache(maxsize=10, ttl=3600)
# For now, this simple dict cache is acceptable for development/testing.
_oidc_jwks_cache: dict[str, Any] = {}


def validate_api_key(api_key: str | None, valid_keys: list[str]) -> bool:
    """
    Validate an API key against the list of valid keys.

    Args:
        api_key: The API key to validate (from X-API-Key header)
        valid_keys: List of valid API keys

    Returns:
        bool: True if the API key is valid, False otherwise

    Note:
        - Returns False if api_key is None or empty (after stripping)
        - API keys are case-sensitive
        - Leading/trailing whitespace is stripped from the provided key
    """
    if not api_key:
        return False

    # Strip whitespace from the provided key
    api_key = api_key.strip()

    # Empty string after stripping is invalid
    if not api_key:
        return False

    # Case-sensitive comparison
    return api_key in valid_keys


# JWT Authentication Functions


def create_access_token(data: dict, secret_key: str, algorithm: str, expires_delta: timedelta) -> str:
    """
    Create a JWT access token.

    Args:
        data: Claims to include in token (e.g., {"sub": "username"})
        secret_key: Secret key for signing
        algorithm: Signing algorithm (e.g., "HS256")
        expires_delta: Token lifetime

    Returns:
        str: Encoded JWT token
    """
    to_encode = data.copy()

    # Add issued at time
    to_encode["iat"] = datetime.now(UTC)

    # Add expiration time
    expire = datetime.now(UTC) + expires_delta
    to_encode["exp"] = expire

    # Encode and return
    encoded_jwt = jwt.encode(to_encode, secret_key, algorithm=algorithm)
    return encoded_jwt


def decode_access_token(token: str, secret_key: str, algorithm: str) -> dict | None:
    """
    Decode and validate a JWT access token.

    Args:
        token: JWT token string
        secret_key: Secret key for verification
        algorithm: Expected algorithm

    Returns:
        dict: Token payload if valid

    Raises:
        jwt.ExpiredSignatureError: If token has expired
        jwt.InvalidTokenError: If token is invalid
    """
    payload = jwt.decode(token, secret_key, algorithms=[algorithm])
    return payload


def hash_password(password: str) -> str:
    """
    Hash a password using Argon2 (via pwdlib).

    Args:
        password: Plain text password

    Returns:
        str: Hashed password (Argon2 hash string)
    """
    return pwd_hash.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verify a password against its Argon2 hash.

    Args:
        plain_password: Plain text password to verify
        hashed_password: Argon2 hashed password to compare against

    Returns:
        bool: True if password matches hash
    """
    return pwd_hash.verify(plain_password, hashed_password)


def verify_test_user(username: str, password: str, test_users: dict) -> bool:
    """
    Verify username/password against test users with hashed passwords.

    Args:
        username: Username to check
        password: Plain text password to verify
        test_users: Dictionary of username to hashed password

    Returns:
        bool: True if credentials are valid
    """
    if username not in test_users:
        return False

    hashed_password = test_users[username]
    return verify_password(password, hashed_password)


# OIDC Authentication Functions


async def get_oidc_jwks(jwks_uri: str, issuer: str) -> dict[str, Any]:
    """
    Fetch OIDC JSON Web Key Set (JWKS) from the provider.

    Args:
        jwks_uri: Direct JWKS URI, or empty to auto-discover
        issuer: OIDC issuer URL (used for discovery if jwks_uri not provided)

    Returns:
        dict: JWKS response containing the public keys

    Raises:
        ValueError: If JWKS cannot be fetched
    """
    # Use cached JWKS if available
    cache_key = jwks_uri or issuer
    if cache_key in _oidc_jwks_cache:
        return _oidc_jwks_cache[cache_key]

    try:
        async with httpx.AsyncClient() as client:
            # If no explicit JWKS URI, discover it from the issuer
            if not jwks_uri:
                discovery_url = f"{issuer.rstrip('/')}/.well-known/openid-configuration"
                discovery_response = await client.get(discovery_url, timeout=10.0)
                discovery_response.raise_for_status()
                discovery_data = discovery_response.json()
                jwks_uri = discovery_data.get("jwks_uri")

                if not jwks_uri:
                    raise ValueError(f"No jwks_uri found in OIDC discovery document at {discovery_url}")

            # Fetch the JWKS
            jwks_response = await client.get(jwks_uri, timeout=10.0)
            jwks_response.raise_for_status()
            jwks = jwks_response.json()

            # Cache for future use
            _oidc_jwks_cache[cache_key] = jwks
            return jwks

    except httpx.HTTPError as e:
        raise ValueError(f"Failed to fetch OIDC JWKS: {e}") from e


async def validate_oidc_token(token: str, issuer: str, audience: str, jwks_uri: str = "") -> dict | None:
    """
    Validate an OIDC access token.

    Args:
        token: JWT token string
        issuer: Expected issuer URL
        audience: Expected audience (API client ID)
        jwks_uri: Optional explicit JWKS URI (auto-discovered if not provided)

    Returns:
        dict: Token payload if valid, None if invalid

    Raises:
        ValueError: If validation fails for configuration reasons
    """
    try:
        # Get the JWKS (public keys) from the OIDC provider
        jwks = await get_oidc_jwks(jwks_uri, issuer)

        # Decode and validate the token
        # python-jose will automatically select the correct key from the JWKS
        payload = jose_jwt.decode(
            token,
            jwks,
            algorithms=["RS256", "RS384", "RS512", "ES256", "ES384", "ES512"],
            audience=audience,
            issuer=issuer,
            options={
                "verify_signature": True,
                "verify_aud": True,
                "verify_iss": True,
                "verify_exp": True,
                "verify_nbf": True,
            },
        )

        return payload

    except JWTError as e:
        # Token is invalid (expired, wrong signature, etc.)
        logger.warning("OIDC token validation failed: %s", e)
        return None
    except Exception as e:
        # Unexpected error (network, configuration, etc.)
        raise ValueError(f"OIDC token validation error: {e}") from e
