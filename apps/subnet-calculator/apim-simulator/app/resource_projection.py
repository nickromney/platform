from __future__ import annotations

from typing import Any

from app.config import (
    ApiConfig,
    ApiReleaseConfig,
    ApiRevisionConfig,
    ApiSchemaConfig,
    ApiVersionSetConfig,
    BackendConfig,
    DiagnosticConfig,
    GatewayConfig,
    GroupConfig,
    LoggerConfig,
    NamedValueConfig,
    OperationConfig,
    ProductConfig,
    RouteConfig,
    Subscription,
    TagConfig,
    UserConfig,
)
from app.named_values import mask_secret_data, resolve_named_value


def service_resource_id(config: GatewayConfig) -> str:
    return f"service/{config.service.name}"


def nested_resource_id(config: GatewayConfig, *parts: str) -> str:
    return "/".join([service_resource_id(config), *parts])


def policy_scope(scope_type: str, scope_name: str) -> dict[str, str]:
    return {"scope_type": scope_type, "scope_name": scope_name}


def project_route(config: GatewayConfig, route: RouteConfig) -> dict[str, Any]:
    payload = {
        "name": route.name,
        "path_prefix": route.path_prefix,
        "host_match": route.host_match,
        "methods": route.methods,
        "upstream_base_url": route.upstream_base_url,
        "upstream_path_prefix": route.upstream_path_prefix,
        "backend": route.backend,
        "product": route.product,
        "products": route.products,
        "api_version_set": route.api_version_set,
        "api_version": route.api_version,
    }
    if not config.apis:
        payload["policy_scope"] = policy_scope("route", route.name)
    return payload


def project_operation(
    config: GatewayConfig, api_id: str, operation_id: str, operation: OperationConfig
) -> dict[str, Any]:
    return {
        "id": operation_id,
        "resource_id": nested_resource_id(config, "apis", api_id, "operations", operation_id),
        "api_id": api_id,
        "name": operation.name,
        "method": operation.method,
        "url_template": operation.url_template,
        "description": operation.description,
        "upstream_base_url": operation.upstream_base_url,
        "upstream_path_prefix": operation.upstream_path_prefix,
        "backend": operation.backend,
        "products": operation.products,
        "api_version_set": operation.api_version_set,
        "api_version": operation.api_version,
        "subscription_header_names": operation.subscription_header_names,
        "subscription_query_param_names": operation.subscription_query_param_names,
        "authz": operation.authz.model_dump(mode="json") if operation.authz is not None else None,
        "tags": list(operation.tags),
        "template_parameters": [item.model_dump(mode="json") for item in operation.template_parameters],
        "request": operation.request.model_dump(mode="json") if operation.request is not None else None,
        "responses": [item.model_dump(mode="json") for item in operation.responses],
        "policy_scope": policy_scope("operation", f"{api_id}:{operation_id}"),
    }


def project_api_schema(config: GatewayConfig, api_id: str, schema_id: str, schema: ApiSchemaConfig) -> dict[str, Any]:
    return {
        "id": schema_id,
        "resource_id": nested_resource_id(config, "apis", api_id, "schemas", schema_id),
        **schema.model_dump(mode="json"),
    }


def project_api_revision(
    config: GatewayConfig, api_id: str, revision_id: str, revision: ApiRevisionConfig
) -> dict[str, Any]:
    return {
        "id": revision_id,
        "resource_id": nested_resource_id(config, "apis", api_id, "revisions", revision_id),
        **revision.model_dump(mode="json"),
    }


def project_api_release(
    config: GatewayConfig, api_id: str, release_id: str, release: ApiReleaseConfig
) -> dict[str, Any]:
    return {
        "id": release_id,
        "resource_id": nested_resource_id(config, "apis", api_id, "releases", release_id),
        **release.model_dump(mode="json"),
    }


