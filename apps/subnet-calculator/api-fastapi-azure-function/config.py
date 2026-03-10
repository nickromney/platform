"""
Authentication configuration management.

Handles loading and validating authentication settings from environment variables.
"""

import os
from enum import Enum


class AuthMethod(str, Enum):
    """Supported authentication methods."""

    NONE = "none"
    API_KEY = "api_key"
    JWT = "jwt"
    AZURE_SWA = "azure_swa"  # Azure Static Web Apps EasyAuth
    APIM = "apim"  # Azure API Management (trust APIM validation)
    AZURE_AD = "azure_ad"  # Direct Azure AD/Entra ID integration
    OIDC = "oidc"  # OpenID Connect (Keycloak, Okta, Auth0, etc.)


# JWT Configuration Functions


def get_jwt_secret_key() -> str:
    """
    Get JWT secret key from environment.

    Returns:
        str: Secret key for signing JWTs

    Raises:
        ValueError: If AUTH_METHOD=jwt but JWT_SECRET_KEY not set
        ValueError: If secret key is too short (< 32 chars)
    """
    auth_method = get_auth_method()

    if auth_method != AuthMethod.JWT:
        return ""

    secret = os.getenv("JWT_SECRET_KEY", "").strip()

    if not secret:
        raise ValueError("JWT_SECRET_KEY environment variable required when AUTH_METHOD=jwt")

    if len(secret) < 32:
        raise ValueError("JWT_SECRET_KEY must be at least 32 characters long")

    return secret


def get_jwt_algorithm() -> str:
    """
    Get JWT signing algorithm.

    Returns:
        str: Algorithm name (default: HS256)

    Raises:
        ValueError: If algorithm is not supported
    """
    algorithm = os.getenv("JWT_ALGORITHM", "HS256").upper()

    valid_algorithms = [
        "HS256",
        "HS384",
        "HS512",
        "RS256",
        "RS384",
        "RS512",
        "ES256",
        "ES384",
        "ES512",
    ]

    if algorithm not in valid_algorithms:
        raise ValueError(f"Invalid JWT_ALGORITHM: '{algorithm}'. Valid options: {', '.join(valid_algorithms)}")

    return algorithm


def get_jwt_expiration_minutes() -> int:
    """
    Get JWT token expiration time in minutes.

    Returns:
        int: Expiration time in minutes (default: 30)
    """
    try:
        return int(os.getenv("JWT_ACCESS_TOKEN_EXPIRE_MINUTES", "30"))
    except ValueError:
        return 30


def get_jwt_test_users() -> dict:
    """
    Get test users for JWT authentication (development only).

    Returns:
        dict: Username to password mapping

    Raises:
        ValueError: If JWT_TEST_USERS is invalid JSON
    """
    import json

    auth_method = get_auth_method()

    if auth_method != AuthMethod.JWT:
        return {}

    users_json = os.getenv("JWT_TEST_USERS", "{}").strip()

    try:
        users = json.loads(users_json)
        if not isinstance(users, dict):
            raise ValueError("JWT_TEST_USERS must be a JSON object")
        return users
    except json.JSONDecodeError as e:
        raise ValueError(f"Invalid JSON in JWT_TEST_USERS: {e}") from e


def get_auth_method() -> AuthMethod:
    """
    Get the configured authentication method from environment.

    Returns:
        AuthMethod: The authentication method to use (default: NONE)

    Raises:
        ValueError: If AUTH_METHOD is set to an invalid value
    """
    auth_method_str = os.getenv("AUTH_METHOD", "none").lower()

    try:
        return AuthMethod(auth_method_str)
    except ValueError as e:
        valid_methods = ", ".join([m.value for m in AuthMethod])
        raise ValueError(f"Invalid AUTH_METHOD: '{auth_method_str}'. Valid options: {valid_methods}") from e


