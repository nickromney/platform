from __future__ import annotations

import logging
import os
from collections.abc import Callable
from pathlib import Path
from typing import Any

from fastapi import HTTPException

from app.config import (
    GatewayConfig,
    GroupConfig,
    ProductConfig,
    Subscription,
    SubscriptionKeyPair,
    TagConfig,
    UserConfig,
    load_config,
)
from app.security import OIDCVerifier

logger = logging.getLogger("apim-simulator")


class ManagementService:
    def __init__(
        self,
        *,
        app: Any,
        serialize_gateway_config: Callable[[GatewayConfig], str],
        build_oidc_verifiers: Callable[[GatewayConfig], dict[str, OIDCVerifier]],
    ) -> None:
        self.app = app
        self._serialize_gateway_config = serialize_gateway_config
        self._build_oidc_verifiers = build_oidc_verifiers

    def reload_config(self) -> GatewayConfig:
        new_config = load_config()
        new_config.routes = new_config.materialize_routes()
        self.app.state.gateway_config = new_config
        self.app.state.oidc_verifiers = self._build_oidc_verifiers(new_config)
        self.app.state.policy_cache = {}
        self.app.state.policy_response_cache = {}
        self.app.state.policy_value_cache = {}
        metrics = getattr(self.app.state, "gateway_metrics", None)
        if metrics is not None:
            metrics.config_reloads.add(1, {"result": "success"})
        logger.info(
            "config reloaded | routes=%d | origins=%s | anonymous=%s",
            len(new_config.routes),
            new_config.allowed_origins,
            new_config.allow_anonymous,
        )
        return new_config

    def apply_runtime_config(self, cfg: GatewayConfig) -> GatewayConfig:
        cfg.routes = cfg.materialize_routes()
        self.app.state.gateway_config = cfg
        self.app.state.oidc_verifiers = self._build_oidc_verifiers(cfg)
        self.app.state.policy_cache = {}
        self.app.state.policy_response_cache = {}
        self.app.state.policy_value_cache = {}
        return cfg

    def persist_or_apply_config(self, cfg: GatewayConfig) -> GatewayConfig:
        config_path = os.getenv("APIM_CONFIG_PATH", "").strip()
        if not config_path:
            return self.apply_runtime_config(cfg)

        try:
            Path(config_path).write_text(self._serialize_gateway_config(cfg), encoding="utf-8")
        except OSError as exc:
            raise HTTPException(status_code=500, detail="Unable to persist config update") from exc
        return self.reload_config()

    def upsert_product(self, cfg: GatewayConfig, product_id: str, body: Any) -> GatewayConfig:
        existing = cfg.products.get(product_id)
        cfg.products[product_id] = ProductConfig(
            name=body.name,
            description=body.description,
            require_subscription=body.require_subscription,
            groups=existing.groups if existing is not None else [],
            tags=existing.tags if existing is not None else [],
        )
        return self.persist_or_apply_config(cfg)

    def delete_product(self, cfg: GatewayConfig, product_id: str) -> GatewayConfig:
        self._get_product_or_404(cfg, product_id)
        del cfg.products[product_id]
        for subscription in cfg.subscription.subscriptions.values():
            subscription.products = [item for item in subscription.products if item != product_id]
        for api in cfg.apis.values():
            api.products = [item for item in api.products if item != product_id]
            for operation in api.operations.values():
                if operation.products is not None:
                    operation.products = [item for item in operation.products if item != product_id]
        for route in cfg.routes:
            if route.product == product_id:
                route.product = None
            route.products = [item for item in route.products if item != product_id]
        return self.persist_or_apply_config(cfg)

    def upsert_tag(self, cfg: GatewayConfig, tag_id: str, body: Any) -> GatewayConfig:
        cfg.tags[tag_id] = TagConfig(display_name=body.display_name or tag_id)
        return self.persist_or_apply_config(cfg)

    def delete_tag(self, cfg: GatewayConfig, tag_id: str) -> GatewayConfig:
        self._get_tag_or_404(cfg, tag_id)
        del cfg.tags[tag_id]
        for api in cfg.apis.values():
            self._unlink_list_item(api.tags, tag_id)
            for operation in api.operations.values():
                self._unlink_list_item(operation.tags, tag_id)
        for product in cfg.products.values():
            self._unlink_list_item(product.tags, tag_id)
        return self.persist_or_apply_config(cfg)

    def upsert_group(self, cfg: GatewayConfig, group_id: str, body: Any) -> GatewayConfig:
        existing = cfg.groups.get(group_id)
        cfg.groups[group_id] = GroupConfig(
            id=group_id,
            name=body.name,
            description=body.description,
            external_id=body.external_id,
            type=body.type,
            users=existing.users if existing is not None else [],
        )
        return self.persist_or_apply_config(cfg)

    def delete_group(self, cfg: GatewayConfig, group_id: str) -> GatewayConfig:
        self._get_group_or_404(cfg, group_id)
        del cfg.groups[group_id]
        for product in cfg.products.values():
            self._unlink_list_item(product.groups, group_id)
        return self.persist_or_apply_config(cfg)

    def upsert_user(self, cfg: GatewayConfig, user_id: str, body: Any) -> GatewayConfig:
        first_name = body.first_name.strip() if body.first_name else None
        last_name = body.last_name.strip() if body.last_name else None
        full_name = " ".join(part for part in [first_name, last_name] if part).strip() or user_id
        cfg.users[user_id] = UserConfig(
            id=user_id,
            email=body.email,
            name=full_name,
            first_name=first_name,
            last_name=last_name,
            note=body.note,
            state=body.state,
            confirmation=body.confirmation,
        )
        return self.persist_or_apply_config(cfg)

    def delete_user(self, cfg: GatewayConfig, user_id: str) -> GatewayConfig:
        self._get_user_or_404(cfg, user_id)
        del cfg.users[user_id]
        for group in cfg.groups.values():
            self._unlink_list_item(group.users, user_id)
        return self.persist_or_apply_config(cfg)

    def create_subscription(self, cfg: GatewayConfig, body: Any) -> GatewayConfig:
        if self.find_subscription_by_id(cfg, body.id) is not None:
            raise HTTPException(status_code=409, detail="Subscription already exists")

        primary = body.primary_key or f"sub-{body.id}-primary"
        secondary = body.secondary_key or f"sub-{body.id}-secondary"
        cfg.subscription.subscriptions[body.id] = Subscription(
            id=body.id,
            name=body.name,
            keys=SubscriptionKeyPair(primary=primary, secondary=secondary),
            state=body.state,
            products=body.products,
            created_by="management",
        )
        return self.persist_or_apply_config(cfg)

    def update_subscription(self, cfg: GatewayConfig, subscription_id: str, body: Any) -> GatewayConfig:
        sub = self.find_subscription_by_id(cfg, subscription_id)
        if sub is None:
            raise HTTPException(status_code=404, detail="Subscription not found")

        if body.name is not None:
            sub.name = body.name
        if body.state is not None:
            sub.state = body.state
        if body.products is not None:
            sub.products = body.products
        return self.persist_or_apply_config(cfg)

    def delete_subscription(self, cfg: GatewayConfig, subscription_id: str) -> GatewayConfig:
        entry = self.find_subscription_entry(cfg, subscription_id)
        if entry is None:
            raise HTTPException(status_code=404, detail="Subscription not found")
        config_key, _subscription = entry
        del cfg.subscription.subscriptions[config_key]
        return self.persist_or_apply_config(cfg)

    def rotate_subscription_key(
        self, cfg: GatewayConfig, subscription_id: str, key: str = "secondary"
    ) -> tuple[GatewayConfig, str]:
        sub = self.find_subscription_by_id(cfg, subscription_id)
        if sub is None:
            raise HTTPException(status_code=404, detail="Subscription not found")
        if key not in {"primary", "secondary"}:
            raise HTTPException(status_code=400, detail="Invalid key")

        new_key = f"rotated-{sub.id}-{key}"
        if key == "primary":
            sub.keys.primary = new_key
        else:
            sub.keys.secondary = new_key
        return self.persist_or_apply_config(cfg), new_key

    def find_subscription_entry(self, cfg: GatewayConfig, subscription_id: str) -> tuple[str, Subscription] | None:
        for config_key, sub in cfg.subscription.subscriptions.items():
            if sub.id == subscription_id:
                return config_key, sub
        return None

    def find_subscription_by_id(self, cfg: GatewayConfig, subscription_id: str) -> Subscription | None:
        entry = self.find_subscription_entry(cfg, subscription_id)
        return entry[1] if entry is not None else None

    def _get_product_or_404(self, cfg: GatewayConfig, product_id: str) -> ProductConfig:
        product = cfg.products.get(product_id)
        if product is None:
            raise HTTPException(status_code=404, detail="Product not found")
        return product

    def _get_group_or_404(self, cfg: GatewayConfig, group_id: str) -> GroupConfig:
        group = cfg.groups.get(group_id)
        if group is None:
            raise HTTPException(status_code=404, detail="Group not found")
        return group

    def _get_user_or_404(self, cfg: GatewayConfig, user_id: str) -> UserConfig:
        user = cfg.users.get(user_id)
        if user is None:
            raise HTTPException(status_code=404, detail="User not found")
        return user

    def _get_tag_or_404(self, cfg: GatewayConfig, tag_id: str) -> TagConfig:
        tag = cfg.tags.get(tag_id)
        if tag is None:
            raise HTTPException(status_code=404, detail="Tag not found")
        return tag

    @staticmethod
    def _unlink_list_item(values: list[str], item_id: str) -> bool:
        if item_id not in values:
            return False
        values[:] = [item for item in values if item != item_id]
        return True
