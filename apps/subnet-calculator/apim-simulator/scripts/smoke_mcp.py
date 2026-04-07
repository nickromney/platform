#!/usr/bin/env python3
from __future__ import annotations

import asyncio
import os
import sys
import traceback
from pathlib import Path

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamable_http_client

DEFAULT_CA_CERT = Path(__file__).resolve().parent.parent / "examples" / "edge" / "certs" / "dev-root-ca.crt"
DEFAULT_ATTEMPTS = int(os.getenv("SMOKE_MCP_ATTEMPTS", "20"))
DEFAULT_DELAY_SECONDS = float(os.getenv("SMOKE_MCP_RETRY_DELAY_SECONDS", "1"))


def resolve_tls_verify(
    *,
    default_ca: Path | None = None,
    ca_env: str,
    verify_env: str,
    insecure_env: str,
) -> bool | str:
    insecure = os.getenv(insecure_env, "false").lower() == "true"
    if insecure:
        return False

    explicit_ca = os.getenv(ca_env, "").strip()
    if explicit_ca:
        return explicit_ca

    legacy_verify = os.getenv(verify_env, "").strip()
    if legacy_verify and legacy_verify.lower() not in {"true", "false"}:
        return legacy_verify
    if legacy_verify.lower() == "false":
        return False

    if default_ca is not None and default_ca.exists():
        return str(default_ca)

    return True


async def run(url: str, subscription_key: str, *, verify: bool | str = True) -> None:
    async with httpx.AsyncClient(
        headers={"Ocp-Apim-Subscription-Key": subscription_key},
        timeout=httpx.Timeout(30.0, read=300.0),
        verify=verify,
    ) as client:
        async with streamable_http_client(
            url,
            http_client=client,
        ) as (read_stream, write_stream, _):
            async with ClientSession(read_stream, write_stream) as session:
                init = await session.initialize()
                tools = await session.list_tools()
                names = [tool.name for tool in tools.tools]
                if "add_numbers" not in names:
                    raise RuntimeError(f"add_numbers tool missing from {names}")

                result = await session.call_tool("add_numbers", {"a": 2, "b": 3})
                text_values: list[str] = []
                for item in result.content:
                    text = getattr(item, "text", None)
                    if text is not None:
                        text_values.append(text)

                if not text_values or "5" not in " ".join(text_values):
                    raise RuntimeError(f"unexpected add_numbers result: {result}")

                print("MCP smoke passed")
                print(f"- server: {init.serverInfo.name}")
                print(f"- tools: {', '.join(names)}")
                print(f"- add_numbers: {' | '.join(text_values)}")


async def run_with_retry(
    url: str,
    subscription_key: str,
    *,
    verify: bool | str = True,
    attempts: int = DEFAULT_ATTEMPTS,
    delay_seconds: float = DEFAULT_DELAY_SECONDS,
) -> None:
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            await run(url=url, subscription_key=subscription_key, verify=verify)
            return
        except Exception as exc:
            last_error = exc
            if attempt == attempts:
                raise
            await asyncio.sleep(delay_seconds)

    if last_error is not None:
        raise last_error


def main() -> int:
    url = os.getenv("SMOKE_MCP_URL", "http://localhost:8000/mcp")
    subscription_key = os.getenv("SMOKE_MCP_SUBSCRIPTION_KEY", "mcp-demo-key")
    verify = resolve_tls_verify(
        default_ca=DEFAULT_CA_CERT if url.startswith("https://") else None,
        ca_env="SMOKE_MCP_CA_CERT",
        verify_env="SMOKE_MCP_VERIFY_TLS",
        insecure_env="SMOKE_MCP_INSECURE_SKIP_VERIFY",
    )
    try:
        asyncio.run(run_with_retry(url=url, subscription_key=subscription_key, verify=verify))
        return 0
    except Exception as exc:
        sys.stderr.write(f"MCP smoke failed: {exc}\n")
        traceback.print_exc()
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