def project_api(config: GatewayConfig, api_id: str, api: ApiConfig) -> dict[str, Any]:
    return {
        "id": api_id,
        "resource_id": nested_resource_id(config, "apis", api_id),
        "name": api.name,
        "path": api.path,
        "upstream_base_url": api.upstream_base_url,
        "upstream_path_prefix": api.upstream_path_prefix,
        "backend": api.backend,
        "products": api.products,
        "api_version_set": api.api_version_set,
        "api_version": api.api_version,
        "revision": api.revision,
        "revision_description": api.revision_description,
        "version_description": api.version_description,
        "source_api_id": api.source_api_id,
        "is_current": api.is_current,
        "is_online": api.is_online,
        "subscription_header_names": api.subscription_header_names,
        "subscription_query_param_names": api.subscription_query_param_names,
        "tags": list(api.tags),
        "policy_scope": policy_scope("api", api_id),
        "operations": [
            project_operation(config, api_id, operation_id, op) for operation_id, op in api.operations.items()
        ],
        "schemas": [project_api_schema(config, api_id, schema_id, schema) for schema_id, schema in api.schemas.items()],
        "revisions": [
            project_api_revision(config, api_id, revision_id, revision)
            for revision_id, revision in api.revisions.items()
        ],
        "releases": [
            project_api_release(config, api_id, release_id, release) for release_id, release in api.releases.items()
        ],
    }


def project_product(config: GatewayConfig, product_id: str, product: ProductConfig) -> dict[str, Any]:
    subscription_count = sum(1 for sub in config.subscription.subscriptions.values() if product_id in sub.products)
    return {
        "id": product_id,
        "resource_id": nested_resource_id(config, "products", product_id),
        "name": product.name,
        "description": product.description,
        "require_subscription": product.require_subscription,
        "groups": list(product.groups),
        "tags": list(product.tags),
        "subscription_count": subscription_count,
    }


def project_tag(config: GatewayConfig, tag_id: str, tag: TagConfig) -> dict[str, Any]:
    return {
        "id": tag_id,
        "resource_id": nested_resource_id(config, "tags", tag_id),
        "display_name": tag.display_name,
    }


def project_api_tag_link(config: GatewayConfig, api_id: str, tag_id: str, tag: TagConfig) -> dict[str, Any]:
    return {
        "id": tag_id,
        "resource_id": nested_resource_id(config, "apis", api_id, "tags", tag_id),
        "tag_resource_id": nested_resource_id(config, "tags", tag_id),
        "api_id": api_id,
        "display_name": tag.display_name,
    }


def project_operation_tag_link(
    config: GatewayConfig, api_id: str, operation_id: str, tag_id: str, tag: TagConfig
) -> dict[str, Any]:
    return {
        "id": tag_id,
        "resource_id": nested_resource_id(config, "apis", api_id, "operations", operation_id, "tags", tag_id),
        "tag_resource_id": nested_resource_id(config, "tags", tag_id),
        "api_id": api_id,
        "operation_id": operation_id,
        "display_name": tag.display_name,
    }


def project_product_tag_link(config: GatewayConfig, product_id: str, tag_id: str, tag: TagConfig) -> dict[str, Any]:
    return {
        "id": tag_id,
        "resource_id": nested_resource_id(config, "products", product_id, "tags", tag_id),
        "tag_resource_id": nested_resource_id(config, "tags", tag_id),
        "product_id": product_id,
        "display_name": tag.display_name,
    }


def project_subscription(config: GatewayConfig, config_key: str, subscription: Subscription) -> dict[str, Any]:
    return {
        "id": subscription.id,
        "resource_id": nested_resource_id(config, "subscriptions", subscription.id),
        "config_key": config_key,
        "name": subscription.name,
        "state": subscription.state.value,
        "products": subscription.products,
        "created_by": subscription.created_by,
        "keys": subscription.keys.model_dump(mode="json"),
    }


def project_backend(config: GatewayConfig, backend_id: str, backend: BackendConfig) -> dict[str, Any]:
    return {
        "id": backend_id,
        "resource_id": nested_resource_id(config, "backends", backend_id),
        **backend.model_dump(mode="json"),
    }


