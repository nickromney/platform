from __future__ import annotations

from dataclasses import asdict
from typing import Any
from xml.etree import ElementTree

from app.terraform_import import (
    ImportDiagnostic,
    arm_resource_type,
    azapi_body,
    import_from_tofu_show_json,
    iter_tofu_resources,
)

SUPPORTED_POLICY_TAGS = {
    "policies",
    "inbound",
    "backend",
    "outbound",
    "on-error",
    "base",
    "set-header",
    "set-status",
    "value",
    "body",
    "rewrite-uri",
    "return-response",
    "choose",
    "when",
    "otherwise",
    "check-header",
    "ip-filter",
    "address",
    "cidr",
    "address-range",
    "cors",
    "rate-limit",
    "rate-limit-by-key",
    "quota",
    "quota-by-key",
    "cache-lookup",
    "cache-store",
    "cache-lookup-value",
    "cache-store-value",
    "cache-remove-value",
    "vary-by-header",
    "vary-by-query-parameter",
    "set-variable",
    "set-query-parameter",
    "set-body",
    "mock-response",
    "include-fragment",
    "validate-jwt",
    "openid-config",
    "audiences",
    "audience",
    "issuers",
    "issuer",
    "required-claims",
    "claim",
    "set-backend-service",
    "send-request",
    "set-url",
    "set-method",
    "authentication-certificate",
    "authentication-managed-identity",
}

ADAPTED_POLICY_TAGS = {
    "include-fragment": "Fragments are resolved from local config instead of APIM fragment resources.",
}

UNSUPPORTED_POLICY_TAGS = {
    "issuer-signing-keys": "Inline signing keys are not supported; use openid-config locally.",
    "decryption-keys": "JWT decryption keys are out of scope.",
    "proxy": "send-request proxy configuration is out of scope.",
}

AZAPI_POLICY_ARM_TYPES = {
    "Microsoft.ApiManagement/service/policies",
    "Microsoft.ApiManagement/service/apis/policies",
    "Microsoft.ApiManagement/service/apis/operations/policies",
}


def _policy_scope(res_type: str, values: dict[str, Any]) -> str:
    if res_type == "azurerm_api_management_policy":
        return "gateway"
    if res_type == "azurerm_api_management_api_policy":
        return f"api:{values.get('api_name') or 'unknown'}"
    if res_type == "azurerm_api_management_api_operation_policy":
        api_name = values.get("api_name") or "unknown"
        operation_id = values.get("operation_id") or "unknown"
        return f"operation:{api_name}:{operation_id}"
    return res_type


def _scope_from_parent_id(parent_id: str, *, marker: str) -> str:
    parts = parent_id.strip("/").split("/")
    if marker not in parts:
        return "unknown"
    idx = parts.index(marker)
    if idx + 1 >= len(parts):
        return "unknown"
    return parts[idx + 1]


def _azapi_policy_scope(values: dict[str, Any], arm_type: str) -> str:
    if arm_type == "Microsoft.ApiManagement/service/policies":
        return "gateway"

    parent_id = str(values.get("parent_id") or values.get("id") or "")
    if arm_type == "Microsoft.ApiManagement/service/apis/policies":
        return f"api:{_scope_from_parent_id(parent_id, marker='apis')}"
    if arm_type == "Microsoft.ApiManagement/service/apis/operations/policies":
        api_name = _scope_from_parent_id(parent_id, marker="apis")
        operation_id = _scope_from_parent_id(parent_id, marker="operations")
        return f"operation:{api_name}:{operation_id}"
    return arm_type


def _azapi_policy_xml(values: dict[str, Any]) -> str | None:
    body = azapi_body(values)
    properties = body.get("properties")
    if not isinstance(properties, dict):
        return None
    value = properties.get("value")
    if not isinstance(value, str) or not value.strip():
        return None
    return value


def _analyze_policy_tag(tag: str, scope: str, diagnostics: list[ImportDiagnostic]) -> None:
    if tag in ADAPTED_POLICY_TAGS:
        diagnostics.append(
            ImportDiagnostic(status="adapted", scope=scope, feature=tag, detail=ADAPTED_POLICY_TAGS[tag])
        )
        return
    if tag in UNSUPPORTED_POLICY_TAGS:
        diagnostics.append(
            ImportDiagnostic(status="unsupported", scope=scope, feature=tag, detail=UNSUPPORTED_POLICY_TAGS[tag])
        )
        return
    if tag in SUPPORTED_POLICY_TAGS:
        diagnostics.append(ImportDiagnostic(status="supported", scope=scope, feature=tag, detail="Supported."))
        return
    diagnostics.append(
        ImportDiagnostic(status="unsupported", scope=scope, feature=tag, detail="Policy element is not implemented.")
    )


