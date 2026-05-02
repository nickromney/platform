from __future__ import annotations

import base64
import hashlib
import json
import os
import time
import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

from cryptography import x509
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.serialization import pkcs12
from fastapi import HTTPException, Request
from pydantic import BaseModel, Field

DEFAULT_VAULT_HOST = "local-keyvault.vault.azure.net"


class SecretSetRequest(BaseModel):
    value: str
    attributes: dict[str, Any] = Field(default_factory=dict)


class CertificateImportRequest(BaseModel):
    pem: str | None = None
    private_key: str | None = None
    pfx: str | None = None
    password: str | None = None
    attributes: dict[str, Any] = Field(default_factory=dict)


class KeyVaultStore:
    def __init__(self, *, path: Path | None = None, vault_host: str = DEFAULT_VAULT_HOST) -> None:
        self.path = path
        self.vault_host = vault_host
        self.secrets: dict[str, list[dict[str, Any]]] = {}
        self.certificates: dict[str, list[dict[str, Any]]] = {}
        self._load()

    @classmethod
    def from_env(cls) -> KeyVaultStore:
        raw_path = os.getenv("KEYVAULT_STORE_PATH", "").strip()
        vault_host = os.getenv("KEYVAULT_HOST", DEFAULT_VAULT_HOST).strip() or DEFAULT_VAULT_HOST
        return cls(path=Path(raw_path) if raw_path else None, vault_host=vault_host)

    def _load(self) -> None:
        if self.path is None or not self.path.exists():
            return
        payload = json.loads(self.path.read_text(encoding="utf-8") or "{}")
        self.secrets = payload.get("secrets") or {}
        self.certificates = payload.get("certificates") or {}

    def _save(self) -> None:
        if self.path is None:
            return
        self.path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "secrets": self.secrets,
            "certificates": self.certificates,
        }
        self.path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")

    def secret_id(self, name: str, version: str | None = None) -> str:
        suffix = f"/{version}" if version else ""
        return f"https://{self.vault_host}/secrets/{name}{suffix}"

    def certificate_id(self, name: str, version: str | None = None) -> str:
        suffix = f"/{version}" if version else ""
        return f"https://{self.vault_host}/certificates/{name}{suffix}"

    def set_secret(self, name: str, value: str, *, enabled: bool = True) -> dict[str, Any]:
        version = uuid.uuid4().hex
        now = _now()
        entry = {
            "id": self.secret_id(name, version),
            "name": name,
            "version": version,
            "value": value,
            "attributes": {"enabled": enabled, "created": now, "updated": now, "deleted": False},
        }
        self.secrets.setdefault(name, []).append(entry)
        self._save()
        return entry

    def get_secret(self, name: str, version: str | None = None) -> dict[str, Any]:
        entry = _select_version(self.secrets.get(name, []), version)
        if entry is None:
            raise HTTPException(status_code=404, detail="Secret not found")
        return entry

    def delete_secret(self, name: str) -> None:
        versions = self.secrets.get(name)
        if not versions:
            raise HTTPException(status_code=404, detail="Secret not found")
        now = _now()
        for entry in versions:
            entry.setdefault("attributes", {})["deleted"] = True
            entry["attributes"]["updated"] = now
        self._save()

    def import_certificate(self, name: str, body: CertificateImportRequest) -> dict[str, Any]:
        version = uuid.uuid4().hex
        now = _now()
        enabled = bool(body.attributes.get("enabled", True))

        if body.pfx:
            pfx_bytes = base64.b64decode(body.pfx)
            password = body.password.encode("utf-8") if body.password is not None else None
            key, cert, extra = pkcs12.load_key_and_certificates(pfx_bytes, password)
            if cert is None:
                raise HTTPException(status_code=400, detail="PFX bundle does not contain a certificate")
            cert_pem = cert.public_bytes(serialization.Encoding.PEM).decode("utf-8")
            private_material = body.pfx
            content_type = "application/x-pkcs12"
            chain = [item.public_bytes(serialization.Encoding.PEM).decode("utf-8") for item in extra or []]
            key_pem = (
                key.private_bytes(
                    serialization.Encoding.PEM,
                    serialization.PrivateFormat.PKCS8,
                    serialization.NoEncryption(),
                ).decode("utf-8")
                if key is not None
                else None
            )
        elif body.pem:
            cert = x509.load_pem_x509_certificate(body.pem.encode("utf-8"))
            cert_pem = body.pem
            key_pem = body.private_key
            private_material = "\n".join(part for part in [body.pem, body.private_key] if part)
            content_type = "application/x-pem-file"
            chain = []
        else:
            raise HTTPException(status_code=400, detail="Certificate import requires pem or pfx")

        der = cert.public_bytes(serialization.Encoding.DER)
        x5t = base64.urlsafe_b64encode(hashlib.sha1(der).digest()).decode("ascii").rstrip("=")
        dns_names: list[str] = []
        try:
            san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName).value
            dns_names = list(san.get_values_for_type(x509.DNSName))
        except x509.ExtensionNotFound:
            pass

        entry = {
            "id": self.certificate_id(name, version),
            "kid": f"https://{self.vault_host}/keys/{name}/{version}",
            "sid": self.secret_id(name, version),
            "name": name,
            "version": version,
            "cer": base64.b64encode(der).decode("ascii"),
            "x5t": x5t,
            "subject": cert.subject.rfc4514_string(),
            "issuer": cert.issuer.rfc4514_string(),
            "dns_names": dns_names,
            "serial_number": format(cert.serial_number, "x"),
            "not_before": _dt(cert.not_valid_before_utc),
            "not_after": _dt(cert.not_valid_after_utc),
            "contentType": content_type,
            "attributes": {
                "enabled": enabled,
                "created": now,
                "updated": now,
                "deleted": False,
                "nbf": int(cert.not_valid_before_utc.timestamp()),
                "exp": int(cert.not_valid_after_utc.timestamp()),
            },
            "_secret": {
                "value": private_material,
                "contentType": content_type,
                "certificate_pem": cert_pem,
                "private_key_pem": key_pem,
                "chain": chain,
            },
        }
        self.certificates.setdefault(name, []).append(entry)
        self._save()
        return entry

    def get_certificate(self, name: str, version: str | None = None) -> dict[str, Any]:
        entry = _select_version(self.certificates.get(name, []), version)
        if entry is None:
            raise HTTPException(status_code=404, detail="Certificate not found")
        return entry

    def delete_certificate(self, name: str) -> None:
        versions = self.certificates.get(name)
        if not versions:
            raise HTTPException(status_code=404, detail="Certificate not found")
        now = _now()
        for entry in versions:
            entry.setdefault("attributes", {})["deleted"] = True
            entry["attributes"]["updated"] = now
        self._save()