def get_api_keys() -> list[str]:
    """
    Get configured API keys from environment.

    Returns:
        List[str]: List of valid API keys (empty list if not using API key auth)

    Raises:
        ValueError: If API_KEYS is required but not set or empty
    """
    auth_method = get_auth_method()

    if auth_method != AuthMethod.API_KEY:
        return []

    api_keys_str = os.getenv("API_KEYS", "").strip()

    if not api_keys_str:
        raise ValueError("API_KEYS environment variable required when AUTH_METHOD=api_key")

    # Split by comma and strip whitespace from each key
    keys = [key.strip() for key in api_keys_str.split(",")]

    # Filter out empty strings after stripping
    keys = [key for key in keys if key]

    if not keys:
        raise ValueError("API_KEYS cannot be empty when AUTH_METHOD=api_key")

    return keys


def get_cors_origins() -> list[str]:
    """
    Get allowed CORS origins from environment.

    Returns:
        List[str]: List of allowed origins (empty list means same-origin only)

    Environment variable:
        CORS_ORIGINS: Comma-separated list of allowed origins
                     If not set or empty, returns empty list (no wildcard)
    """
    cors_origins_str = os.getenv("CORS_ORIGINS", "").strip()

    if not cors_origins_str:
        return []

    # Split by comma and strip whitespace from each origin
    origins = [origin.strip() for origin in cors_origins_str.split(",")]

    # Filter out empty strings after stripping
    origins = [origin for origin in origins if origin]

    return origins


def get_allowed_swa_hosts() -> list[str]:
    """
    Get allowed Azure Static Web Apps hostnames from environment.

    Returns:
        List[str]: List of allowed SWA hostnames (empty list means no validation)

    Environment variable:
        ALLOWED_SWA_HOSTS: Comma-separated list of SWA hostnames
                          Example: app.azurestaticapps.net,custom-domain.com
    """
    swa_hosts_str = os.getenv("ALLOWED_SWA_HOSTS", "").strip()

    if not swa_hosts_str:
        return []

    # Split by comma and strip whitespace from each hostname
    hosts = [host.strip() for host in swa_hosts_str.split(",")]

    # Filter out empty strings after stripping
    hosts = [host for host in hosts if host]

    return hosts


def get_oidc_issuer() -> str:
    """
    Get OIDC issuer URL from environment.

    Returns:
        str: OIDC issuer URL (e.g., https://keycloak.example.com/realms/my-realm)

    Raises:
        ValueError: If AUTH_METHOD=oidc but OIDC_ISSUER not set
    """
    auth_method = get_auth_method()

    if auth_method != AuthMethod.OIDC:
        return ""

    issuer = os.getenv("OIDC_ISSUER", "").strip()

    if not issuer:
        raise ValueError("OIDC_ISSUER environment variable required when AUTH_METHOD=oidc")

    return issuer


def get_oidc_audience() -> str:
    """
    Get expected OIDC token audience from environment.

    Returns:
        str: Expected audience value (client ID of this API)

    Raises:
        ValueError: If AUTH_METHOD=oidc but OIDC_AUDIENCE not set
    """
    auth_method = get_auth_method()

    if auth_method != AuthMethod.OIDC:
        return ""

    audience = os.getenv("OIDC_AUDIENCE", "").strip()

    if not audience:
        raise ValueError("OIDC_AUDIENCE environment variable required when AUTH_METHOD=oidc")

    return audience


def get_oidc_jwks_uri() -> str:
    """
    Get OIDC JWKS URI from environment.

    Returns:
        str: JWKS URI (e.g., https://keycloak.example.com/realms/my-realm/protocol/openid-connect/certs)
             If not set, will be auto-discovered from issuer metadata

    Note:
        If OIDC_JWKS_URI is not provided, the JWKS URI will be fetched from the
        OIDC discovery endpoint at {issuer}/.well-known/openid-configuration
    """
    return os.getenv("OIDC_JWKS_URI", "").strip()


def validate_configuration():
    """
    Validate authentication configuration at startup.

    Raises:
        ValueError: If configuration is invalid
    """
    auth_method = get_auth_method()

    if auth_method == AuthMethod.API_KEY:
        # This will raise ValueError if API_KEYS is missing or empty
        get_api_keys()

    elif auth_method == AuthMethod.JWT:
        # This will raise ValueError if JWT_SECRET_KEY is missing or too short
        get_jwt_secret_key()
        # Validate algorithm is supported
        get_jwt_algorithm()

    elif auth_method == AuthMethod.OIDC:
        # This will raise ValueError if OIDC settings are missing
        get_oidc_issuer()
        get_oidc_audience()
