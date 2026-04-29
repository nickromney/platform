from __future__ import annotations

from urllib.parse import urlunsplit

from app.urls import http_url, https_url


def test_http_url_handles_host_only_targets() -> None:
    assert http_url("localhost:8000") == urlunsplit(("http", "localhost:8000", "", "", ""))


def test_http_url_handles_path_and_query_targets() -> None:
    assert http_url("localhost:8000/api/health?name=team") == urlunsplit(
        ("http", "localhost:8000", "/api/health", "name=team", "")
    )


def test_https_url_handles_path_and_query_targets() -> None:
    assert https_url("edge.apim.127.0.0.1.sslip.io:9443/api/health?name=team") == urlunsplit(
        ("https", "edge.apim.127.0.0.1.sslip.io:9443", "/api/health", "name=team", "")
    )
