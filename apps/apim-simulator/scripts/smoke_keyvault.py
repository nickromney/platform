from __future__ import annotations

import base64
import json
import os
import time
from datetime import UTC, datetime, timedelta
from urllib.error import URLError
from urllib.request import Request, urlopen

import jwt
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

BASE_URL = os.getenv("KEYVAULT_BASE_URL", "http://127.0.0.1:8000").rstrip("/")


def _token() -> str:
    return jwt.encode(
        {"sub": "smoke", "exp": int(time.time()) + 300},
        "local-smoke-secret-for-keyvault-smoke-tests",
        algorithm="HS256",
    )


def _request(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = Request(
        f"{BASE_URL}{path}",
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {_token()}",
            "Accept": "application/json",
            "Content-Type": "application/json",
        },
    )
    with urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def _wait_for_health() -> None:
    deadline = time.time() + 60
    last_error: Exception | None = None
    while time.time() < deadline:
        try:
            health = _request("GET", "/apim/health")
            if health == {"status": "healthy"}:
                return
        except (ConnectionError, OSError, URLError) as exc:
            last_error = exc
        time.sleep(1)
    raise SystemExit(f"APIM simulator did not become healthy: {last_error}")


def _certificate() -> tuple[str, str]:
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    subject = issuer = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "keyvault-smoke.local")])
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(x509.random_serial_number())
        .not_valid_before(datetime.now(UTC) - timedelta(minutes=5))
        .not_valid_after(datetime.now(UTC) + timedelta(days=1))
        .add_extension(x509.SubjectAlternativeName([x509.DNSName("keyvault-smoke.local")]), critical=False)
        .sign(key, hashes.SHA256())
    )
    cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
    key_pem = key.private_bytes(
        serialization.Encoding.PEM,
        serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption(),
    ).decode("utf-8")
    return cert_pem, key_pem


def main() -> None:
    _wait_for_health()

    _request("PUT", "/keyvault/secrets/smoke-api-secret", {"value": "local-smoke-secret-value"})
    latest_secret = _request("GET", "/keyvault/secrets/smoke-api-secret")
    listed_secrets = _request("GET", "/keyvault/secrets")
    if latest_secret.get("value") != "local-smoke-secret-value":
        raise SystemExit("secret latest value did not round trip")
    if any("value" in item for item in listed_secrets.get("value", [])):
        raise SystemExit("secret list leaked values")

    cert_pem, key_pem = _certificate()
    cert = _request("PUT", "/keyvault/certificates/smoke-cert", {"pem": cert_pem, "private_key": key_pem})
    latest_cert = _request("GET", "/keyvault/certificates/smoke-cert")
    listed_certs = _request("GET", "/keyvault/certificates")
    backing_secret = _request("GET", f"/keyvault/certificates/smoke-cert/{cert['id'].rsplit('/', 1)[-1]}/secret")

    public_payload = json.dumps({"latest": latest_cert, "listed": listed_certs})
    if "PRIVATE KEY" in public_payload:
        raise SystemExit("certificate public endpoints leaked private key material")
    if latest_cert.get("subject") != "CN=keyvault-smoke.local":
        raise SystemExit(f"unexpected certificate subject: {latest_cert.get('subject')}")
    if base64.b64decode(latest_cert["cer"]).find(b"PRIVATE KEY") != -1:
        raise SystemExit("certificate DER unexpectedly contained private key marker")
    if "PRIVATE KEY" not in backing_secret.get("value", ""):
        raise SystemExit("certificate backing secret did not expose private material to authorized caller")

    print("Key Vault smoke passed")


if __name__ == "__main__":
    main()