def _now() -> int:
    return int(time.time())


def _dt(value: datetime) -> str:
    return value.astimezone(UTC).isoformat().replace("+00:00", "Z")


def _select_version(entries: list[dict[str, Any]], version: str | None) -> dict[str, Any] | None:
    candidates = [entry for entry in entries if not entry.get("attributes", {}).get("deleted")]
    if version is not None:
        return next((entry for entry in candidates if entry.get("version") == version), None)
    enabled = [entry for entry in candidates if entry.get("attributes", {}).get("enabled", True)]
    return enabled[-1] if enabled else None


def _public_secret(entry: dict[str, Any], *, include_value: bool) -> dict[str, Any]:
    out = {
        "id": entry["id"],
        "attributes": entry.get("attributes", {}),
    }
    if include_value:
        out["value"] = entry["value"]
    return out


def _public_certificate(entry: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in entry.items() if not key.startswith("_")}


def require_keyvault_auth(request: Request) -> None:
    if os.getenv("KEYVAULT_ALLOW_ANONYMOUS", "").strip().lower() in {"1", "true", "yes", "on"}:
        return

    header = request.headers.get("authorization", "")
    if not header.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    token = header.split(" ", 1)[1].strip()
    parts = token.split(".")
    if len(parts) != 3 or not all(parts):
        raise HTTPException(status_code=401, detail="Invalid bearer token")
    try:
        payload_raw = parts[1] + "=" * (-len(parts[1]) % 4)
        payload = json.loads(base64.urlsafe_b64decode(payload_raw.encode("ascii")))
    except Exception as exc:
        raise HTTPException(status_code=401, detail="Invalid bearer token") from exc
    exp = payload.get("exp")
    if exp is not None and float(exp) < time.time():
        raise HTTPException(status_code=401, detail="Expired bearer token")


