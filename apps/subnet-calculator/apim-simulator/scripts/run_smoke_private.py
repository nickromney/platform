from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def main() -> None:
    site_packages_path = Path("/run/smoke/site-packages")
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
            "httpx",
            "mcp",
        ],
        check=True,
    )

    env = os.environ.copy()
    existing_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = (
        f"{site_packages_path}{os.pathsep}{existing_pythonpath}" if existing_pythonpath else str(site_packages_path)
    )

    subprocess.run(
        [sys.executable, "scripts/smoke_private.py"],
        check=True,
        env=env,
    )


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        raise SystemExit(exc.returncode) from exc
