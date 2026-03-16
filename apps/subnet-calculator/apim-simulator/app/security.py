from __future__ import annotations

import base64
import json
from dataclasses import dataclass
from typing import Any

import jwt
from fastapi import HTTPException, Request
from jwt import InvalidTokenError, PyJWKClient

from app.config import (
    ClientCertificateConfig,
    ClientCertificateMode,
    GatewayConfig,
    SubscriptionIdentity,
    SubscriptionState,
    TrustedClientCertificateConfig,
)


@dataclass(frozen=True)
class ClientCertContext:
    """Extracted client certificate information from proxy headers."""

    subject: str | None
    issuer: str | None
    thumbprint: str | None
    cert_pem: str | None


@dataclass(frozen=True)
class AuthContext:
    claims: dict[str, Any]
    subscription: SubscriptionIdentity | None
    subscription_products: list[str]
    client_cert: ClientCertContext | None = None


def build_client_principal(claims: dict[str, Any]) -> str:
    principal = {
        "auth_typ": "oauth2",
        "name_typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier",
        "role_typ": "http://schemas.microsoft.com/ws/2008/06/identity/claims/role",
        "claims": [
            {
                "typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier",
                "val": claims.get("sub", ""),
            },
            {"typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name", "val": claims.get("name", "")},
            {
                "typ": "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress",
                "val": claims.get("email", ""),
            },
            {"typ": "preferred_username", "val": claims.get("preferred_username", "")},
        ],
    }
    return base64.b64encode(json.dumps(principal).encode("utf-8")).decode("utf-8")


class OIDCVerifier:
    def __init__(self, issuer: str, audience: str, *, jwks_uri: str | None, jwks: dict[str, Any] | None):
        self.issuer = issuer
        self.audience = audience
        self._jwks = jwks
        self._jwks_client = PyJWKClient(jwks_uri) if (jwks_uri and not jwks) else None

    def _get_key_from_static_jwks(self, token: str) -> Any:
        from jwt.algorithms import RSAAlgorithm

        header = jwt.get_unverified_header(token)
        kid = header.get("kid")
        jwks = self._jwks or {}
        keys = jwks.get("keys") or []
        if not isinstance(keys, list) or not keys:
            raise HTTPException(status_code=401, detail="Invalid or expired access token")

        candidates = keys
        if kid:
            candidates = [k for k in keys if isinstance(k, dict) and k.get("kid") == kid]
        jwk = candidates[0] if candidates else None
        if not isinstance(jwk, dict):
            raise HTTPException(status_code=401, detail="Invalid or expired access token")
        return RSAAlgorithm.from_jwk(json.dumps(jwk))

    def decode(self, token: str) -> dict[str, Any]:
        try:
            if self._jwks_client is not None:
                signing_key = self._jwks_client.get_signing_key_from_jwt(token)
                key = signing_key.key
            else:
                key = self._get_key_from_static_jwks(token)

            return jwt.decode(
                token,
                key,
                algorithms=["RS256"],
                audience=self.audience,
                issuer=self.issuer,
            )
        except InvalidTokenError as exc:
            raise HTTPException(status_code=401, detail="Invalid or expired access token") from exc


def _unverified_claims(token: str) -> dict[str, Any]:
    try:
        return jwt.decode(
            token,
            options={
                "verify_signature": False,
                "verify_aud": False,
                "verify_iss": False,
                "verify_exp": False,
            },
        )
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired access token") from None


def _default_issuer_audience(config: GatewayConfig) -> tuple[str, str]:
    if config.oidc is not None:
        return config.oidc.issuer, config.oidc.audience
    if config.oidc_providers:
        first = next(iter(config.oidc_providers.values()))
        return first.issuer, first.audience
    return "", ""


def _subscription_bypassed(request: Request, config: GatewayConfig) -> bool:
    for cond in config.subscription.bypass:
        if cond.matches(request.headers):
            return True
    return False


def subscription_bypassed(request: Request, config: GatewayConfig) -> bool:
    return _subscription_bypassed(request, config)


def _get_subscription_key_optional(request: Request, config: GatewayConfig) -> str | None:
    for header_name in config.subscription.header_names:
        provided = request.headers.get(header_name)
        if provided:
            return provided
    for query_name in config.subscription.query_param_names:
        provided = request.query_params.get(query_name)
        if provided:
            return provided
    return None


def _require_active_subscription(config: GatewayConfig, provided_key: str) -> None:
    sub = config.subscription.lookup_subscription_by_key(provided_key)
    if sub is None:
        return
    if sub.state != SubscriptionState.Active:
        raise HTTPException(status_code=403, detail="Subscription is not active")


def validate_subscription_key(request: Request, config: GatewayConfig) -> SubscriptionIdentity | None:
    if not config.subscription.required:
        return None
    if _subscription_bypassed(request, config):
        return None

    provided = _get_subscription_key_optional(request, config)
    if not provided:
        raise HTTPException(status_code=401, detail="Missing subscription key")

    _require_active_subscription(config, provided)

    identity = config.subscription.lookup_identity_by_key(provided)
    if identity is None:
        raise HTTPException(status_code=401, detail="Invalid subscription key")
    return identity


