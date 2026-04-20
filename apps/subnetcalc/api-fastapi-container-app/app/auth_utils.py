"""Authentication utilities for FastAPI endpoints.

Provides get_current_user dependency for protecting endpoints.
"""

import jwt
from fastapi import HTTPException, Request, status

from .auth import decode_access_token
from .config import (
    AuthMethod,
    get_auth_method,
    get_jwt_algorithm,
    get_jwt_secret_key,
)


async def get_current_user(request: Request) -> str:
    """
    FastAPI dependency to get current authenticated user.

    Supports multiple authentication methods:
    - none: Returns "anonymous" (no auth required)
    - api_key: Returns "api_key_user" (middleware validates)
    - jwt: Validates Bearer token and returns username from 'sub' claim
    - azure_swa: Parses x-ms-client-principal header
    - apim: Trusts X-User-ID/X-User-Email headers from APIM

    Args:
        request: FastAPI Request object

    Returns:
        str: Username from token's 'sub' claim, "anonymous", or "api_key_user"

    Raises:
        HTTPException: 401 if authentication fails
    """
    auth_method = get_auth_method()

    # No authentication required
    if auth_method == AuthMethod.NONE:
        return "anonymous"

    # API key authentication - middleware handles it
    # This dependency just passes through
    if auth_method == AuthMethod.API_KEY:
        return "api_key_user"

    # JWT authentication
    if auth_method == AuthMethod.JWT:
        # Manually parse Authorization header for better error messages
        authorization = request.headers.get("Authorization")

        # Missing Authorization header
        if not authorization:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Missing authorization header",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Strip whitespace and parse scheme and token
        authorization = authorization.strip()

        if not authorization:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Empty authorization header",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Split by whitespace (handles multiple spaces)
        parts = authorization.split()

        # Check for Bearer scheme
        if len(parts) == 0 or parts[0].lower() != "bearer":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authorization scheme. Expected Bearer",
                headers={"WWW-Authenticate": "Bearer"},
            )

        # Check for token
        if len(parts) != 2:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authorization header format",
                headers={"WWW-Authenticate": "Bearer"},
            )

        token = parts[1]

        # Validate JWT token
        try:
            secret_key = get_jwt_secret_key()
            algorithm = get_jwt_algorithm()
            payload = decode_access_token(token, secret_key, algorithm)

            username = payload.get("sub")
            if username is None:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Could not validate credentials",
                    headers={"WWW-Authenticate": "Bearer"},
                )

            return username

        except jwt.ExpiredSignatureError as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token has expired",
                headers={"WWW-Authenticate": "Bearer"},
            ) from e
        except jwt.InvalidTokenError as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token",
                headers={"WWW-Authenticate": "Bearer"},
            ) from e

    # Azure Static Web Apps EasyAuth
    if auth_method == AuthMethod.AZURE_SWA:
        # SWA injects x-ms-client-principal header after authentication
        principal_header = request.headers.get("x-ms-client-principal")

        if not principal_header:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Azure SWA authentication required but no principal found",
            )

        try:
            # Decode base64-encoded JSON
            import base64
            import json

            principal_json = base64.b64decode(principal_header).decode("utf-8")
            claims = json.loads(principal_json)

            # Extract user identity from claims
            user_details = claims.get("userDetails")  # Email
            user_id = claims.get("userId")  # Unique ID

            # Return email if available, otherwise user ID
            user = user_details or user_id

            if not user:
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Invalid Azure SWA principal: missing user identity",
                )

            return user

        except (ValueError, KeyError, json.JSONDecodeError) as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid Azure SWA principal: {str(e)}",
            ) from e

    # Azure API Management (APIM)
    if auth_method == AuthMethod.APIM:
        # APIM validates JWT and injects user claims into headers
        user_id = request.headers.get("X-User-ID")
        user_email = request.headers.get("X-User-Email")

        # Prefer email, fall back to user ID
        user = user_email or user_id

        if not user:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="APIM authentication required but no user headers found",
            )

        return user

    # Unknown auth method
    raise HTTPException(
        status_code=status.HTTP_501_NOT_IMPLEMENTED,
        detail="Authentication method not implemented",
    )