def project_named_value(config: GatewayConfig, named_value_id: str, named_value: NamedValueConfig) -> dict[str, Any]:
    resolved = resolve_named_value(config, named_value_id)
    return {
        "id": named_value_id,
        "resource_id": nested_resource_id(config, "named-values", named_value_id),
        "secret": named_value.secret,
        "value": named_value.value,
        "value_from_key_vault": (
            named_value.value_from_key_vault.model_dump(mode="json") if named_value.value_from_key_vault else None
        ),
        "resolved": (
            {
                "source": resolved.source,
                "env_var_name": resolved.env_var_name,
                "value": resolved.value,
                "is_secret": resolved.is_secret,
            }
            if resolved is not None
            else None
        ),
    }


def _masked_logger_payload(logger: LoggerConfig) -> dict[str, Any]:
    payload = logger.model_dump(mode="json")
    app_insights = payload.get("application_insights")
    if isinstance(app_insights, dict):
        if app_insights.get("connection_string"):
            app_insights["connection_string"] = "***"
        if app_insights.get("instrumentation_key"):
            app_insights["instrumentation_key"] = "***"
    eventhub = payload.get("eventhub")
    if isinstance(eventhub, dict) and eventhub.get("connection_string"):
        eventhub["connection_string"] = "***"
    return payload


def project_logger(config: GatewayConfig, logger_id: str, logger: LoggerConfig) -> dict[str, Any]:
    payload = _masked_logger_payload(logger)
    target_resource_id = payload.pop("resource_id", None)
    return {
        "id": logger_id,
        "resource_id": nested_resource_id(config, "loggers", logger_id),
        "target_resource_id": target_resource_id,
        **payload,
    }


def project_diagnostic(config: GatewayConfig, diagnostic_id: str, diagnostic: DiagnosticConfig) -> dict[str, Any]:
    logger_resource_id = None
    if diagnostic.logger_id and diagnostic.logger_id in config.loggers:
        logger_resource_id = nested_resource_id(config, "loggers", diagnostic.logger_id)
    return {
        "id": diagnostic_id,
        "resource_id": nested_resource_id(config, "diagnostics", diagnostic_id),
        "logger_resource_id": logger_resource_id,
        **diagnostic.model_dump(mode="json"),
    }


def project_api_version_set(
    config: GatewayConfig, version_set_id: str, version_set: ApiVersionSetConfig
) -> dict[str, Any]:
    return {
        "id": version_set_id,
        "resource_id": nested_resource_id(config, "api-version-sets", version_set_id),
        **version_set.model_dump(mode="json"),
    }


def project_policy_fragment(config: GatewayConfig, fragment_id: str, xml: str) -> dict[str, Any]:
    return {
        "id": fragment_id,
        "resource_id": nested_resource_id(config, "policy-fragments", fragment_id),
        "xml": xml,
    }


def project_user(config: GatewayConfig, user_id: str, user: UserConfig) -> dict[str, Any]:
    groups = sorted(group_id for group_id, group in config.groups.items() if user_id in group.users)
    return {
        "id": user_id,
        "resource_id": nested_resource_id(config, "users", user_id),
        "email": user.email,
        "name": user.name,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "note": user.note,
        "state": user.state,
        "confirmation": user.confirmation,
        "groups": groups,
    }


def project_group(config: GatewayConfig, group_id: str, group: GroupConfig) -> dict[str, Any]:
    products = sorted(product_id for product_id, product in config.products.items() if group_id in product.groups)
    return {
        "id": group_id,
        "resource_id": nested_resource_id(config, "groups", group_id),
        "name": group.name,
        "description": group.description,
        "external_id": group.external_id,
        "type": group.type,
        "users": group.users,
        "products": products,
    }


def project_group_user_link(config: GatewayConfig, group_id: str, user_id: str, user: UserConfig) -> dict[str, Any]:
    return {
        "id": user_id,
        "resource_id": nested_resource_id(config, "groups", group_id, "users", user_id),
        "group_resource_id": nested_resource_id(config, "groups", group_id),
        "user_resource_id": nested_resource_id(config, "users", user_id),
        "group_id": group_id,
        "email": user.email,
        "name": user.name,
    }


