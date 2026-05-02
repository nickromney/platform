from __future__ import annotations

import base64
import json
import time
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives.serialization import pkcs12
from cryptography.x509.oid import NameOID
from fastapi.testclient import TestClient

from app.config import GatewayConfig, KeyVaultNamedValueConfig, NamedValueConfig
from app.main import create_app
from app.named_values import resolve_named_value


def _token(*, exp_delta: int = 3600) -> str:
    return jwt.encode(
        {"sub": "local-dev", "exp": int(time.time()) + exp_delta},
        "local-dev-keyvault-test-secret-key",
        algorithm="HS256",
    )


def _headers() -> dict[str, str]:
    return {"Authorization": f"Bearer {_token()}"}


def _certificate() -> tuple[str, str, bytes]:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COMMON_NAME, "demo.platform.local"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Platform Local"),
        ]
    )
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(UTC) - timedelta(minutes=5))
        .not_valid_after(datetime.now(UTC) + timedelta(days=30))
        .add_extension(
            x509.SubjectAlternativeName([x509.DNSName("demo.platform.local"), x509.DNSName("demo.127.0.0.1.sslip.io")]),
            critical=False,
        )
        .sign(key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
    key_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode("utf-8")
    pfx = pkcs12.serialize_key_and_certificates(
        name=b"demo-platform",
        key=key,
        cert=cert,
        cas=None,
        encryption_algorithm=serialization.BestAvailableEncryption(b"password"),
    )
    return cert_pem, key_pem, pfx


def _assert_no_private_material(payload: Any) -> None:
    text = json.dumps(payload)
    assert "PRIVATE KEY" not in text
    assert "pfx" not in text.lower()


def test_keyvault_requires_bearer_token_by_default(monkeypatch) -> None:
    monkeypatch.delenv("KEYVAULT_ALLOW_ANONYMOUS", raising=False)
    app = create_app(config=GatewayConfig(allow_anonymous=True))

    with TestClient(app) as client:
        missing = client.get("/keyvault/secrets")
        malformed = client.get("/keyvault/secrets", headers={"Authorization": "Bearer not-a-jwt"})
        expired = client.get("/keyvault/secrets", headers={"Authorization": f"Bearer {_token(exp_delta=-1)}"})

    assert missing.status_code == 401
    assert malformed.status_code == 401
    assert expired.status_code == 401


def test_keyvault_can_run_in_explicit_anonymous_mode(monkeypatch) -> None:
    monkeypatch.setenv("KEYVAULT_ALLOW_ANONYMOUS", "true")
    app = create_app(config=GatewayConfig(allow_anonymous=True))

    with TestClient(app) as client:
        resp = client.get("/keyvault/secrets")

    assert resp.status_code == 200
    assert resp.json() == {"value": []}


def test_keyvault_secret_lifecycle_masks_list_values(monkeypatch) -> None:
    monkeypatch.delenv("KEYVAULT_ALLOW_ANONYMOUS", raising=False)
    app = create_app(config=GatewayConfig(allow_anonymous=True))

    with TestClient(app) as client:
        created = client.put("/keyvault/secrets/api-secret", headers=_headers(), json={"value": "first"})
        updated = client.put("/keyvault/secrets/api-secret", headers=_headers(), json={"value": "second"})
        latest = client.get("/keyvault/secrets/api-secret", headers=_headers())
        versioned = client.get(
            f"/keyvault/secrets/api-secret/{created.json()['id'].rsplit('/', 1)[-1]}", headers=_headers()
        )
        listed = client.get("/keyvault/secrets", headers=_headers())
        deleted = client.delete("/keyvault/secrets/api-secret", headers=_headers())

    assert created.status_code == 200
    assert updated.status_code == 200
    assert latest.json()["value"] == "second"
    assert versioned.json()["value"] == "first"
    assert listed.status_code == 200
    assert listed.json()["value"][0]["id"].endswith("/secrets/api-secret")
    assert "value" not in listed.json()["value"][0]
    assert deleted.json()["deleted"] is True


def test_keyvault_imports_pem_certificate_without_leaking_private_material(monkeypatch) -> None:
    monkeypatch.delenv("KEYVAULT_ALLOW_ANONYMOUS", raising=False)
    cert_pem, key_pem, _pfx = _certificate()
    app = create_app(config=GatewayConfig(allow_anonymous=True))

    with TestClient(app) as client:
        imported = client.put(
            "/keyvault/certificates/platform-gateway",
            headers=_headers(),
            json={"pem": cert_pem, "private_key": key_pem},
        )
        latest = client.get("/keyvault/certificates/platform-gateway", headers=_headers())
        listed = client.get("/keyvault/certificates", headers=_headers())
        backing_secret = client.get(
            f"/keyvault/certificates/platform-gateway/{imported.json()['id'].rsplit('/', 1)[-1]}/secret",
            headers=_headers(),
        )

    assert imported.status_code == 200
    body = latest.json()
    assert body["subject"] == "O=Platform Local,CN=demo.platform.local"
    assert body["issuer"] == "O=Platform Local,CN=demo.platform.local"
    assert sorted(body["dns_names"]) == ["demo.127.0.0.1.sslip.io", "demo.platform.local"]
    assert body["contentType"] == "application/x-pem-file"
    assert body["cer"]
    assert body["x5t"]
    _assert_no_private_material(body)
    _assert_no_private_material(listed.json())
    assert "PRIVATE KEY" in backing_secret.json()["value"]


def test_keyvault_imports_pfx_certificate(monkeypatch) -> None:
    monkeypatch.delenv("KEYVAULT_ALLOW_ANONYMOUS", raising=False)
    _cert_pem, _key_pem, pfx = _certificate()
    app = create_app(config=GatewayConfig(allow_anonymous=True))

    with TestClient(app) as client:
        imported = client.put(
            "/keyvault/certificates/pkcs12-cert",
            headers=_headers(),
            json={"pfx": base64.b64encode(pfx).decode("ascii"), "password": "password"},
        )
        latest = client.get("/keyvault/certificates/pkcs12-cert", headers=_headers())
        backing_secret = client.get(
            f"/keyvault/certificates/pkcs12-cert/{imported.json()['id'].rsplit('/', 1)[-1]}/secret",
            headers=_headers(),
        )

    assert imported.status_code == 200
    assert latest.json()["contentType"] == "application/x-pkcs12"
    assert latest.json()["subject"] == "O=Platform Local,CN=demo.platform.local"
    _assert_no_private_material(latest.json())
    assert backing_secret.json()["contentType"] == "application/x-pkcs12"
    assert backing_secret.json()["value"] == base64.b64encode(pfx).decode("ascii")


def test_named_value_resolves_local_keyvault_secret_and_preserves_env_override(monkeypatch, tmp_path: Path) -> None:
    store_path = tmp_path / "keyvault.json"
    monkeypatch.setenv("KEYVAULT_STORE_PATH", str(store_path))
    app = create_app(config=GatewayConfig(allow_anonymous=True))

    with TestClient(app) as client:
        created = client.put("/keyvault/secrets/api-secret", headers=_headers(), json={"value": "from-vault"})

    cfg = GatewayConfig(
        named_values={
            "api-secret": NamedValueConfig(
                secret=True,
                value_from_key_vault=KeyVaultNamedValueConfig(secret_id=created.json()["id"]),
            )
        }
    )
    resolved = resolve_named_value(cfg, "api-secret")
    assert resolved is not None
    assert resolved.value == "from-vault"
    assert resolved.source == "key_vault"

    monkeypatch.setenv("APIM_NAMED_VALUE_API_SECRET", "from-env")
    overridden = resolve_named_value(cfg, "api-secret")
    assert overridden is not None
    assert overridden.value == "from-env"
    assert overridden.source == "env"
