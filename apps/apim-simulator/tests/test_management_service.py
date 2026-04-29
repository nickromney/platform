from __future__ import annotations

import json
from types import SimpleNamespace

import pytest
from fastapi import HTTPException

from app.config import (
    ApiConfig,
    GatewayConfig,
    GroupConfig,
    OperationConfig,
    ProductConfig,
    RouteConfig,
    Subscription,
    SubscriptionConfig,
    SubscriptionKeyPair,
    SubscriptionState,
    TagConfig,
    UserConfig,
)
from app.management_service import ManagementService
from app.urls import http_url


class _Counter:
    def __init__(self) -> None:
        self.calls: list[tuple[int, dict[str, str]]] = []

    def add(self, value: int, attrs: dict[str, str]) -> None:
        self.calls.append((value, attrs))


def _make_service(cfg: GatewayConfig) -> tuple[ManagementService, SimpleNamespace, _Counter]:
    counter = _Counter()
    app = SimpleNamespace(
        state=SimpleNamespace(
            gateway_config=cfg,
            oidc_verifiers={},
            policy_cache={"cached": True},
            policy_response_cache={"cached": True},
            policy_value_cache={"cached": True},
            gateway_metrics=SimpleNamespace(config_reloads=counter),
        )
    )
    service = ManagementService(
        app=app,
        serialize_gateway_config=lambda current: json.dumps(current.model_dump(mode="json"), indent=2) + "\n",
        build_oidc_verifiers=lambda current: {"route_count": str(len(current.routes))},
    )
    return service, app, counter


def test_apply_runtime_config_materializes_routes_and_clears_policy_caches() -> None:
    cfg = GatewayConfig(
        apis={
            "weather": ApiConfig(
                name="weather",
                path="weather",
                upstream_base_url=http_url("upstream"),
                operations={
                    "current": OperationConfig(name="current", method="GET", url_template="/current"),
                },
            )
        }
    )
    service, app, _ = _make_service(cfg)

    updated = service.apply_runtime_config(cfg)

    assert updated.routes[0].name == "weather:current"
    assert app.state.gateway_config is updated
    assert app.state.oidc_verifiers == {"route_count": "1"}
    assert app.state.policy_cache == {}
    assert app.state.policy_response_cache == {}
    assert app.state.policy_value_cache == {}


def test_persist_or_apply_config_writes_and_reloads_from_disk(tmp_path, monkeypatch) -> None:
    config_path = tmp_path / "apim.json"
    monkeypatch.setenv("APIM_CONFIG_PATH", str(config_path))

    cfg = GatewayConfig(products={"starter": ProductConfig(name="Starter")})
    service, app, counter = _make_service(cfg)

    updated = service.persist_or_apply_config(cfg)

    payload = json.loads(config_path.read_text(encoding="utf-8"))
    assert payload["products"]["starter"]["name"] == "Starter"
    assert updated.products["starter"].name == "Starter"
    assert app.state.gateway_config.products["starter"].name == "Starter"
    assert counter.calls == [(1, {"result": "success"})]


def test_delete_product_unlinks_legacy_routes_and_subscriptions() -> None:
    cfg = GatewayConfig(
        products={"starter": ProductConfig(name="Starter")},
        subscription=SubscriptionConfig(
            subscriptions={
                "demo": Subscription(
                    id="demo",
                    name="Demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=["starter"],
                )
            }
        ),
        apis={
            "weather": ApiConfig(
                name="weather",
                path="weather",
                upstream_base_url=http_url("upstream"),
                products=["starter"],
                operations={
                    "current": OperationConfig(
                        name="current",
                        method="GET",
                        url_template="/current",
                        products=["starter", "pro"],
                    )
                },
            )
        },
        routes=[
            RouteConfig(
                name="legacy",
                path_prefix="/legacy",
                upstream_base_url=http_url("upstream"),
                product="starter",
                products=["starter"],
            )
        ],
    )
    service, _, _ = _make_service(cfg)

    updated = service.delete_product(cfg, "starter")

    assert "starter" not in updated.products
    assert updated.subscription.subscriptions["demo"].products == []
    assert updated.apis["weather"].products == []
    assert updated.apis["weather"].operations["current"].products == ["pro"]
    assert all(route.product != "starter" for route in updated.routes)
    assert all("starter" not in route.products for route in updated.routes)


