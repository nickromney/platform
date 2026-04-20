"""
Entra ID (Azure Active Directory) authentication module for Flask
Implements OAuth 2.0 Authorization Code Flow with PKCE for secure authentication
"""

import os
import uuid
from collections.abc import Callable
from functools import wraps
from typing import Any

import msal
from flask import Flask, redirect, request, session, url_for


class EntraIDAuth:
    """Manages Entra ID authentication for Flask applications"""

    def __init__(
        self,
        app: Flask,
        client_id: str,
        client_secret: str,
        tenant_id: str,
        redirect_uri: str | None = None,
        scopes: list[str] | None = None,
    ):
        """
        Initialize Entra ID authentication

        Args:
            app: Flask application instance
            client_id: Azure AD application client ID
            client_secret: Azure AD application client secret
            tenant_id: Azure AD tenant ID
            redirect_uri: OAuth redirect URI (defaults to http://localhost:5000/auth/callback)
            scopes: List of scopes to request (defaults to ["User.Read"])
        """
        self.app = app
        self.client_id = client_id
        self.client_secret = client_secret
        self.tenant_id = tenant_id
        self.redirect_uri = redirect_uri or "http://localhost:5000/auth/callback"
        self.scopes = scopes or ["User.Read"]
        self.authority = f"https://login.microsoftonline.com/{tenant_id}"

        # Create MSAL app
        self.msal_app = msal.ConfidentialClientApplication(
            client_id=self.client_id,
            client_credential=self.client_secret,
            authority=self.authority,
        )

        # Register routes
        self._register_routes()

    def _register_routes(self) -> None:
        """Register authentication routes with Flask app"""
        self.app.add_url_rule("/login", "login", self.login, methods=["GET"])
        self.app.add_url_rule("/auth/callback", "auth_callback", self.auth_callback, methods=["GET"])
        self.app.add_url_rule("/logout", "logout", self.logout, methods=["GET"])

    def login(self) -> str:
        """
        Initiate OAuth login flow
        Redirects to Entra ID authorization endpoint
        """
        # Generate session state for CSRF protection
        session["state"] = str(uuid.uuid4())

        # Get authorization URL from MSAL
        auth_url = self.msal_app.get_authorization_request_url(
            scopes=self.scopes,
            redirect_uri=self.redirect_uri,
            state=session["state"],
        )

        return redirect(auth_url)

    def auth_callback(self) -> str:
        """
        OAuth callback handler
        Processes authorization code and exchanges it for tokens
        """
        # Validate state parameter (CSRF protection)
        if request.args.get("state") != session.get("state"):
            return "State validation failed", 401

        # Get authorization code
        code = request.args.get("code")
        if not code:
            error = request.args.get("error")
            error_description = request.args.get("error_description", "Unknown error")
            return f"Authorization failed: {error} - {error_description}", 401

        try:
            # Exchange code for tokens
            token_result = self.msal_app.acquire_token_by_authorization_code(
                code=code,
                scopes=self.scopes,
                redirect_uri=self.redirect_uri,
            )

            if "error" in token_result:
                error = token_result.get("error")
                error_description = token_result.get("error_description", "Unknown error")
                return f"Token acquisition failed: {error} - {error_description}", 401

            # Store token and user info in session
            session["access_token"] = token_result.get("access_token")
            session["id_token"] = token_result.get("id_token")
            session["user"] = token_result.get("id_token_claims", {})

            # Redirect to originally requested page or home
            return redirect(request.args.get("redirect_uri", url_for("index")))

        except Exception as e:
            return f"Token acquisition error: {str(e)}", 500

    def logout(self) -> str:
        """
        Logout handler
        Clears session and redirects to Entra ID logout endpoint
        """
        session.clear()

        # Redirect to Entra ID logout
        logout_url = f"{self.authority}/oauth2/v2.0/logout"
        return redirect(logout_url)

    def login_required(self, f: Callable) -> Callable:
        """
        Decorator to require authentication for a route
        Redirects to login if user is not authenticated
        """

        @wraps(f)
        def decorated_function(*args: Any, **kwargs: Any) -> Any:
            if "user" not in session:
                return redirect(url_for("login", redirect_uri=request.url))
            return f(*args, **kwargs)

        return decorated_function

    def get_user(self) -> dict | None:
        """Get authenticated user info from session"""
        return session.get("user")

    def get_access_token(self) -> str | None:
        """Get access token from session"""
        return session.get("access_token")

    def is_authenticated(self) -> bool:
        """Check if user is authenticated"""
        return "user" in session


def init_auth(
    app: Flask,
    client_id: str | None = None,
    client_secret: str | None = None,
    tenant_id: str | None = None,
    redirect_uri: str | None = None,
) -> EntraIDAuth | None:
    """
    Initialize Entra ID authentication from environment variables

    Args:
        app: Flask application instance
        client_id: Override AZURE_CLIENT_ID env var
        client_secret: Override AZURE_CLIENT_SECRET env var
        tenant_id: Override AZURE_TENANT_ID env var
        redirect_uri: Override REDIRECT_URI env var

    Returns:
        EntraIDAuth instance if all required variables are set, None otherwise
    """
    client_id = client_id or os.getenv("AZURE_CLIENT_ID")
    client_secret = client_secret or os.getenv("AZURE_CLIENT_SECRET")
    tenant_id = tenant_id or os.getenv("AZURE_TENANT_ID")
    redirect_uri = redirect_uri or os.getenv("REDIRECT_URI")

    if not all([client_id, client_secret, tenant_id]):
        return None

    return EntraIDAuth(
        app=app,
        client_id=client_id,
        client_secret=client_secret,
        tenant_id=tenant_id,
        redirect_uri=redirect_uri or "http://localhost:5000/auth/callback",
    )
