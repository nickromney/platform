from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError
from urllib.request import Request, urlopen


class ApiError(RuntimeError):
    def __init__(self, *, status_code: int, response: str) -> None:
        super().__init__(f"HTTP {status_code}: {response}")
        self.status_code = status_code
        self.response = response


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
        return await asyncio.to_thread(self._request_sync, method, path, payload)

    def _request_sync(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        headers = {"accept": "application/json"}
        body = None
        if payload is not None:
            headers["content-type"] = "application/json"
            body = json.dumps(payload).encode("utf-8")
        if self.bearer_token:
            headers["authorization"] = f"Bearer {self.bearer_token}"

        request = Request(f"{self.base_url.rstrip('/')}{path}", data=body, headers=headers, method=method)
        try:
            with urlopen(request, timeout=self.timeout_seconds) as response:
                response_body = response.read()
        except HTTPError as exc:
            detail = exc.read().decode("utf-8", errors="replace")
            raise ApiError(status_code=exc.code, response=detail[:1000]) from exc

        if not response_body:
            return {}
        return json.loads(response_body.decode("utf-8"))