def test_subscription_lifecycle_round_trips_through_persistence() -> None:
    cfg = GatewayConfig()
    service, _, _ = _make_service(cfg)

    created = service.create_subscription(
        cfg,
        SimpleNamespace(
            id="demo",
            name="Demo",
            state=SubscriptionState.Active,
            products=["starter"],
            primary_key=None,
            secondary_key=None,
        ),
    )
    assert created.subscription.subscriptions["demo"].created_by == "management"
    assert created.subscription.subscriptions["demo"].keys.primary == "sub-demo-primary"

    updated = service.update_subscription(
        created,
        "demo",
        SimpleNamespace(name="Demo Plus", state=SubscriptionState.Suspended, products=["starter", "pro"]),
    )
    assert updated.subscription.subscriptions["demo"].name == "Demo Plus"
    assert updated.subscription.subscriptions["demo"].state == SubscriptionState.Suspended
    assert updated.subscription.subscriptions["demo"].products == ["starter", "pro"]

    rotated, new_key = service.rotate_subscription_key(updated, "demo", "secondary")
    assert rotated.subscription.subscriptions["demo"].keys.secondary == new_key

    deleted = service.delete_subscription(rotated, "demo")
    assert "demo" not in deleted.subscription.subscriptions


def test_persist_or_apply_config_returns_http_500_when_write_fails(tmp_path, monkeypatch) -> None:
    monkeypatch.setenv("APIM_CONFIG_PATH", str(tmp_path))
    cfg = GatewayConfig(products={"starter": ProductConfig(name="Starter")})
    service, _, _ = _make_service(cfg)

    with pytest.raises(HTTPException, match="Unable to persist config update") as exc_info:
        service.persist_or_apply_config(cfg)

    assert exc_info.value.status_code == 500


def test_subscription_error_paths_and_primary_rotation() -> None:
    cfg = GatewayConfig(
        subscription=SubscriptionConfig(
            subscriptions={
                "demo": Subscription(
                    id="demo",
                    name="Demo",
                    keys=SubscriptionKeyPair(primary="good", secondary="good2"),
                    products=[],
                )
            }
        )
    )
    service, _, _ = _make_service(cfg)

    with pytest.raises(HTTPException, match="Subscription already exists") as duplicate_exc:
        service.create_subscription(
            cfg,
            SimpleNamespace(
                id="demo",
                name="Duplicate",
                state=SubscriptionState.Active,
                products=[],
                primary_key=None,
                secondary_key=None,
            ),
        )
    assert duplicate_exc.value.status_code == 409

    with pytest.raises(HTTPException, match="Subscription not found") as missing_update_exc:
        service.update_subscription(cfg, "missing", SimpleNamespace(name="x", state=None, products=None))
    assert missing_update_exc.value.status_code == 404

    with pytest.raises(HTTPException, match="Subscription not found") as missing_delete_exc:
        service.delete_subscription(cfg, "missing")
    assert missing_delete_exc.value.status_code == 404

    with pytest.raises(HTTPException, match="Subscription not found") as missing_rotate_exc:
        service.rotate_subscription_key(cfg, "missing")
    assert missing_rotate_exc.value.status_code == 404

    with pytest.raises(HTTPException, match="Invalid key") as invalid_key_exc:
        service.rotate_subscription_key(cfg, "demo", "tertiary")
    assert invalid_key_exc.value.status_code == 400

    rotated, new_key = service.rotate_subscription_key(cfg, "demo", "primary")
    assert rotated.subscription.subscriptions["demo"].keys.primary == new_key


def test_management_service_raises_not_found_for_missing_resources() -> None:
    cfg = GatewayConfig(
        groups={"admins": GroupConfig(id="admins", name="Admins")},
        users={"alice": UserConfig(id="alice", name="Alice", email="alice@example.com")},
        tags={"featured": TagConfig(display_name="Featured")},
    )
    service, _, _ = _make_service(cfg)

    with pytest.raises(HTTPException, match="Product not found") as product_exc:
        service.delete_product(cfg, "missing")
    assert product_exc.value.status_code == 404

    with pytest.raises(HTTPException, match="Group not found") as group_exc:
        service.delete_group(cfg, "missing")
    assert group_exc.value.status_code == 404

    with pytest.raises(HTTPException, match="User not found") as user_exc:
        service.delete_user(cfg, "missing")
    assert user_exc.value.status_code == 404

    with pytest.raises(HTTPException, match="Tag not found") as tag_exc:
        service.delete_tag(cfg, "missing")
    assert tag_exc.value.status_code == 404


def test_unlink_list_item_returns_false_when_item_is_missing() -> None:
    values = ["starter"]

    result = ManagementService._unlink_list_item(values, "missing")

    assert result is False
    assert values == ["starter"]
