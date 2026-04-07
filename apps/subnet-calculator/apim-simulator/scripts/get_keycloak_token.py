#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys

import httpx


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Fetch a Keycloak access token for the local APIM simulator example.")
    parser.add_argument("--base-url", default="http://localhost:8180")
    parser.add_argument("--realm", default="subnet-calculator")
    parser.add_argument("--client-id", default="frontend-app")
    parser.add_argument("--username", default="demo@dev.test")
    parser.add_argument("--password", default="demo-password")
    parser.add_argument(
        "--json", action="store_true", help="Print the full token payload instead of only the access token."
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    token_url = f"{args.base_url.rstrip('/')}/realms/{args.realm}/protocol/openid-connect/token"
    form = {
        "grant_type": "password",
        "client_id": args.client_id,
        "username": args.username,
        "password": args.password,
    }

    with httpx.Client(timeout=20.0) as client:
        response = client.post(token_url, data=form)

    try:
        response.raise_for_status()
    except httpx.HTTPStatusError:
        sys.stderr.write(response.text + "\n")
        return 1

    payload = response.json()
    if args.json:
        print(json.dumps(payload, indent=2))
    else:
        print(payload["access_token"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
