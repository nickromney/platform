from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path


def docker_config_path() -> Path:
    explicit_path = os.getenv("DOCKER_CONFIG_PATH")
    if explicit_path:
        return Path(explicit_path)

    docker_config_dir = os.getenv("DOCKER_CONFIG")
    if docker_config_dir:
        return Path(docker_config_dir) / "config.json"

    return Path.home() / ".docker" / "config.json"


def candidate_keys(registry: str) -> list[str]:
    if registry == "dhi.io":
        return ["dhi.io", "https://dhi.io", "https://dhi.io/"]
    if registry in {"docker.io", "index.docker.io"}:
        return [
            "docker.io",
            "https://docker.io",
            "https://docker.io/",
            "index.docker.io",
            "https://index.docker.io/v1/",
            "https://index.docker.io/v1",
            "https://index.docker.io/v1/access-token",
            "https://index.docker.io/v1/refresh-token",
        ]
    return [registry, f"https://{registry}", f"https://{registry}/"]


def login_hint(registry: str) -> str:
    return "docker login" if registry in {"docker.io", "index.docker.io"} else f"docker login {registry}"


def helper_name_for_registry(config: dict, keys: list[str]) -> str | None:
    cred_helpers = config.get("credHelpers") or {}
    for key in keys:
        helper_name = cred_helpers.get(key)
        if helper_name:
            return str(helper_name)

    creds_store = config.get("credsStore")
    if creds_store:
        return str(creds_store)

    return None


def helper_contains_registry(helper_bin: str, keys: list[str]) -> bool:
    result = subprocess.run(
        [helper_bin, "list"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return False

    try:
        listing = json.loads(result.stdout)
    except json.JSONDecodeError:
        return False

    return any(key in listing for key in keys)


def main(argv: list[str]) -> int:
    if len(argv) not in {2, 3}:
        print(
            "Usage: check_docker_registry_auth.py <registry> [display-name]",
            file=sys.stderr,
        )
        return 2

    registry = argv[1]
    display_name = argv[2] if len(argv) == 3 else registry
    keys = candidate_keys(registry)
    config_path = docker_config_path()

    if not config_path.is_file():
        print(
            f"WARN {display_name} credentials not found because Docker config is missing at {config_path} "
            f"(run: {login_hint(registry)})",
            file=sys.stderr,
        )
        return 1

    try:
        config = json.loads(config_path.read_text())
    except json.JSONDecodeError:
        print(f"WARN Docker config at {config_path} is not valid JSON", file=sys.stderr)
        return 1

    helper_name = helper_name_for_registry(config, keys)
    if helper_name:
        helper_bin = f"docker-credential-{helper_name}"
        if shutil.which(helper_bin) is None:
            print(
                f"WARN {display_name} uses {helper_bin}, but it is not available on PATH",
                file=sys.stderr,
            )
            return 1
        if helper_contains_registry(helper_bin, keys):
            print(f"OK   {display_name} credentials found via {helper_bin}")
            return 0
        print(
            f"WARN {display_name} credentials not found via {helper_bin} (run: {login_hint(registry)})",
            file=sys.stderr,
        )
        return 1

    auths = config.get("auths") or {}
    if any(key in auths for key in keys):
        print(f"OK   {display_name} credentials found in {config_path.name}")
        return 0

    print(
        f"WARN {display_name} credentials not found in Docker auth config (run: {login_hint(registry)})",
        file=sys.stderr,
    )
    return 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
