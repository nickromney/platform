import sys
from pathlib import Path
from unittest.mock import MagicMock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from idp_mcp.server import IdpApiClient, TOOLS, tool_definitions, handle_tool_call


def test_default_api_base_url_uses_public_https_fqdn(monkeypatch) -> None:
    monkeypatch.delenv("IDP_API_BASE_URL", raising=False)

    assert IdpApiClient.from_env().base_url == "https://portal-api.127.0.0.1.sslip.io"


def test_env_api_base_url_override_is_trimmed(monkeypatch) -> None:
    monkeypatch.setenv("IDP_API_BASE_URL", "https://example.test///")

    assert IdpApiClient.from_env().base_url == "https://example.test"


# Tool registry — the TOOLS dict is the single source of truth.


def test_tool_definitions_names_match_registry() -> None:
    defs = tool_definitions()
    def_names = {d["name"] for d in defs}
    assert def_names == set(TOOLS.keys())


def test_tool_definitions_include_required_fields() -> None:
    for defn in tool_definitions():
        assert "name" in defn
        assert "description" in defn
        assert "inputSchema" in defn


def test_handle_tool_call_dispatches_platform_status() -> None:
    client = MagicMock()
    client.platform_status.return_value = {"status": "ok"}

    result = handle_tool_call(client, "platform_status", {})

    client.platform_status.assert_called_once()
    assert result["content"][0]["type"] == "text"
    assert '"status"' in result["content"][0]["text"]


def test_handle_tool_call_dispatches_catalog_list() -> None:
    client = MagicMock()
    client.catalog_list.return_value = {"apps": []}

    result = handle_tool_call(client, "catalog_list", {})

    client.catalog_list.assert_called_once()
    assert '"apps"' in result["content"][0]["text"]


def test_handle_tool_call_dispatches_environment_create() -> None:
    client = MagicMock()
    client.create_environment.return_value = {"status": "dry_run"}
    args = {"app": "subnetcalc", "environment": "dev"}

    result = handle_tool_call(client, "environment_create", args)

    client.create_environment.assert_called_once_with(args)
    assert '"status"' in result["content"][0]["text"]


def test_handle_tool_call_raises_for_unknown_tool() -> None:
    client = MagicMock()

    import pytest

    with pytest.raises(ValueError, match="unsupported tool"):
        handle_tool_call(client, "nonexistent_tool", {})


def test_every_registered_tool_has_a_handler() -> None:
    for name, spec in TOOLS.items():
        assert callable(spec["handler"]), f"tool {name!r} missing callable handler"
