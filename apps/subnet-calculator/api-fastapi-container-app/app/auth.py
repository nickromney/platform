"""
Authentication utilities.

Provides functions for validating API keys, JWT tokens, and password hashing.
"""

from datetime import UTC, datetime, timedelta

import jwt
from pwdlib import PasswordHash

# Password hasher (uses Argon2 - modern, secure)
pwd_hash = PasswordHash.recommended()


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
