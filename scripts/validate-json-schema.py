#!/usr/bin/env python3
"""Small JSON Schema validator for repo-local contract smoke tests."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def fail(message: str) -> None:
    print(f"FAIL {message}", file=sys.stderr)
    raise SystemExit(1)


def load_json(path: str) -> object:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except Exception as exc:  # pragma: no cover - command-line diagnostics
        fail(f"could not read JSON {path}: {exc}")


def require_keys(schema: dict, payload: object, path: str = "$") -> None:
    if not isinstance(payload, dict):
        fail(f"{path} is not an object")

    for key in schema.get("required", []):
        if key not in payload:
            fail(f"{path}.{key} is required")

    const_props = schema.get("properties", {})
    for key, prop_schema in const_props.items():
        if key in payload and isinstance(prop_schema, dict) and "const" in prop_schema:
            if payload[key] != prop_schema["const"]:
                fail(f"{path}.{key} must equal {prop_schema['const']!r}")


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("Usage: validate-json-schema.py SCHEMA.json PAYLOAD.json", file=sys.stderr)
        return 2

    schema = load_json(argv[1])
    payload = load_json(argv[2])
    if not isinstance(schema, dict):
        fail("schema must be a JSON object")
    require_keys(schema, payload)
    print(f"OK   {argv[2]} validates against {argv[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
