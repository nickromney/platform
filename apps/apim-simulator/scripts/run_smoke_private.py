from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path

PINNED_HTTPX = "httpx==0.28.1"
PINNED_MCP = "mcp==1.26.0"


def main() -> None:
    site_packages_path = Path("/run/smoke/site-packages")
    repo_root = Path(__file__).resolve().parent.parent
    site_packages_path.mkdir(parents=True, exist_ok=True)

    subprocess.run(
        [
            sys.executable,
            "-m",
            "pip",
            "install",
            "--disable-pip-version-check",
            "--no-cache-dir",
            "-q",
            "--target",
            str(site_packages_path),
            PINNED_HTTPX,
            PINNED_MCP,
        ],
        check=True,
    )

    env = os.environ.copy()
    existing_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = (
        f"{repo_root}{os.pathsep}{site_packages_path}{os.pathsep}{existing_pythonpath}"
        if existing_pythonpath
        else f"{repo_root}{os.pathsep}{site_packages_path}"
    )

    subprocess.run(
        [sys.executable, "scripts/smoke_private.py"],
        check=True,
        cwd=repo_root,
        env=env,
    )


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.returncode) from exc
