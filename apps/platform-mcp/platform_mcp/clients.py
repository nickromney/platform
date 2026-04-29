from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import httpx


@dataclass(frozen=True)
class ApiClient:
    base_url: str
    timeout_seconds: float = 10
    bearer_token: str | None = None

    async def get(self, path: str) -> dict[str, Any]:
        return await self._request("GET", path)

    async def post(self, path: str, payload: dict[str, Any]) -> dict[str, Any]:
        return await self._request("POST", path, payload)

    async def _request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        headers = {"accept": "application/json"}
        if payload is not None:
            headers["content-type"] = "application/json"
        if self.bearer_token:
            headers["authorization"] = f"Bearer {self.bearer_token}"

        async with httpx.AsyncClient(base_url=self.base_url.rstrip("/"), timeout=self.timeout_seconds) as client:
            response = await client.request(method, path, json=payload, headers=headers)
            response.raise_for_status()
            if not response.content:
                return {}
            return response.json()
