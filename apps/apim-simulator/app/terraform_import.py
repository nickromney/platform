from __future__ import annotations

import json
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from typing import Any

from app.config import (
    ApiConfig,
    ApiReleaseConfig,
    ApiRevisionConfig,
    ApiSchemaConfig,
    ApiVersioningScheme,
    ApiVersionSetConfig,
    BackendConfig,
    ClientCertificateMode,
    DiagnosticConfig,
    DiagnosticDataMaskingConfig,
    DiagnosticHttpMessageConfig,
    DiagnosticMaskingRuleConfig,
    GatewayConfig,
    GroupConfig,
    KeyVaultNamedValueConfig,
    LoggerApplicationInsightsConfig,
    LoggerConfig,
    LoggerEventHubConfig,
    NamedValueConfig,
    OperationConfig,
    OperationExampleConfig,
    OperationParameterConfig,
    OperationRepresentationConfig,
    OperationRequestMetadataConfig,
    OperationResponseMetadataConfig,
    ProductConfig,
    ServiceHostnameConfiguration,
    ServiceMetadataConfig,
    Subscription,
    SubscriptionKeyPair,
    TagConfig,
    UserConfig,
)
from app.openapi_import import parse_api_import
from app.urls import http_url


@dataclass(frozen=True)
class TFResource:
    address: str
    type: str
    name: str
    values: dict[str, Any]


@dataclass(frozen=True)
class ImportDiagnostic:
    status: str
    scope: str
    feature: str
    detail: str


@dataclass(frozen=True)
class ImportResult:
    config: GatewayConfig
    diagnostics: list[ImportDiagnostic] = field(default_factory=list)
    service_imported: bool = False


def _iter_module_resources(module: dict[str, Any]) -> Iterable[TFResource]:
    for res in module.get("resources") or []:
        if not isinstance(res, dict):
            continue
        address = str(res.get("address") or "")
        rtype = str(res.get("type") or "")
        name = str(res.get("name") or "")
        values = res.get("values")
        if isinstance(values, dict):
            yield TFResource(address=address, type=rtype, name=name, values=values)

    for child in module.get("child_modules") or []:
        if isinstance(child, dict):
            yield from _iter_module_resources(child)


def _iter_resources(tf: dict[str, Any]) -> list[TFResource]:
    values = tf.get("values")
    if not isinstance(values, dict):
        planned = tf.get("planned_values")
        values = planned if isinstance(planned, dict) else {}

    root = values.get("root_module")
    if not isinstance(root, dict):
        return []
    return list(_iter_module_resources(root))


def iter_tofu_resources(tf: dict[str, Any]) -> list[TFResource]:
    return _iter_resources(tf)


def _first_block(value: Any) -> dict[str, Any] | None:
    if isinstance(value, dict):
        return value
    if isinstance(value, list) and value and isinstance(value[0], dict):
        return value[0]
    return None


def _string_map(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    out: dict[str, str] = {}
    for key, item in value.items():
        if isinstance(item, list):
            out[str(key)] = ",".join(str(part) for part in item)
        elif item is not None:
            out[str(key)] = str(item)
    return out


def _resource_name_from_id(resource_id: str, id_to_name: dict[str, str]) -> str | None:
    if not resource_id:
        return None
    if resource_id in id_to_name:
        return id_to_name[resource_id]
    tail = resource_id.rstrip("/").split("/")[-1]
    return id_to_name.get(tail) or tail or None


def _arm_id_segment(resource_id: str, marker: str) -> str | None:
    if not resource_id:
        return None
    parts = resource_id.strip("/").split("/")
    if marker not in parts:
        return None
    idx = parts.index(marker)
    if idx + 1 >= len(parts):
        return None
    return parts[idx + 1] or None


def _api_name_and_revision_from_resource_id(resource_id: str) -> tuple[str | None, str | None]:
    tail = _arm_id_segment(resource_id, "apis")
    if not tail:
        return None, None
    if ";rev=" in tail:
        api_name, revision = tail.split(";rev=", 1)
        return api_name or None, revision or None
    return tail, None


def _api_import_block(values: dict[str, Any]) -> dict[str, Any] | None:
    return _first_block(values.get("import"))


def _subscription_key_parameter_names(values: dict[str, Any]) -> tuple[list[str] | None, list[str] | None]:
    block = _first_block(values.get("subscription_key_parameter_names"))
    if block is None:
        return None, None
    header = str(block.get("header") or "").strip() or None
    query = str(block.get("query") or "").strip() or None
    return ([header] if header else None, [query] if query else None)


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item) for item in value if str(item).strip()]


def _examples(value: Any) -> list[OperationExampleConfig]:
    if not isinstance(value, list):
        return []
    out: list[OperationExampleConfig] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        if not name:
            continue
        out.append(
            OperationExampleConfig(
                name=name,
                summary=str(item.get("summary")) if item.get("summary") else None,
                description=str(item.get("description")) if item.get("description") else None,
                value=item.get("value"),
                external_value=str(item.get("external_value")) if item.get("external_value") else None,
            )
        )
    return out


def _parameter_blocks(value: Any) -> list[OperationParameterConfig]:
    if not isinstance(value, list):
        return []
    out: list[OperationParameterConfig] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        param_type = str(item.get("type") or "").strip()
        if not name or not param_type:
            continue
        out.append(
            OperationParameterConfig(
                name=name,
                required=bool(item.get("required")),
                type=param_type,
                description=str(item.get("description")) if item.get("description") else None,
                default_value=str(item.get("default_value")) if item.get("default_value") is not None else None,
                values=_string_list(item.get("values")),
                examples=_examples(item.get("example")),
                schema_id=str(item.get("schema_id")) if item.get("schema_id") else None,
                type_name=str(item.get("type_name")) if item.get("type_name") else None,
            )
        )
    return out


