from __future__ import annotations

from app import run_server


def test_prepare_runtime_config_substitutes_env_vars_when_enabled(monkeypatch, tmp_path) -> None:
    source = tmp_path / "config.template.json"
    target = tmp_path / "rendered" / "config.json"
    source.write_text('{"issuer":"${OIDC_ISSUER_EXTERNAL}"}', encoding="utf-8")

    monkeypatch.setenv("APIM_CONFIG_SOURCE_PATH", str(source))
    monkeypatch.setenv("APIM_CONFIG_PATH", str(target))
    monkeypatch.setenv("APIM_CONFIG_TEMPLATE_SUBSTITUTE", "true")
    monkeypatch.setenv("OIDC_ISSUER_EXTERNAL", "http://localhost:8180/realms/demo")

    run_server._prepare_runtime_config()

    assert target.read_text(encoding="utf-8") == ('{"issuer":"http://localhost:8180/realms/demo"}')
