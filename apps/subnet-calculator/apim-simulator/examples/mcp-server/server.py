from __future__ import annotations

import os

from mcp.server.fastmcp import FastMCP

mcp = FastMCP(
    "APIM Simulator Demo MCP Server",
    instructions="Minimal streamable HTTP MCP server used to exercise the APIM simulator.",
    host="0.0.0.0",
    port=int(os.getenv("PORT", "8080")),
    streamable_http_path="/mcp",
    json_response=True,
    stateless_http=True,
)


@mcp.tool()
def add_numbers(a: int, b: int) -> dict[str, int]:
    """Add two integers and return the sum."""
    return {"sum": a + b}


@mcp.tool()
def uppercase(text: str) -> str:
    """Convert text to uppercase."""
    return text.upper()


if __name__ == "__main__":
    mcp.run(transport="streamable-http")