def project_product_group_link(
    config: GatewayConfig, product_id: str, group_id: str, group: GroupConfig
) -> dict[str, Any]:
    return {
        "id": group_id,
        "resource_id": nested_resource_id(config, "products", product_id, "groups", group_id),
        "group_resource_id": nested_resource_id(config, "groups", group_id),
        "product_id": product_id,
        "name": group.name,
        "type": group.type,
    }


def project_service(config: GatewayConfig, *, trace_store: dict[str, Any] | None = None) -> dict[str, Any]:
    return {
        "id": service_resource_id(config),
        "name": config.service.name,
        "display_name": config.service.display_name,
        "public_network_access_enabled": config.service.public_network_access_enabled,
        "virtual_network_type": config.service.virtual_network_type,
        "hostname_configurations": [item.model_dump(mode="json") for item in config.service.hostname_configurations],
        "gateway_policy_scope": policy_scope("gateway", "gateway"),
        "counts": {
            "routes": len(config.routes),
            "apis": len(config.apis),
            "operations": sum(len(api.operations) for api in config.apis.values()),
            "api_revisions": sum(len(api.revisions) for api in config.apis.values()),
            "api_releases": sum(len(api.releases) for api in config.apis.values()),
            "products": len(config.products),
            "subscriptions": len(config.subscription.subscriptions),
            "backends": len(config.backends),
            "named_values": len(config.named_values),
            "loggers": len(config.loggers),
            "diagnostics": len(config.diagnostics),
            "api_version_sets": len(config.api_version_sets),
            "policy_fragments": len(config.policy_fragments),
            "users": len(config.users),
            "groups": len(config.groups),
            "tags": len(config.tags),
            "recent_traces": len(trace_store or {}),
        },
        "management": {
            "tenant_access_enabled": config.tenant_access.enabled,
            "status_path": "/apim/management/status",
            "summary_path": "/apim/management/summary",
        },
        "tracing": {
            "enabled": config.trace_enabled,
            "lookup_path_template": "/apim/trace/{trace_id}",
            "recent_path": "/apim/management/traces",
        },
        "routes": [project_route(config, route) for route in config.routes],
    }


def project_summary(config: GatewayConfig, *, trace_store: dict[str, Any] | None = None) -> dict[str, Any]:
    payload = {
        "service": project_service(config, trace_store=trace_store),
        "gateway_policy_scope": policy_scope("gateway", "gateway"),
        "apis": [project_api(config, api_id, api) for api_id, api in config.apis.items()],
        "routes": [project_route(config, route) for route in config.routes],
        "products": [project_product(config, product_id, product) for product_id, product in config.products.items()],
        "subscriptions": [
            project_subscription(config, config_key, subscription)
            for config_key, subscription in config.subscription.subscriptions.items()
        ],
        "backends": [project_backend(config, backend_id, backend) for backend_id, backend in config.backends.items()],
        "named_values": [
            project_named_value(config, named_value_id, named_value)
            for named_value_id, named_value in config.named_values.items()
        ],
        "loggers": [project_logger(config, logger_id, logger) for logger_id, logger in config.loggers.items()],
        "diagnostics": [
            project_diagnostic(config, diagnostic_id, diagnostic)
            for diagnostic_id, diagnostic in config.diagnostics.items()
        ],
        "api_version_sets": [
            project_api_version_set(config, version_set_id, version_set)
            for version_set_id, version_set in config.api_version_sets.items()
        ],
        "policy_fragments": [
            project_policy_fragment(config, fragment_id, xml) for fragment_id, xml in config.policy_fragments.items()
        ],
        "users": [project_user(config, user_id, user) for user_id, user in config.users.items()],
        "groups": [project_group(config, group_id, group) for group_id, group in config.groups.items()],
        "tags": [project_tag(config, tag_id, tag) for tag_id, tag in config.tags.items()],
    }
    return mask_secret_data(payload, config)
