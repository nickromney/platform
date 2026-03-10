from __future__ import annotations

import json
import os
from enum import Enum
from typing import Any

from pydantic import BaseModel, Field


class ApiVersioningScheme(str, Enum):
    Header = "Header"
    Query = "Query"
    Segment = "Segment"


class ApiVersionSetConfig(BaseModel):
    # Mirrors the ARM shape for Microsoft.ApiManagement/service/api-version-sets.
    # https://learn.microsoft.com/en-us/azure/templates/microsoft.apimanagement/service/api-version-sets
    display_name: str
    description: str | None = None
    versioning_scheme: ApiVersioningScheme
    version_header_name: str | None = None
    version_query_name: str | None = None
    default_version: str | None = None

    def model_post_init(self, __context: Any) -> None:
        if self.versioning_scheme == ApiVersioningScheme.Header and not self.version_header_name:
            raise ValueError("version_header_name is required when versioning_scheme=Header")
        if self.versioning_scheme == ApiVersioningScheme.Query and not self.version_query_name:
            raise ValueError("version_query_name is required when versioning_scheme=Query")


class HeaderCondition(BaseModel):
    header: str
    starts_with: str | None = None
    equals: str | None = None

    def matches(self, headers: Any) -> bool:
        value = headers.get(self.header)
        if value is None:
            return False
        if self.equals is not None:
            return value == self.equals
        if self.starts_with is not None:
            return value.startswith(self.starts_with)
        return False


class SubscriptionIdentity(BaseModel):
    id: str
    name: str


class SubscriptionKeyPair(BaseModel):
    primary: str
    secondary: str


class SubscriptionState(str, Enum):
    Active = "active"
    Suspended = "suspended"
    Cancelled = "cancelled"


class Subscription(BaseModel):
    id: str
    name: str
    keys: SubscriptionKeyPair
    state: SubscriptionState = SubscriptionState.Active
    products: list[str] = Field(default_factory=list)
    created_by: str | None = None

    def identity(self) -> SubscriptionIdentity:
        return SubscriptionIdentity(id=self.id, name=self.name)


class SubscriptionConfig(BaseModel):
    required: bool = True
    header_names: list[str] = Field(
        default_factory=lambda: ["Ocp-Apim-Subscription-Key", "X-Ocp-Apim-Subscription-Key"]
    )
    query_param_names: list[str] = Field(default_factory=lambda: ["subscription-key"])
    # Back-compat/simple mode: direct map of key -> identity
    keys: dict[str, SubscriptionIdentity] = Field(default_factory=dict)
    # APIM-style: subscriptions are named containers, each with 2 keys
    subscriptions: dict[str, Subscription] = Field(default_factory=dict)
    bypass: list[HeaderCondition] = Field(default_factory=list)

    def lookup_subscription_by_key(self, key: str) -> Subscription | None:
        for sub in self.subscriptions.values():
            if key == sub.keys.primary or key == sub.keys.secondary:
                return sub
        return None

    def lookup_identity_by_key(self, key: str) -> SubscriptionIdentity | None:
        identity = self.keys.get(key)
        if identity is not None:
            return identity
        sub = self.lookup_subscription_by_key(key)
        return sub.identity() if sub is not None else None


class OIDCConfig(BaseModel):
    issuer: str
    audience: str
    jwks_uri: str | None = None
    jwks: dict[str, Any] | None = None


class TenantAccessConfig(BaseModel):
    enabled: bool = False
    primary_key: str | None = None
    secondary_key: str | None = None


class ClientCertificateMode(str, Enum):
    """Maps to Azure APIM client certificate settings.

    - disabled: No client cert required (default)
    - optional: Client cert accepted but not required (negotiate_client_certificate=true)
    - required: Client cert required for all requests (client_certificate_enabled=true, Consumption SKU)
    """

    Disabled = "disabled"
    Optional = "optional"
    Required = "required"


class TrustedClientCertificateConfig(BaseModel):
    """A trusted client CA or leaf certificate for mTLS validation."""

    name: str
    subject: str | None = None
    issuer: str | None = None
    thumbprint: str | None = None


class ClientCertificateConfig(BaseModel):
    """Client certificate (mTLS) settings for the gateway.

    Maps to Azure APIM settings:
    - client_certificate_enabled (Consumption SKU): requires client cert
    - negotiate_client_certificate (hostname_configuration): optional client cert

    When running behind a TLS-terminating proxy (nginx, envoy, AppGW), the proxy
    forwards cert details via headers:
    - X-Client-Cert-Subject: CN=client,O=org
    - X-Client-Cert-Issuer: CN=ca,O=org
    - X-Client-Cert-Thumbprint: SHA1 fingerprint
    - X-Client-Cert: Base64-encoded DER or PEM

    The simulator validates these headers against trusted_certificates when mode != disabled.
    """

    mode: ClientCertificateMode = ClientCertificateMode.Disabled
    trusted_certificates: list[TrustedClientCertificateConfig] = Field(default_factory=list)
    # Header names (configurable to match your proxy)
    subject_header: str = "X-Client-Cert-Subject"
    issuer_header: str = "X-Client-Cert-Issuer"
    thumbprint_header: str = "X-Client-Cert-Thumbprint"
    cert_header: str = "X-Client-Cert"


