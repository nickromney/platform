"""Regression tests for the container app dependency footprint."""

from __future__ import annotations

from pathlib import Path
import tomllib


APP_DIR = Path(__file__).resolve().parent.parent


def _dependencies() -> list[str]:
    project = tomllib.loads((APP_DIR / "pyproject.toml").read_text(encoding="utf-8"))
    return list(project["project"]["dependencies"])


def test_runtime_dependencies_use_explicit_fastapi_stack() -> None:
    """Keep the runtime stack small by avoiding the bundled FastAPI extras."""
    dependencies = _dependencies()

    assert "fastapi[standard]>=0.118.0" not in dependencies
    assert "uvicorn[standard]>=0.34.0" not in dependencies
    assert any(dep.startswith("fastapi>=") for dep in dependencies)
    assert any(dep.startswith("uvicorn>=") for dep in dependencies)


def test_runtime_dependencies_drop_unused_runtime_packages() -> None:
    """The container app should not install clients or settings helpers it does not use."""
    dependencies = _dependencies()
    source = "\n".join(
        (
            (APP_DIR / "app" / "cloudflare_ips.py").read_text(encoding="utf-8"),
            (APP_DIR / "app" / "main.py").read_text(encoding="utf-8"),
        )
    )

    assert not any(dep.startswith("pydantic-settings") for dep in dependencies)
    assert not any(dep.startswith("httpx") for dep in dependencies)
    assert not any(dep.startswith("opentelemetry-instrumentation-httpx") for dep in dependencies)
    assert "import httpx" not in source
    assert "HTTPXClientInstrumentor" not in source
