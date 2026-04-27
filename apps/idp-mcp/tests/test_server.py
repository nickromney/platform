import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from idp_mcp.server import IdpApiClient


def test_default_api_base_url_uses_public_https_fqdn(monkeypatch) -> None:
    monkeypatch.delenv("IDP_API_BASE_URL", raising=False)

    assert IdpApiClient.from_env().base_url == "https://portal-api.127.0.0.1.sslip.io"


def test_env_api_base_url_override_is_trimmed(monkeypatch) -> None:
    monkeypatch.setenv("IDP_API_BASE_URL", "https://example.test///")

    assert IdpApiClient.from_env().base_url == "https://example.test"