class RouteAuthzConfig(BaseModel):
    required_scopes: list[str] = Field(default_factory=list)
    required_roles: list[str] = Field(default_factory=list)
    required_claims: dict[str, str] = Field(default_factory=dict)


class NamedValueConfig(BaseModel):
    value: str
    secret: bool = False


class UserConfig(BaseModel):
    id: str
    email: str | None = None
    name: str | None = None


class GroupConfig(BaseModel):
    id: str
    name: str
    users: list[str] = Field(default_factory=list)


class ProductConfig(BaseModel):
    name: str
    description: str | None = None
    require_subscription: bool = True


class BackendConfig(BaseModel):
    url: str
    description: str | None = None
    auth_type: str = "none"  # none|basic|managed_identity|client_certificate
    basic_username: str | None = None
    basic_password: str | None = None
    managed_identity_resource: str | None = None


class RouteConfig(BaseModel):
    name: str
    path_prefix: str
    host_match: list[str] = Field(default_factory=list)
    methods: list[str] | None = None
    upstream_base_url: str
    upstream_path_prefix: str = ""
    backend: str | None = None
    product: str | None = None
    products: list[str] = Field(default_factory=list)
    api_version_set: str | None = None
    api_version: str | None = None
    authz: RouteAuthzConfig | None = None
    policies_xml: str | None = None
    policies_xml_documents: list[str] = Field(default_factory=list)

    def matches(self, *, method: str, path: str) -> bool:
        if not self.matches_path(path):
            return False
        if not self.methods:
            return True
        return method.upper() in {m.upper() for m in self.methods}

    def matches_path(self, path: str) -> bool:
        prefix = self.path_prefix.rstrip("/")
        if not prefix:
            return True
        return path == prefix or path.startswith(prefix + "/")

    def build_upstream_url(self, path: str, *, upstream_base_url: str | None = None) -> str:
        prefix = self.path_prefix.rstrip("/")
        remainder = path
        if prefix and (path == prefix or path.startswith(prefix + "/")):
            remainder = path[len(prefix) :]
        if not remainder.startswith("/"):
            remainder = "/" + remainder
        upstream_prefix = self.upstream_path_prefix.rstrip("/")
        upstream_path = (upstream_prefix + remainder) if upstream_prefix else remainder
        base = (upstream_base_url or self.upstream_base_url).rstrip("/")
        return base + upstream_path


class GatewayConfig(BaseModel):
    schema_version: int = 1
    allowed_origins: list[str] = Field(default_factory=lambda: ["http://localhost:3007"])
    allow_anonymous: bool = False
    client_certificate: ClientCertificateConfig = Field(default_factory=ClientCertificateConfig)
    oidc: OIDCConfig | None = None
    oidc_providers: dict[str, OIDCConfig] = Field(default_factory=dict)
    products: dict[str, ProductConfig] = Field(default_factory=dict)
    named_values: dict[str, NamedValueConfig] = Field(default_factory=dict)
    users: dict[str, UserConfig] = Field(default_factory=dict)
    groups: dict[str, GroupConfig] = Field(default_factory=dict)
    subscription: SubscriptionConfig = Field(default_factory=SubscriptionConfig)
    admin_token: str | None = None
    tenant_access: TenantAccessConfig = Field(default_factory=TenantAccessConfig)
    proxy_timeout_seconds: float = 30.0
    proxy_max_attempts: int = 1
    proxy_retry_statuses: list[int] = Field(default_factory=lambda: [502, 503, 504])
    proxy_streaming: bool = True
    max_request_body_bytes: int = 1_048_576
    cache_enabled: bool = False
    cache_ttl_seconds: float = 5.0
    cache_max_entries: int = 1024
    trace_enabled: bool = False
    api_version_sets: dict[str, ApiVersionSetConfig] = Field(default_factory=dict)
    policies_xml: str | None = None
    policies_xml_documents: list[str] = Field(default_factory=list)
    backends: dict[str, BackendConfig] = Field(default_factory=dict)
    apis: dict[str, ApiConfig] = Field(default_factory=dict)
    routes: list[RouteConfig] = Field(default_factory=list)

    def materialize_routes(self) -> list[RouteConfig]:
        if not self.apis:
            return list(self.routes)

        out: list[RouteConfig] = []

        def _url_template_prefix(url_template: str) -> str:
            templ = (url_template or "").strip()
            if not templ:
                return ""
            if not templ.startswith("/"):
                templ = "/" + templ
            prefix = templ.split("{", 1)[0]
            return prefix.rstrip("/")

        for api in self.apis.values():
            api_base = ("/" + (api.path or "").strip("/")).rstrip("/")
            api_base = api_base or "/"
            api_policy_docs: list[str] = []
            if api.policies_xml:
                api_policy_docs.append(api.policies_xml)

            if not api.operations:
                out.append(
                    RouteConfig(
                        name=api.name,
                        path_prefix=api_base,
                        upstream_base_url=api.upstream_base_url,
                        upstream_path_prefix=api.upstream_path_prefix,
                        backend=api.backend,
                        products=list(api.products),
                        api_version_set=api.api_version_set,
                        api_version=api.api_version,
                        policies_xml_documents=api_policy_docs,
                    )
                )
                continue

            for op in api.operations.values():
                op_prefix = _url_template_prefix(op.url_template)
                full_prefix = api_base.rstrip("/")
                if op_prefix and op_prefix != "/":
                    full_prefix = full_prefix + op_prefix
                if full_prefix == "":
                    full_prefix = "/"

                policies = list(api_policy_docs)
                if op.policies_xml:
                    policies.append(op.policies_xml)

                upstream_base_url = op.upstream_base_url or api.upstream_base_url

                if op.upstream_path_prefix is not None:
                    upstream_path_prefix = op.upstream_path_prefix
                else:
                    api_upstream_prefix = api.upstream_path_prefix.rstrip("/")
                    upstream_path_prefix = api_upstream_prefix
                    if op_prefix and op_prefix != "/":
                        upstream_path_prefix = f"{api_upstream_prefix}{op_prefix}" if api_upstream_prefix else op_prefix
                op_products = op.products if op.products is not None else api.products
                backend = op.backend or api.backend

                out.append(
                    RouteConfig(
                        name=f"{api.name}:{op.name}",
                        path_prefix=full_prefix,
                        methods=[op.method],
                        upstream_base_url=upstream_base_url,
                        upstream_path_prefix=upstream_path_prefix,
                        backend=backend,
                        products=list(op_products or []),
                        api_version_set=op.api_version_set or api.api_version_set,
                        api_version=op.api_version or api.api_version,
                        authz=op.authz,
                        policies_xml_documents=policies,
                    )
                )

        return out