def _analyze_policy_attributes(element: ElementTree.Element, scope: str, diagnostics: list[ImportDiagnostic]) -> None:
    if element.tag == "set-backend-service":
        unsupported_attrs = [key for key in element.attrib if key.startswith("sf-")]
        for attr in unsupported_attrs:
            diagnostics.append(
                ImportDiagnostic(
                    status="unsupported",
                    scope=scope,
                    feature=f"set-backend-service.{attr}",
                    detail="Service Fabric backend routing is out of scope.",
                )
            )
    if element.tag in {"cache-lookup", "cache-lookup-value", "cache-store-value", "cache-remove-value"}:
        caching_type = str(element.attrib.get("caching-type") or "prefer-external").strip().lower()
        if caching_type == "prefer-external":
            diagnostics.append(
                ImportDiagnostic(
                    status="adapted",
                    scope=scope,
                    feature=f"{element.tag}.caching-type",
                    detail="prefer-external is adapted to the simulator's local internal cache.",
                )
            )
        elif caching_type == "external":
            diagnostics.append(
                ImportDiagnostic(
                    status="unsupported",
                    scope=scope,
                    feature=f"{element.tag}.caching-type",
                    detail="External cache backends are out of scope.",
                )
            )
    if element.tag == "quota-by-key" and "bandwidth" in element.attrib:
        diagnostics.append(
            ImportDiagnostic(
                status="unsupported",
                scope=scope,
                feature="quota-by-key.bandwidth",
                detail="Bandwidth quota enforcement is not implemented.",
            )
        )


def _analyze_policy_xml(xml: str, scope: str) -> list[ImportDiagnostic]:
    try:
        root = ElementTree.fromstring(xml)
    except ElementTree.ParseError as exc:
        return [ImportDiagnostic(status="unsupported", scope=scope, feature="policy-xml", detail=str(exc))]

    diagnostics: list[ImportDiagnostic] = []
    for element in root.iter():
        _analyze_policy_tag(element.tag, scope, diagnostics)
        _analyze_policy_attributes(element, scope, diagnostics)
    return diagnostics


def build_compat_report(tf: dict[str, Any]) -> dict[str, Any]:
    result = import_from_tofu_show_json(tf)
    diagnostics = list(result.diagnostics)

    for resource in iter_tofu_resources(tf):
        if resource.type.endswith("_policy") or resource.type == "azurerm_api_management_policy":
            xml = resource.values.get("xml_content")
            if isinstance(xml, str) and xml:
                diagnostics.extend(_analyze_policy_xml(xml, _policy_scope(resource.type, resource.values)))
            continue

        arm_type = arm_resource_type(resource)
        if arm_type not in AZAPI_POLICY_ARM_TYPES:
            continue
        xml = _azapi_policy_xml(resource.values)
        if xml is None:
            diagnostics.append(
                ImportDiagnostic(
                    status="unsupported",
                    scope=_azapi_policy_scope(resource.values, arm_type),
                    feature="policy-xml",
                    detail="AzAPI policy resources are only analyzed when properties.value contains inline XML.",
                )
            )
            continue
        diagnostics.extend(_analyze_policy_xml(xml, _azapi_policy_scope(resource.values, arm_type)))

    supported = [asdict(item) for item in diagnostics if item.status == "supported"]
    adapted = [asdict(item) for item in diagnostics if item.status == "adapted"]
    unsupported = [asdict(item) for item in diagnostics if item.status == "unsupported"]

    return {
        "supported": supported,
        "adapted": adapted,
        "unsupported": unsupported,
        "config_summary": {
            "apis": len(result.config.apis),
            "routes": len(result.config.routes),
            "products": len(result.config.products),
            "loggers": len(result.config.loggers),
            "diagnostics": len(result.config.diagnostics),
            "users": len(result.config.users),
            "groups": len(result.config.groups),
            "tags": len(result.config.tags),
            "api_revisions": sum(len(api.revisions) for api in result.config.apis.values()),
            "api_releases": sum(len(api.releases) for api in result.config.apis.values()),
            "subscriptions": len(result.config.subscription.subscriptions),
            "backends": len(result.config.backends),
            "api_version_sets": len(result.config.api_version_sets),
        },
    }