def _representation_blocks(value: Any) -> list[OperationRepresentationConfig]:
    if not isinstance(value, list):
        return []
    out: list[OperationRepresentationConfig] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        content_type = str(item.get("content_type") or "").strip()
        if not content_type:
            continue
        out.append(
            OperationRepresentationConfig(
                content_type=content_type,
                form_parameters=_parameter_blocks(item.get("form_parameter")),
                examples=_examples(item.get("example")),
                schema_id=str(item.get("schema_id")) if item.get("schema_id") else None,
                type_name=str(item.get("type_name")) if item.get("type_name") else None,
            )
        )
    return out


def _request_metadata(value: Any) -> OperationRequestMetadataConfig | None:
    block = _first_block(value)
    if block is None:
        return None
    request = OperationRequestMetadataConfig(
        description=str(block.get("description")) if block.get("description") else None,
        headers=_parameter_blocks(block.get("header")),
        query_parameters=_parameter_blocks(block.get("query_parameter")),
        representations=_representation_blocks(block.get("representation")),
    )
    if request == OperationRequestMetadataConfig():
        return None
    return request


def _response_metadata(value: Any) -> list[OperationResponseMetadataConfig]:
    if not isinstance(value, list):
        return []
    out: list[OperationResponseMetadataConfig] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        status_code_raw = item.get("status_code")
        if status_code_raw is None:
            continue
        try:
            status_code = int(status_code_raw)
        except (TypeError, ValueError):
            continue
        out.append(
            OperationResponseMetadataConfig(
                status_code=status_code,
                description=str(item.get("description")) if item.get("description") else None,
                headers=_parameter_blocks(item.get("header")),
                representations=_representation_blocks(item.get("representation")),
            )
        )
    return out


def _api_schema(values: dict[str, Any]) -> ApiSchemaConfig:
    definitions = values.get("definitions")
    if not isinstance(definitions, dict):
        definitions = {}
    components = values.get("components")
    if not isinstance(components, dict):
        components = {}
    raw_value = values.get("value")
    value = str(raw_value) if raw_value is not None else None
    return ApiSchemaConfig(
        content_type=str(values.get("content_type") or "application/json"),
        value=value,
        definitions=definitions,
        components=components,
    )


def _diagnostic_masking_rules(value: Any) -> list[DiagnosticMaskingRuleConfig]:
    if not isinstance(value, list):
        return []
    out: list[DiagnosticMaskingRuleConfig] = []
    for item in value:
        if not isinstance(item, dict):
            continue
        mode = str(item.get("mode") or "").strip()
        masked_value = str(item.get("value") or "").strip()
        if not mode or not masked_value:
            continue
        out.append(DiagnosticMaskingRuleConfig(mode=mode, value=masked_value))
    return out


def _diagnostic_data_masking(value: Any) -> DiagnosticDataMaskingConfig | None:
    block = _first_block(value)
    if block is None:
        return None
    data_masking = DiagnosticDataMaskingConfig(
        query_params=_diagnostic_masking_rules(block.get("query_params")),
        headers=_diagnostic_masking_rules(block.get("headers")),
    )
    if data_masking == DiagnosticDataMaskingConfig():
        return None
    return data_masking


def _diagnostic_http_message(value: Any) -> DiagnosticHttpMessageConfig | None:
    block = _first_block(value)
    if block is None:
        return None
    raw_body_bytes = block.get("body_bytes")
    body_bytes: int | None = None
    if raw_body_bytes is not None:
        try:
            body_bytes = int(raw_body_bytes)
        except (TypeError, ValueError):
            body_bytes = None
    payload = DiagnosticHttpMessageConfig(
        body_bytes=body_bytes,
        headers_to_log=_string_list(block.get("headers_to_log")),
        data_masking=_diagnostic_data_masking(block.get("data_masking")),
    )
    if payload == DiagnosticHttpMessageConfig():
        return None
    return payload


def _ensure_tag(
    tags: dict[str, TagConfig],
    *,
    tag_name: str,
    display_name: str | None = None,
) -> bool:
    existing = tags.get(tag_name)
    if existing is not None:
        if display_name and existing.display_name == tag_name:
            existing.display_name = display_name
        return False
    tags[tag_name] = TagConfig(display_name=display_name or tag_name)
    return True


def _ensure_group(groups: dict[str, GroupConfig], *, group_name: str) -> bool:
    if group_name in groups:
        return False
    groups[group_name] = GroupConfig(id=group_name, name=group_name)
    return True


def _ensure_user(users: dict[str, UserConfig], *, user_id: str) -> bool:
    if user_id in users:
        return False
    users[user_id] = UserConfig(id=user_id, name=user_id)
    return True


AZAPI_PROVIDER_RESOURCE_TYPES = {"azapi_resource", "azapi_update_resource"}

AZAPI_APIM_CHILD_EQUIVALENTS = {
    "Microsoft.ApiManagement/service/apis": "azurerm_api_management_api",
    "Microsoft.ApiManagement/service/apis/operations": "azurerm_api_management_api_operation",
    "Microsoft.ApiManagement/service/apis/schemas": "azurerm_api_management_api_schema",
    "Microsoft.ApiManagement/service/apis/policies": "azurerm_api_management_api_policy",
    "Microsoft.ApiManagement/service/apis/operations/policies": "azurerm_api_management_api_operation_policy",
    "Microsoft.ApiManagement/service/products": "azurerm_api_management_product",
    "Microsoft.ApiManagement/service/subscriptions": "azurerm_api_management_subscription",
    "Microsoft.ApiManagement/service/backends": "azurerm_api_management_backend",
    "Microsoft.ApiManagement/service/namedValues": "azurerm_api_management_named_value",
    "Microsoft.ApiManagement/service/loggers": "azurerm_api_management_logger",
    "Microsoft.ApiManagement/service/diagnostics": "azurerm_api_management_diagnostic",
    "Microsoft.ApiManagement/service/apiVersionSets": "azurerm_api_management_api_version_set",
    "Microsoft.ApiManagement/service/policies": "azurerm_api_management_policy",
}


