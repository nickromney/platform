from __future__ import annotations

from urllib.parse import urlunsplit


def _split_target(target: str) -> tuple[str, str, str]:
    host, _, remainder = target.partition("/")
    path, _, query = remainder.partition("?")
    return host, f"/{path}" if path else "", query


def http_url(target: str) -> str:
    host, path, query = _split_target(target)
    return urlunsplit(("http", host, path, query, ""))


def https_url(target: str) -> str:
    host, path, query = _split_target(target)
    return urlunsplit(("https", host, path, query, ""))