def register_keyvault_routes(app: Any) -> None:
    store = KeyVaultStore.from_env()
    app.state.keyvault_store = store

    @app.get("/keyvault/secrets", tags=["keyvault"])
    async def list_secrets(request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        return {
            "value": [
                {**_public_secret(entries[-1], include_value=False), "id": store.secret_id(entries[-1]["name"])}
                for entries in store.secrets.values()
                if entries
            ]
        }

    @app.put("/keyvault/secrets/{name}", tags=["keyvault"])
    async def set_secret(name: str, body: SecretSetRequest, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        entry = store.set_secret(name, body.value, enabled=bool(body.attributes.get("enabled", True)))
        return _public_secret(entry, include_value=True)

    @app.get("/keyvault/secrets/{name}", tags=["keyvault"])
    async def get_secret(name: str, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        return _public_secret(store.get_secret(name), include_value=True)

    @app.get("/keyvault/secrets/{name}/{version}", tags=["keyvault"])
    async def get_secret_version(name: str, version: str, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        return _public_secret(store.get_secret(name, version), include_value=True)

    @app.delete("/keyvault/secrets/{name}", tags=["keyvault"])
    async def delete_secret(name: str, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        store.delete_secret(name)
        return {"deleted": True, "id": store.secret_id(name)}

    @app.get("/keyvault/certificates", tags=["keyvault"])
    async def list_certificates(request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        return {
            "value": [
                _public_certificate(entries[-1])
                for entries in store.certificates.values()
                if entries and not entries[-1].get("attributes", {}).get("deleted")
            ]
        }

    @app.put("/keyvault/certificates/{name}", tags=["keyvault"])
    async def import_certificate(name: str, body: CertificateImportRequest, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        return _public_certificate(store.import_certificate(name, body))

    @app.get("/keyvault/certificates/{name}", tags=["keyvault"])
    async def get_certificate(name: str, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        return _public_certificate(store.get_certificate(name))

    @app.get("/keyvault/certificates/{name}/{version}", tags=["keyvault"])
    async def get_certificate_version(name: str, version: str, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        return _public_certificate(store.get_certificate(name, version))

    @app.get("/keyvault/certificates/{name}/{version}/secret", tags=["keyvault"])
    async def get_certificate_secret(name: str, version: str, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        entry = store.get_certificate(name, version)
        secret = entry["_secret"]
        return {
            "id": entry["sid"],
            "value": secret["value"],
            "contentType": secret["contentType"],
            "attributes": entry.get("attributes", {}),
        }

    @app.delete("/keyvault/certificates/{name}", tags=["keyvault"])
    async def delete_certificate(name: str, request: Request) -> dict[str, Any]:
        require_keyvault_auth(request)
        store.delete_certificate(name)
        return {"deleted": True, "id": store.certificate_id(name)}


def resolve_secret_id_from_store(secret_id: str) -> str | None:
    parsed = urlparse(secret_id)
    parts = [part for part in parsed.path.split("/") if part]
    if len(parts) < 2 or parts[0] != "secrets":
        return None
    store = KeyVaultStore.from_env()
    version = parts[2] if len(parts) > 2 else None
    try:
        return str(store.get_secret(parts[1], version)["value"])
    except HTTPException:
        return None
