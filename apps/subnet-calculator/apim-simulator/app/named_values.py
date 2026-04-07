from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import Any

from app.config import GatewayConfig

NAMED_VALUE_PATTERN = re.compile(r"\{\{([^{}]+)\}\}")
ENV_NAME_PATTERN = re.compile(r"[^A-Za-z0-9]+")


@dataclass(frozen=True)
class ResolvedNamedValue:
    name: str
    value: str | None
    is_secret: bool
    source: str
    env_var_name: str


def named_value_env_var(name: str) -> str:
    normalized = ENV_NAME_PATTERN.sub("_", name.strip()).strip("_").upper()
    return f"APIM_NAMED_VALUE_{normalized}" if normalized else "APIM_NAMED_VALUE"


def resolve_named_value(config: GatewayConfig, name: str) -> ResolvedNamedValue | None:
    entry = config.named_values.get(name)
    if entry is None:
        return None

    env_var_name = named_value_env_var(name)
    env_override = os.environ.get(env_var_name)
    if env_override is not None:
        return ResolvedNamedValue(
            name=name,
            value=env_override,
            is_secret=entry.secret or entry.value_from_key_vault is not None,
            source="env",
            env_var_name=env_var_name,
        )

    if entry.value is not None:
        return ResolvedNamedValue(
            name=name,
            value=entry.value,
            is_secret=entry.secret,
            source="config",
            env_var_name=env_var_name,
        )

    return ResolvedNamedValue(
        name=name,
        value=None,
        is_secret=True,
        source="key_vault",
        env_var_name=env_var_name,
    )


def resolve_named_values_in_text(text: str, config: GatewayConfig) -> str:
    def _replace(match: re.Match[str]) -> str:
        resolved = resolve_named_value(config, match.group(1).strip())
        if resolved is None or resolved.value is None:
            return match.group(0)
        return resolved.value

    return NAMED_VALUE_PATTERN.sub(_replace, text)


def secret_named_value_map(config: GatewayConfig) -> dict[str, str]:
    out: dict[str, str] = {}
    for name in config.named_values:
        resolved = resolve_named_value(config, name)
        if resolved is None or not resolved.is_secret or not resolved.value:
            continue
        out[name] = resolved.value
    return out


def mask_secret_text(value: str, config: GatewayConfig) -> str:
    out = value
    for secret in secret_named_value_map(config).values():
        out = out.replace(secret, "***")
    return out


def mask_secret_data(value: Any, config: GatewayConfig) -> Any:
    if isinstance(value, str):
        return mask_secret_text(value, config)
    if isinstance(value, bytes):
        return mask_secret_text(value.decode("utf-8", errors="replace"), config)
    if isinstance(value, dict):
        return {str(key): mask_secret_data(item, config) for key, item in value.items()}
    if isinstance(value, list):
        return [mask_secret_data(item, config) for item in value]
    return value