def get_subscription_identity_optional(request: Request, config: GatewayConfig) -> SubscriptionIdentity | None:
    if _subscription_bypassed(request, config):
        return None

    provided = _get_subscription_key_optional(request, config)
    if not provided:
        return None

    _require_active_subscription(config, provided)
    identity = config.subscription.lookup_identity_by_key(provided)
    if identity is None:
        raise HTTPException(status_code=401, detail="Invalid subscription key")
    return identity


def get_subscription_products_optional(request: Request, config: GatewayConfig) -> list[str]:
    if _subscription_bypassed(request, config):
        return []
    provided = _get_subscription_key_optional(request, config)
    if not provided:
        return []

    _require_active_subscription(config, provided)
    sub = config.subscription.lookup_subscription_by_key(provided)
    return sub.products if sub is not None else []


def require_subscription_products(request: Request, config: GatewayConfig) -> list[str]:
    if _subscription_bypassed(request, config):
        return []
    provided = _get_subscription_key_optional(request, config)
    if not provided:
        raise HTTPException(status_code=401, detail="Missing subscription key")

    _require_active_subscription(config, provided)
    sub = config.subscription.lookup_subscription_by_key(provided)
    if sub is None:
        # Back-compat: key->identity mode has no products.
        if config.subscription.lookup_identity_by_key(provided) is not None:
            return []
        raise HTTPException(status_code=401, detail="Invalid subscription key")
    return sub.products


def authenticate_request(
    request: Request, config: GatewayConfig, oidc_verifiers: dict[str, OIDCVerifier]
) -> AuthContext:
    if config.allow_anonymous:
        subscription = get_subscription_identity_optional(request, config)
        products = get_subscription_products_optional(request, config)
        issuer, audience = _default_issuer_audience(config)
        claims = {
            "sub": "anon-demo",
            "email": "demo@dev.test",
            "name": "Demo User",
            "preferred_username": "demo@dev.test",
            "iss": issuer,
            "aud": audience,
        }
        return AuthContext(claims=claims, subscription=subscription, subscription_products=products)

    subscription = validate_subscription_key(request, config)
    products = require_subscription_products(request, config)

    auth_header = request.headers.get("authorization")
    if not auth_header or not auth_header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = auth_header.split(" ", 1)[1].strip()

    if not oidc_verifiers:
        raise HTTPException(status_code=500, detail="OIDC verifier not configured")

    verifier: OIDCVerifier | None = None
    if len(oidc_verifiers) == 1:
        verifier = next(iter(oidc_verifiers.values()))
    else:
        unverified = _unverified_claims(token)
        iss = unverified.get("iss")
        if isinstance(iss, str) and iss:
            for candidate in oidc_verifiers.values():
                if candidate.issuer == iss:
                    verifier = candidate
                    break

    if verifier is None:
        raise HTTPException(status_code=401, detail="Invalid or expired access token")

    claims = verifier.decode(token)
    return AuthContext(claims=claims, subscription=subscription, subscription_products=products)


def _extract_client_cert_context(request: Request, cert_cfg: ClientCertificateConfig) -> ClientCertContext | None:
    """Extract client certificate info from proxy headers."""
    subject = request.headers.get(cert_cfg.subject_header)
    issuer = request.headers.get(cert_cfg.issuer_header)
    thumbprint = request.headers.get(cert_cfg.thumbprint_header)
    cert_pem = request.headers.get(cert_cfg.cert_header)

    if not subject and not issuer and not thumbprint and not cert_pem:
        return None

    return ClientCertContext(
        subject=subject,
        issuer=issuer,
        thumbprint=thumbprint.upper() if thumbprint else None,
        cert_pem=cert_pem,
    )


def _cert_matches_trusted(cert: ClientCertContext, trusted: TrustedClientCertificateConfig) -> bool:
    """Check if client cert matches a trusted certificate config."""
    if trusted.thumbprint:
        if cert.thumbprint and cert.thumbprint.upper() == trusted.thumbprint.upper():
            return True
    if trusted.subject:
        if cert.subject and trusted.subject in cert.subject:
            return True
    if trusted.issuer:
        if cert.issuer and trusted.issuer in cert.issuer:
            return True
    # If no matching criteria specified, no match
    if not trusted.thumbprint and not trusted.subject and not trusted.issuer:
        return False
    return False


def validate_client_certificate(request: Request, config: GatewayConfig) -> ClientCertContext | None:
    """Validate client certificate based on gateway config.

    Returns:
        ClientCertContext if cert present and valid (or mode=disabled/optional with no cert)
        Raises HTTPException if mode=required and no cert, or cert doesn't match trusted list
    """
    cert_cfg = config.client_certificate
    mode = cert_cfg.mode

    if mode == ClientCertificateMode.Disabled:
        return None

    cert_ctx = _extract_client_cert_context(request, cert_cfg)

    if mode == ClientCertificateMode.Required and cert_ctx is None:
        raise HTTPException(status_code=401, detail="Client certificate required")

    if cert_ctx is None:
        return None

    # If we have trusted certificates, validate against them
    if cert_cfg.trusted_certificates:
        for trusted in cert_cfg.trusted_certificates:
            if _cert_matches_trusted(cert_ctx, trusted):
                return cert_ctx
        raise HTTPException(status_code=403, detail="Client certificate not trusted")

    # No trusted list configured - accept any cert
    return cert_ctx