def arm_resource_type(resource: TFResource) -> str | None:
    if resource.type not in AZAPI_PROVIDER_RESOURCE_TYPES:
        return None
    raw = resource.values.get("type")
    if not isinstance(raw, str) or not raw.strip():
        return None
    return raw.split("@", 1)[0]


def azapi_body(values: dict[str, Any]) -> dict[str, Any]:
    raw = values.get("body")
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str) and raw.strip():
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        if isinstance(parsed, dict):
            return parsed
    return {}


def _coerce_bool(value: Any) -> bool | None:
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered in {"true", "enabled", "yes"}:
            return True
        if lowered in {"false", "disabled", "no"}:
            return False
    return None


def _coerce_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _service_scope(name: str) -> str:
    return f"service:{name}"


def _service_hostnames_from_azurerm(values: dict[str, Any]) -> list[ServiceHostnameConfiguration]:
    block = _first_block(values.get("hostname_configuration"))
    if block is None:
        return []

    out: list[ServiceHostnameConfiguration] = []
    type_map = {
        "management": "Management",
        "portal": "Portal",
        "developer_portal": "DeveloperPortal",
        "proxy": "Proxy",
        "scm": "Scm",
    }
    for tf_type, apim_type in type_map.items():
        for item in block.get(tf_type) or []:
            if not isinstance(item, dict):
                continue
            host_name = str(item.get("host_name") or "").strip()
            if not host_name:
                continue
            out.append(
                ServiceHostnameConfiguration(
                    type=apim_type,
                    host_name=host_name,
                    negotiate_client_certificate=bool(item.get("negotiate_client_certificate")),
                    default_ssl_binding=bool(item.get("default_ssl_binding")),
                )
            )
    return out


def _service_hostnames_from_azapi(body: dict[str, Any]) -> list[ServiceHostnameConfiguration]:
    properties = body.get("properties")
    if not isinstance(properties, dict):
        return []

    raw_hostnames = properties.get("hostnameConfigurations") or properties.get("hostname_configurations")
    if not isinstance(raw_hostnames, list):
        return []

    out: list[ServiceHostnameConfiguration] = []
    for item in raw_hostnames:
        if not isinstance(item, dict):
            continue
        host_name = str(item.get("hostName") or item.get("host_name") or "").strip()
        host_type = str(item.get("type") or "").strip()
        if not host_name or not host_type:
            continue
        out.append(
            ServiceHostnameConfiguration(
                type=host_type,
                host_name=host_name,
                negotiate_client_certificate=bool(
                    _coerce_bool(item.get("negotiateClientCertificate", item.get("negotiate_client_certificate")))
                ),
                default_ssl_binding=bool(_coerce_bool(item.get("defaultSslBinding", item.get("default_ssl_binding")))),
            )
        )
    return out


def _service_mode_from_flags(
    *, client_certificate_enabled: bool | None, hostnames: list[ServiceHostnameConfiguration]
) -> ClientCertificateMode | None:
    if client_certificate_enabled:
        return ClientCertificateMode.Required
    if any(item.negotiate_client_certificate for item in hostnames):
        return ClientCertificateMode.Optional
    return None


def _import_azurerm_service(
    values: dict[str, Any], fallback_name: str
) -> tuple[ServiceMetadataConfig, ClientCertificateMode | None]:
    name = str(values.get("name") or fallback_name or "apim-simulator")
    hostnames = _service_hostnames_from_azurerm(values)
    service = ServiceMetadataConfig(
        name=name,
        display_name=name,
        public_network_access_enabled=_coerce_bool(values.get("public_network_access_enabled")),
        virtual_network_type=(str(values.get("virtual_network_type")) if values.get("virtual_network_type") else None),
        hostname_configurations=hostnames,
    )
    mode = _service_mode_from_flags(
        client_certificate_enabled=_coerce_bool(values.get("client_certificate_enabled")),
        hostnames=hostnames,
    )
    return service, mode