class OperationConfig(BaseModel):
    name: str
    method: str = "GET"
    url_template: str
    upstream_base_url: str | None = None
    upstream_path_prefix: str | None = None
    backend: str | None = None
    products: list[str] | None = None
    api_version_set: str | None = None
    api_version: str | None = None
    authz: RouteAuthzConfig | None = None
    policies_xml: str | None = None


class ApiConfig(BaseModel):
    name: str
    path: str
    upstream_base_url: str
    upstream_path_prefix: str = ""
    backend: str | None = None
    products: list[str] = Field(default_factory=list)
    api_version_set: str | None = None
    api_version: str | None = None
    policies_xml: str | None = None
    operations: dict[str, OperationConfig] = Field(default_factory=dict)


def _default_config_from_env() -> GatewayConfig:
    backend_base_url = os.getenv("BACKEND_BASE_URL", "http://api-fastapi-keycloak:8080")
    oidc_issuer = os.getenv("OIDC_ISSUER", "http://localhost:8300/realms/subnet-calculator")
    oidc_audience = os.getenv("OIDC_AUDIENCE", "api-app")
    oidc_jwks_uri = os.getenv(
        "OIDC_JWKS_URI", "http://keycloak:8080/realms/subnet-calculator/protocol/openid-connect/certs"
    )
    allowed_origins = [
        origin.strip() for origin in os.getenv("ALLOWED_ORIGINS", "http://localhost:3007").split(",") if origin.strip()
    ]
    allow_anonymous = os.getenv("ALLOW_ANONYMOUS", "false").lower() == "true"

    subscription_key = os.getenv("APIM_SUBSCRIPTION_KEY", "")
    keys: dict[str, SubscriptionIdentity] = {}
    if subscription_key:
        keys[subscription_key] = SubscriptionIdentity(id="sub-default", name="default")

    admin_token = os.getenv("APIM_ADMIN_TOKEN", "").strip() or None

    tenant_primary = os.getenv("APIM_TENANT_ACCESS_PRIMARY_KEY", "").strip() or None
    tenant_secondary = os.getenv("APIM_TENANT_ACCESS_SECONDARY_KEY", "").strip() or None
    tenant_enabled = bool(tenant_primary or tenant_secondary)

    return GatewayConfig(
        allowed_origins=allowed_origins or ["*"],
        allow_anonymous=allow_anonymous,
        oidc=OIDCConfig(issuer=oidc_issuer, audience=oidc_audience, jwks_uri=oidc_jwks_uri),
        products={"default": ProductConfig(name="Default")},
        subscription=SubscriptionConfig(required=bool(subscription_key), keys=keys),
        admin_token=admin_token,
        tenant_access=TenantAccessConfig(
            enabled=tenant_enabled,
            primary_key=tenant_primary,
            secondary_key=tenant_secondary,
        ),
        routes=[
            RouteConfig(
                name="default",
                path_prefix="/api",
                upstream_base_url=backend_base_url,
                upstream_path_prefix="/api",
                product="default",
            )
        ],
    )


def load_config() -> GatewayConfig:
    config_path = os.getenv("APIM_CONFIG_PATH", "").strip()
    if not config_path:
        return _default_config_from_env()
    with open(config_path, encoding="utf-8") as f:
        data = json.load(f)
    return GatewayConfig.model_validate(data)
