from __future__ import annotations

import json
import re
import sys
from pathlib import Path

SEMVER_RE = re.compile(r"^\d+\.\d+\.\d+$")
ROOT = Path(__file__).resolve().parent.parent


def replace_once(path: Path, pattern: str, replacement: str) -> None:
    original = path.read_text(encoding="utf-8")
    updated, count = re.subn(pattern, replacement, original, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"expected one replacement in {path}")
    path.write_text(updated, encoding="utf-8")


def update_har(path: Path, version: str) -> None:
    payload = json.loads(path.read_text(encoding="utf-8"))
    payload["log"]["creator"]["version"] = version
    path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2 or not SEMVER_RE.fullmatch(sys.argv[1]):
        raise SystemExit("usage: bump_version.py X.Y.Z")

    version = sys.argv[1]

    replace_once(ROOT / "pyproject.toml", r'^version = "[^"]+"$', f'version = "{version}"')
    replace_once(ROOT / "app/main.py", r'^APIM_SERVICE_VERSION = "[^"]+"$', f'APIM_SERVICE_VERSION = "{version}"')
    replace_once(ROOT / "examples/hello-api/main.py", r'^SERVICE_VERSION = "[^"]+"$', f'SERVICE_VERSION = "{version}"')
    replace_once(
        ROOT / "examples/todo-app/api-fastapi-container-app/main.py",
        r'^TODO_SERVICE_VERSION = "[^"]+"$',
        f'TODO_SERVICE_VERSION = "{version}"',
    )
    update_har(ROOT / "examples/todo-app/api-clients/proxyman/todo-through-apim.har", version)


if __name__ == "__main__":
    main()