def _import_azapi_service(
    values: dict[str, Any], fallback_name: str
) -> tuple[ServiceMetadataConfig, ClientCertificateMode | None, list[ImportDiagnostic]]:
    body = azapi_body(values)
    properties = body.get("properties") if isinstance(body.get("properties"), dict) else {}
    name = str(values.get("name") or fallback_name or "apim-simulator")
    hostnames = _service_hostnames_from_azapi(body)
    diagnostics: list[ImportDiagnostic] = []
    scope = _service_scope(name)

    public_network_access = properties.get("publicNetworkAccess", properties.get("public_network_access"))
    virtual_network_type = properties.get("virtualNetworkType", properties.get("virtual_network_type"))
    client_certificate_enabled = properties.get("enableClientCertificate", properties.get("enable_client_certificate"))

    if public_network_access is not None:
        diagnostics.append(
            ImportDiagnostic(
                status="adapted",
                scope=scope,
                feature="properties.publicNetworkAccess",
                detail="Imported into local service metadata only; Azure control-plane reachability is not enforced locally.",
            )
        )
    if virtual_network_type is not None:
        diagnostics.append(
            ImportDiagnostic(
                status="adapted",
                scope=scope,
                feature="properties.virtualNetworkType",
                detail="Imported into local service metadata only; Azure VNet placement is not enforced locally.",
            )
        )
    if hostnames:
        diagnostics.append(
            ImportDiagnostic(
                status="adapted",
                scope=scope,
                feature="properties.hostnameConfigurations",
                detail="Imported as descriptive host metadata; TLS termination and custom-domain ownership remain external.",
            )
        )
    if client_certificate_enabled is not None:
        diagnostics.append(
            ImportDiagnostic(
                status="adapted",
                scope=scope,
                feature="properties.enableClientCertificate",
                detail="Mapped onto the simulator's existing client-certificate mode.",
            )
        )

    allowed_top_level = {"properties"}
    allowed_properties = {
        "publicNetworkAccess",
        "public_network_access",
        "virtualNetworkType",
        "virtual_network_type",
        "hostnameConfigurations",
        "hostname_configurations",
        "enableClientCertificate",
        "enable_client_certificate",
    }
    for key in sorted(key for key in body if key not in allowed_top_level):
        diagnostics.append(
            ImportDiagnostic(
                status="unsupported",
                scope=scope,
                feature=key,
                detail="This AzAPI APIM service field is not imported into the simulator.",
            )
        )
    for key in sorted(key for key in properties if key not in allowed_properties):
        diagnostics.append(
            ImportDiagnostic(
                status="unsupported",
                scope=scope,
                feature=f"properties.{key}",
                detail="This AzAPI APIM service property is not imported into the simulator.",
            )
        )

    service = ServiceMetadataConfig(
        name=name,
        display_name=name,
        public_network_access_enabled=_coerce_bool(public_network_access),
        virtual_network_type=str(virtual_network_type) if virtual_network_type is not None else None,
        hostname_configurations=hostnames,
    )
    mode = _service_mode_from_flags(
        client_certificate_enabled=_coerce_bool(client_certificate_enabled),
        hostnames=hostnames,
    )
    return service, mode, diagnostics


