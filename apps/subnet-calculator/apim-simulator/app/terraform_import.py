from __future__ import annotations

from collections.abc import Iterable
from dataclasses import dataclass
from typing import Any

from app.config import (
    ApiConfig,
    GatewayConfig,
    NamedValueConfig,
    OperationConfig,
    ProductConfig,
    Subscription,
    SubscriptionKeyPair,
)


@dataclass(frozen=True)
class TFResource:
    address: str
    type: str
    name: str
    values: dict[str, Any]


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


def config_from_tofu_show_json(tf: dict[str, Any]) -> GatewayConfig:
    resources = _iter_resources(tf)

    products: dict[str, ProductConfig] = {}
    subscriptions: dict[str, Subscription] = {}
    named_values: dict[str, NamedValueConfig] = {}
    apis: dict[str, ApiConfig] = {}

    # ---- First pass: base resources ----
    for res in resources:
        if res.type == "azurerm_api_management_product":
            product_id = str(res.values.get("product_id") or res.values.get("product_id") or res.name)
            display_name = str(res.values.get("display_name") or product_id)
            subscription_required = res.values.get("subscription_required")
            require_subscription = bool(subscription_required) if subscription_required is not None else True
            products[product_id] = ProductConfig(name=display_name, require_subscription=require_subscription)

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
            name = str(res.values.get("name") or res.name)
            value = str(res.values.get("value") or "")
            secret = bool(res.values.get("secret"))
            named_values[name] = NamedValueConfig(value=value, secret=secret)

        if res.type == "azurerm_api_management_api":
            api_name = str(res.values.get("name") or res.name)
            path = str(res.values.get("path") or api_name)
            # service_url is optional in APIM; for simulator default to placeholder.
            upstream = str(res.values.get("service_url") or "http://upstream")
            apis[api_name] = ApiConfig(name=api_name, path=path, upstream_base_url=upstream)

    # ---- Second pass: children, associations, and policies ----
    for res in resources:
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
            )

        if res.type == "azurerm_api_management_product_api":
            product_id = str(res.values.get("product_id") or "")
            api_name = str(res.values.get("api_name") or "")
            if product_id and api_name and api_name in apis:
                apis[api_name].products.append(product_id)

        if res.type == "azurerm_api_management_subscription":
            sub_id = str(res.values.get("subscription_id") or res.values.get("name") or res.name)
            if sub_id not in subscriptions:
                continue
            product_id = res.values.get("product_id")
            if isinstance(product_id, str) and product_id:
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

    # Determine gateway policy (if any) from the last policy resource we saw.
    gateway_policy: str | None = None
    for res in resources:
        if res.type != "azurerm_api_management_policy":
            continue
        xml = res.values.get("xml_content")
        if isinstance(xml, str) and xml:
            gateway_policy = xml

    cfg = GatewayConfig(
        allow_anonymous=True,
        products=products,
        named_values=named_values,
        subscription={
            "required": True,
            "subscriptions": subscriptions,
        },
        apis=apis,
        policies_xml=gateway_policy,
    )
    cfg.routes = cfg.materialize_routes()
    return cfg
