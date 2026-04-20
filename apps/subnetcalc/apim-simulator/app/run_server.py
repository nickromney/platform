from __future__ import annotations

import os
from pathlib import Path
from string import Template

import uvicorn


def _prepare_runtime_config() -> None:
    source = os.getenv("APIM_CONFIG_SOURCE_PATH", "").strip()
    target = os.getenv("APIM_CONFIG_PATH", "").strip()

    if not source or not target or source == target:
        return

    source_path = Path(source)
    if not source_path.exists():
        raise FileNotFoundError(f"APIM_CONFIG_SOURCE_PATH does not exist: {source_path}")

    target_path = Path(target)
    if target_path.exists():
        return

    rendered = source_path.read_text(encoding="utf-8")
    if os.getenv("APIM_CONFIG_TEMPLATE_SUBSTITUTE", "").strip().lower() in {"1", "true", "yes", "on"}:
        rendered = Template(rendered).safe_substitute(os.environ)

    target_path.parent.mkdir(parents=True, exist_ok=True)
    target_path.write_text(rendered, encoding="utf-8")


def main() -> None:
    _prepare_runtime_config()
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=int(os.getenv("PORT", "8000")),
        access_log=False,
    )


if __name__ == "__main__":
    main()