def import_from_tofu_show_json(
    tf: dict[str, Any],
    *,
    fetcher: Callable[[str], str] | None = None,
) -> ImportResult:
    resources = _iter_resources(tf)
    diagnostics: list[ImportDiagnostic] = []

    service = ServiceMetadataConfig()
    service_imported = False
    client_certificate_mode: ClientCertificateMode | None = None
    products: dict[str, ProductConfig] = {}
    subscriptions: dict[str, Subscription] = {}
    named_values: dict[str, NamedValueConfig] = {}
    loggers: dict[str, LoggerConfig] = {}
    diagnostic_resources: dict[str, DiagnosticConfig] = {}
    users: dict[str, UserConfig] = {}
    groups: dict[str, GroupConfig] = {}
    api_version_sets: dict[str, ApiVersionSetConfig] = {}
    backends: dict[str, BackendConfig] = {}
    apis: dict[str, ApiConfig] = {}
    tags: dict[str, TagConfig] = {}
    id_to_name: dict[str, str] = {}

    for res in resources:
        resource_id = res.values.get("id")
        if isinstance(resource_id, str) and resource_id:
            id_to_name[resource_id] = res.name
        id_to_name[res.name] = res.name

    # ---- First pass: base resources ----
    for res in resources:
        if res.type == "azurerm_api_management":
            service, mode = _import_azurerm_service(res.values, res.name)
            service_imported = True
            if mode is not None:
                client_certificate_mode = mode

        arm_type = arm_resource_type(res)
        if arm_type == "Microsoft.ApiManagement/service":
            service, mode, service_diagnostics = _import_azapi_service(res.values, res.name)
            service_imported = True
            diagnostics.extend(service_diagnostics)
            if mode is not None:
                client_certificate_mode = mode
        elif arm_type in AZAPI_APIM_CHILD_EQUIVALENTS:
            diagnostics.append(
                ImportDiagnostic(
                    status="unsupported",
                    scope=arm_type,
                    feature="azapi_import",
                    detail=(
                        "Detected APIM child resource via AzAPI, but the simulator only imports the "
                        f"AzureRM equivalent `{AZAPI_APIM_CHILD_EQUIVALENTS[arm_type]}` today."
                    ),
                )
            )

        if res.type == "azurerm_api_management_product":
            product_id = str(res.values.get("product_id") or res.name)
            display_name = str(res.values.get("display_name") or product_id)
            subscription_required = res.values.get("subscription_required")
            require_subscription = bool(subscription_required) if subscription_required is not None else True
            products[product_id] = ProductConfig(name=display_name, require_subscription=require_subscription)

        if res.type == "azurerm_api_management_group":
            group_name = str(res.values.get("name") or res.name).strip()
            if not group_name:
                continue
            groups[group_name] = GroupConfig(
                id=group_name,
                name=str(res.values.get("display_name") or group_name),
                description=str(res.values.get("description")) if res.values.get("description") else None,
                external_id=str(res.values.get("external_id")) if res.values.get("external_id") else None,
                type=str(res.values.get("type") or "custom"),
            )
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"group:{group_name}",
                    feature="group",
                    detail="Imported API Management group.",
                )
            )

        if res.type == "azurerm_api_management_user":
            user_id = str(res.values.get("user_id") or res.name).strip()
            if not user_id:
                continue
            first_name = str(res.values.get("first_name") or "").strip() or None
            last_name = str(res.values.get("last_name") or "").strip() or None
            full_name = " ".join(part for part in [first_name, last_name] if part).strip() or user_id
            users[user_id] = UserConfig(
                id=user_id,
                email=str(res.values.get("email")) if res.values.get("email") else None,
                name=full_name,
                first_name=first_name,
                last_name=last_name,
                note=str(res.values.get("note")) if res.values.get("note") else None,
                state=str(res.values.get("state")) if res.values.get("state") else None,
                confirmation=str(res.values.get("confirmation")) if res.values.get("confirmation") else None,
            )
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"user:{user_id}",
                    feature="user",
                    detail="Imported API Management user.",
                )
            )
            if res.values.get("password") is not None:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"user:{user_id}",
                        feature="password",
                        detail="User passwords are not stored or enforced by the simulator.",
                    )
                )

        if res.type == "azurerm_api_management_tag":
            tag_name = str(res.values.get("name") or res.name).strip()
            if not tag_name:
                continue
            _ensure_tag(
                tags,
                tag_name=tag_name,
                display_name=str(res.values.get("display_name") or tag_name),
            )
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"tag:{tag_name}",
                    feature="tag",
                    detail="Imported API Management tag.",
                )
            )

        if res.type == "azurerm_api_management_subscription":
            sub_id = str(res.values.get("subscription_id") or res.values.get("name") or res.name)
            display_name = str(res.values.get("display_name") or res.values.get("name") or sub_id)
            primary = str(res.values.get("primary_key") or "")
            secondary = str(res.values.get("secondary_key") or "")
            subscriptions[sub_id] = Subscription(
                id=sub_id,
                name=display_name,
                keys=SubscriptionKeyPair(primary=primary, secondary=secondary),
            )

        if res.type == "azurerm_api_management_named_value":
            name = str(res.values.get("display_name") or res.values.get("name") or res.name)
            secret = bool(res.values.get("secret"))
            key_vault_block = _first_block(res.values.get("value_from_key_vault"))
            value_from_key_vault = None
            if key_vault_block is not None and key_vault_block.get("secret_id"):
                value_from_key_vault = KeyVaultNamedValueConfig(
                    secret_id=str(key_vault_block["secret_id"]),
                    identity_client_id=(
                        str(key_vault_block.get("identity_client_id"))
                        if key_vault_block.get("identity_client_id")
                        else None
                    ),
                )
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"named-value:{name}",
                        feature="value_from_key_vault",
                        detail="Key Vault-backed named values require APIM_NAMED_VALUE_<NAME> env overrides locally.",
                    )
                )
            value = res.values.get("value")
            named_values[name] = NamedValueConfig(
                value=str(value) if value is not None else None,
                secret=secret,
                value_from_key_vault=value_from_key_vault,
            )

        if res.type == "azurerm_api_management_logger":
            logger_id = str(res.values.get("name") or res.name).strip()
            if not logger_id:
                continue
            app_insights_block = _first_block(res.values.get("application_insights"))
            eventhub_block = _first_block(res.values.get("eventhub"))
            logger_type = "application_insights" if app_insights_block else "eventhub" if eventhub_block else "custom"
            loggers[logger_id] = LoggerConfig(
                logger_type=logger_type,
                description=str(res.values.get("description")) if res.values.get("description") else None,
                buffered=bool(res.values.get("buffered", True)),
                resource_id=str(res.values.get("resource_id")) if res.values.get("resource_id") else None,
                application_insights=(
                    LoggerApplicationInsightsConfig(
                        connection_string=(
                            str(app_insights_block.get("connection_string"))
                            if app_insights_block.get("connection_string")
                            else None
                        ),
                        instrumentation_key=(
                            str(app_insights_block.get("instrumentation_key"))
                            if app_insights_block.get("instrumentation_key")
                            else None
                        ),
                    )
                    if app_insights_block is not None
                    else None
                ),
                eventhub=(
                    LoggerEventHubConfig(
                        name=str(eventhub_block.get("name") or logger_id),
                        connection_string=(
                            str(eventhub_block.get("connection_string"))
                            if eventhub_block.get("connection_string")
                            else None
                        ),
                        endpoint_uri=str(eventhub_block.get("endpoint_uri"))
                        if eventhub_block.get("endpoint_uri")
                        else None,
                        user_assigned_identity_client_id=(
                            str(eventhub_block.get("user_assigned_identity_client_id"))
                            if eventhub_block.get("user_assigned_identity_client_id")
                            else None
                        ),
                    )
                    if eventhub_block is not None
                    else None
                ),
            )
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"logger:{logger_id}",
                    feature="logger",
                    detail="Imported API Management logger for read-only local inspection.",
                )
            )
            if app_insights_block is not None:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"logger:{logger_id}",
                        feature="application_insights",
                        detail=(
                            "Logger Application Insights settings are descriptive only; the simulator continues to "
                            "emit telemetry through its local OTEL/logging pipeline."
                        ),
                    )
                )
            if eventhub_block is not None:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"logger:{logger_id}",
                        feature="eventhub",
                        detail=(
                            "Logger Event Hub settings are descriptive only; the simulator continues to emit "
                            "telemetry through its local OTEL/logging pipeline."
                        ),
                    )
                )

        if res.type == "azurerm_api_management_diagnostic":
            diagnostic_id = str(res.values.get("identifier") or res.name).strip()
            if not diagnostic_id:
                continue
            logger_reference = str(res.values.get("api_management_logger_id") or "").strip()
            logger_id = _resource_name_from_id(logger_reference, id_to_name) if logger_reference else None
            diagnostic_resources[diagnostic_id] = DiagnosticConfig(
                identifier=diagnostic_id,
                logger_id=logger_id,
                always_log_errors=_coerce_bool(res.values.get("always_log_errors")),
                backend_request=_diagnostic_http_message(res.values.get("backend_request")),
                backend_response=_diagnostic_http_message(res.values.get("backend_response")),
                frontend_request=_diagnostic_http_message(res.values.get("frontend_request")),
                frontend_response=_diagnostic_http_message(res.values.get("frontend_response")),
                http_correlation_protocol=(
                    str(res.values.get("http_correlation_protocol"))
                    if res.values.get("http_correlation_protocol")
                    else None
                ),
                log_client_ip=_coerce_bool(res.values.get("log_client_ip")),
                sampling_percentage=_coerce_float(res.values.get("sampling_percentage")),
                verbosity=str(res.values.get("verbosity")) if res.values.get("verbosity") else None,
                operation_name_format=(
                    str(res.values.get("operation_name_format")) if res.values.get("operation_name_format") else None
                ),
            )
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"diagnostic:{diagnostic_id}",
                    feature="diagnostic",
                    detail="Imported API Management diagnostic for read-only local inspection.",
                )
            )
            diagnostics.append(
                ImportDiagnostic(
                    status="adapted",
                    scope=f"diagnostic:{diagnostic_id}",
                    feature="runtime_settings",
                    detail=(
                        "Diagnostic sampling, header/body capture, and logger routing are descriptive only; "
                        "runtime observability continues to use local traces and OTEL."
                    ),
                )
            )

        if res.type == "azurerm_api_management_api_version_set":
            scheme_raw = str(res.values.get("versioning_scheme") or "Segment")
            try:
                scheme = ApiVersioningScheme(scheme_raw)
            except ValueError:
                diagnostics.append(
                    ImportDiagnostic(
                        status="unsupported",
                        scope=f"api-version-set:{res.name}",
                        feature="versioning_scheme",
                        detail=f"Unsupported versioning scheme: {scheme_raw}",
                    )
                )
                continue
            api_version_sets[res.name] = ApiVersionSetConfig(
                display_name=str(res.values.get("display_name") or res.name),
                description=str(res.values.get("description")) if res.values.get("description") else None,
                versioning_scheme=scheme,
                version_header_name=(
                    str(res.values.get("version_header_name")) if res.values.get("version_header_name") else None
                ),
                version_query_name=(
                    str(res.values.get("version_query_name")) if res.values.get("version_query_name") else None
                ),
            )

        if res.type == "azurerm_api_management_backend":
            credentials = _first_block(res.values.get("credentials")) or {}
            authorization = _first_block(credentials.get("authorization")) or {}
            backends[res.name] = BackendConfig(
                url=str(res.values.get("url") or http_url("upstream")),
                description=str(res.values.get("description")) if res.values.get("description") else None,
                authorization_scheme=(str(authorization.get("scheme")) if authorization.get("scheme") else None),
                authorization_parameter=(
                    str(authorization.get("parameter")) if authorization.get("parameter") else None
                ),
                header_credentials=_string_map(credentials.get("header")),
                query_credentials=_string_map(credentials.get("query")),
                client_certificate_thumbprints=[
                    str(item) for item in (credentials.get("certificate") or []) if str(item).strip()
                ],
            )

        if res.type == "azurerm_api_management_api":
            api_name = str(res.values.get("name") or res.name)
            revision = str(res.values.get("revision") or "1")
            path = str(res.values.get("path") or api_name)
            upstream = str(res.values.get("service_url") or http_url("upstream"))
            subscription_header_names, subscription_query_param_names = _subscription_key_parameter_names(res.values)
            version_set_id = str(res.values.get("version_set_id") or "")
            version_set_name = _resource_name_from_id(version_set_id, id_to_name) if version_set_id else None
            source_api_id = str(res.values.get("source_api_id")) if res.values.get("source_api_id") else None
            revision_is_current = _coerce_bool(res.values.get("is_current"))
            revision_is_online = _coerce_bool(res.values.get("is_online"))

            revision_metadata = ApiRevisionConfig(
                revision=revision,
                description=str(res.values.get("revision_description"))
                if res.values.get("revision_description")
                else None,
                is_current=revision_is_current,
                is_online=revision_is_online,
                source_api_id=source_api_id,
            )

            candidate = ApiConfig(
                name=api_name,
                path=path,
                upstream_base_url=upstream,
                api_version_set=version_set_name,
                api_version=(str(res.values.get("version")) if res.values.get("version") else None),
                revision=revision,
                revision_description=revision_metadata.description,
                version_description=(
                    str(res.values.get("version_description")) if res.values.get("version_description") else None
                ),
                source_api_id=source_api_id,
                is_current=revision_is_current,
                is_online=revision_is_online,
                subscription_header_names=subscription_header_names,
                subscription_query_param_names=subscription_query_param_names,
                revisions={revision: revision_metadata},
            )

            import_block = _api_import_block(res.values)
            if import_block is not None:
                content_format = str(import_block.get("content_format") or "")
                content_value = str(import_block.get("content_value") or "")
                try:
                    imported = parse_api_import(
                        content_format=content_format,
                        content_value=content_value,
                        fetcher=fetcher,
                    )
                except ValueError as exc:
                    diagnostics.append(
                        ImportDiagnostic(
                            status="unsupported",
                            scope=f"api:{api_name}",
                            feature="api_import",
                            detail=str(exc),
                        )
                    )
                except Exception as exc:
                    diagnostics.append(
                        ImportDiagnostic(
                            status="unsupported",
                            scope=f"api:{api_name}",
                            feature="api_import",
                            detail=f"Failed to load API import document: {exc}",
                        )
                    )
                else:
                    if imported.upstream_base_url and not res.values.get("service_url"):
                        candidate.upstream_base_url = imported.upstream_base_url
                    for operation in imported.operations:
                        candidate.operations[operation.name] = OperationConfig(
                            name=operation.name,
                            method=operation.method,
                            url_template=operation.url_template,
                        )
                    diagnostics.append(
                        ImportDiagnostic(
                            status="supported",
                            scope=f"api:{api_name}",
                            feature="api_import",
                            detail=f"Imported {len(imported.operations)} operations from {imported.format}.",
                        )
                    )
                    for item in imported.diagnostics:
                        diagnostics.append(
                            ImportDiagnostic(
                                status="adapted",
                                scope=f"api:{api_name}",
                                feature="api_import",
                                detail=item,
                            )
                        )

            existing = apis.get(api_name)
            if existing is None:
                apis[api_name] = candidate
            else:
                existing.revisions[revision] = revision_metadata
                should_replace_active = bool(revision_is_current) and not bool(existing.is_current)
                if should_replace_active:
                    candidate.tags = existing.tags
                    if not candidate.operations:
                        candidate.operations = existing.operations
                    candidate.schemas = existing.schemas
                    candidate.releases = existing.releases
                    candidate.revisions = dict(existing.revisions)
                    apis[api_name] = candidate
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"api:{api_name}",
                        feature="revisions",
                        detail=(
                            "Multiple API revisions are collapsed into one active local API while revision metadata is preserved."
                        ),
                    )
                )

    # ---- Second pass: children, associations, and policies ----
    for res in resources:
        if res.type == "azurerm_api_management_api_schema":
            api_name = str(res.values.get("api_name") or "")
            if not api_name or api_name not in apis:
                continue
            schema_id = str(res.values.get("schema_id") or res.name)
            apis[api_name].schemas[schema_id] = _api_schema(res.values)

        if res.type == "azurerm_api_management_api_operation":
            api_name = str(res.values.get("api_name") or "")
            if not api_name or api_name not in apis:
                continue
            op_id = str(res.values.get("operation_id") or res.name)
            method = str(res.values.get("method") or "GET")
            url_template = str(res.values.get("url_template") or "/")
            apis[api_name].operations[op_id] = OperationConfig(
                name=op_id,
                method=method,
                url_template=url_template,
                description=str(res.values.get("description")) if res.values.get("description") else None,
                template_parameters=_parameter_blocks(res.values.get("template_parameter")),
                request=_request_metadata(res.values.get("request")),
                responses=_response_metadata(res.values.get("response")),
            )

        if res.type == "azurerm_api_management_product_api":
            product_id = str(res.values.get("product_id") or "")
            api_name = str(res.values.get("api_name") or "")
            if product_id and api_name and api_name in apis and product_id not in apis[api_name].products:
                apis[api_name].products.append(product_id)

        if res.type == "azurerm_api_management_product_group":
            product_id = _resource_name_from_id(str(res.values.get("product_id") or ""), id_to_name)
            group_name = str(res.values.get("group_name") or "").strip()
            if not product_id or product_id not in products or not group_name:
                continue
            created_placeholder = _ensure_group(groups, group_name=group_name)
            if group_name not in products[product_id].groups:
                products[product_id].groups.append(group_name)
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"product:{product_id}",
                    feature=f"group:{group_name}",
                    detail="Imported product-group link.",
                )
            )
            if created_placeholder:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"group:{group_name}",
                        feature="placeholder_group",
                        detail="Created a local placeholder group because the product-group link had no separate group definition.",
                    )
                )

        if res.type == "azurerm_api_management_group_user":
            group_name = str(res.values.get("group_name") or "").strip()
            user_id = (
                _resource_name_from_id(str(res.values.get("user_id") or ""), id_to_name)
                or str(res.values.get("user_id") or "").strip()
            )
            if not group_name or not user_id:
                continue
            created_group_placeholder = _ensure_group(groups, group_name=group_name)
            created_user_placeholder = _ensure_user(users, user_id=user_id)
            if user_id not in groups[group_name].users:
                groups[group_name].users.append(user_id)
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"group:{group_name}",
                    feature=f"user:{user_id}",
                    detail="Imported group-user link.",
                )
            )
            if created_group_placeholder:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"group:{group_name}",
                        feature="placeholder_group",
                        detail="Created a local placeholder group because the group-user link had no separate group definition.",
                    )
                )
            if created_user_placeholder:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"user:{user_id}",
                        feature="placeholder_user",
                        detail="Created a local placeholder user because the group-user link had no separate user definition.",
                    )
                )

        if res.type == "azurerm_api_management_api_tag":
            api_name = _resource_name_from_id(str(res.values.get("api_id") or ""), id_to_name)
            tag_name = str(res.values.get("name") or "").strip()
            if not api_name or api_name not in apis or not tag_name:
                continue
            created_placeholder = _ensure_tag(tags, tag_name=tag_name)
            if tag_name not in apis[api_name].tags:
                apis[api_name].tags.append(tag_name)
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"api:{api_name}",
                    feature=f"tag:{tag_name}",
                    detail="Imported API tag link.",
                )
            )
            if created_placeholder:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"tag:{tag_name}",
                        feature="placeholder_tag",
                        detail="Created a local tag placeholder because the API tag link had no separate tag definition.",
                    )
                )

        if res.type == "azurerm_api_management_product_tag":
            product_id = _resource_name_from_id(str(res.values.get("api_management_product_id") or ""), id_to_name)
            tag_name = str(res.values.get("name") or "").strip()
            if not product_id or product_id not in products or not tag_name:
                continue
            created_placeholder = _ensure_tag(tags, tag_name=tag_name)
            if tag_name not in products[product_id].tags:
                products[product_id].tags.append(tag_name)
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"product:{product_id}",
                    feature=f"tag:{tag_name}",
                    detail="Imported product tag link.",
                )
            )
            if created_placeholder:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"tag:{tag_name}",
                        feature="placeholder_tag",
                        detail=(
                            "Created a local tag placeholder because the product tag link had no separate tag definition."
                        ),
                    )
                )

        if res.type == "azurerm_api_management_api_operation_tag":
            operation_id = str(res.values.get("api_operation_id") or "")
            api_name = _arm_id_segment(operation_id, "apis")
            op_name = _arm_id_segment(operation_id, "operations")
            tag_name = str(res.values.get("name") or "").strip()
            display_name = str(res.values.get("display_name") or tag_name).strip() or tag_name
            if (
                not api_name
                or api_name not in apis
                or not op_name
                or op_name not in apis[api_name].operations
                or not tag_name
            ):
                continue
            created_placeholder = _ensure_tag(tags, tag_name=tag_name, display_name=display_name)
            if tag_name not in apis[api_name].operations[op_name].tags:
                apis[api_name].operations[op_name].tags.append(tag_name)
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"operation:{api_name}:{op_name}",
                    feature=f"tag:{tag_name}",
                    detail="Imported operation tag link.",
                )
            )
            if created_placeholder:
                diagnostics.append(
                    ImportDiagnostic(
                        status="adapted",
                        scope=f"tag:{tag_name}",
                        feature="placeholder_tag",
                        detail="Created a local tag definition from the operation tag resource.",
                    )
                )

        if res.type == "azurerm_api_management_api_release":
            api_name, revision = _api_name_and_revision_from_resource_id(str(res.values.get("api_id") or ""))
            if not api_name or api_name not in apis:
                continue
            release_name = str(res.values.get("name") or res.name)
            apis[api_name].releases[release_name] = ApiReleaseConfig(
                name=release_name,
                api_id=str(res.values.get("api_id")) if res.values.get("api_id") else None,
                notes=str(res.values.get("notes")) if res.values.get("notes") else None,
                revision=revision,
            )
            diagnostics.append(
                ImportDiagnostic(
                    status="supported",
                    scope=f"api:{api_name}",
                    feature=f"release:{release_name}",
                    detail="Imported API release metadata.",
                )
            )

        if res.type == "azurerm_api_management_subscription":
            sub_id = str(res.values.get("subscription_id") or res.values.get("name") or res.name)
            if sub_id not in subscriptions:
                continue
            product_id = res.values.get("product_id")
            if isinstance(product_id, str) and product_id and product_id not in subscriptions[sub_id].products:
                subscriptions[sub_id].products.append(product_id)

        if res.type == "azurerm_api_management_api_policy":
            api_name = str(res.values.get("api_name") or "")
            xml = res.values.get("xml_content")
            if api_name in apis and isinstance(xml, str) and xml:
                apis[api_name].policies_xml = xml

        if res.type == "azurerm_api_management_api_operation_policy":
            api_name = str(res.values.get("api_name") or "")
            op_id = str(res.values.get("operation_id") or "")
            xml = res.values.get("xml_content")
            if not (api_name and op_id and isinstance(xml, str) and xml):
                continue
            api = apis.get(api_name)
            if api is None:
                continue
            op = api.operations.get(op_id)
            if op is None:
                continue
            op.policies_xml = xml

    gateway_policy: str | None = None
    for res in resources:
        if res.type == "azurerm_api_management_policy":
            xml = res.values.get("xml_content")
            if isinstance(xml, str) and xml:
                gateway_policy = xml
            continue
        if res.type.endswith("_policy") and res.type not in {
            "azurerm_api_management_api_policy",
            "azurerm_api_management_api_operation_policy",
        }:
            diagnostics.append(
                ImportDiagnostic(
                    status="unsupported",
                    scope=res.type,
                    feature="policy_scope",
                    detail="This policy scope is not imported into the simulator yet.",
                )
            )

    for diagnostic_id, diagnostic in diagnostic_resources.items():
        if diagnostic.logger_id and diagnostic.logger_id not in loggers:
            diagnostics.append(
                ImportDiagnostic(
                    status="adapted",
                    scope=f"diagnostic:{diagnostic_id}",
                    feature="logger_reference",
                    detail="Referenced logger was not imported; keeping the resolved logger id for inspection only.",
                )
            )

    header_names: list[str] = []
    query_param_names: list[str] = []
    for api in apis.values():
        if api.subscription_header_names:
            for name in api.subscription_header_names:
                if name not in header_names:
                    header_names.append(name)
        if api.subscription_query_param_names:
            for name in api.subscription_query_param_names:
                if name not in query_param_names:
                    query_param_names.append(name)

    subscription_payload: dict[str, Any] = {
        "required": True,
        "subscriptions": subscriptions,
    }
    if header_names:
        subscription_payload["header_names"] = header_names
    if query_param_names:
        subscription_payload["query_param_names"] = query_param_names

    cfg = GatewayConfig(
        allow_anonymous=True,
        service=service,
        products=products,
        named_values=named_values,
        loggers=loggers,
        diagnostics=diagnostic_resources,
        users=users,
        groups=groups,
        api_version_sets=api_version_sets,
        backends=backends,
        tags=tags,
        subscription=subscription_payload,
        apis=apis,
        policies_xml=gateway_policy,
    )
    if client_certificate_mode is not None:
        cfg.client_certificate.mode = client_certificate_mode
    if not header_names:
        cfg.subscription.header_names = ["Ocp-Apim-Subscription-Key", "X-Ocp-Apim-Subscription-Key"]
    if not query_param_names:
        cfg.subscription.query_param_names = ["subscription-key"]
    cfg.routes = cfg.materialize_routes()
    return ImportResult(config=cfg, diagnostics=diagnostics, service_imported=service_imported)


def config_from_tofu_show_json(
    tf: dict[str, Any],
    *,
    fetcher: Callable[[str], str] | None = None,
) -> GatewayConfig:
    return import_from_tofu_show_json(tf, fetcher=fetcher).config
