from __future__ import annotations

from fastapi import FastAPI

from app.telemetry import configure_observability, instrument_fastapi_app, set_current_span_attributes

SERVICE_NAME = "hello-api"
SERVICE_VERSION = "0.2.0"

telemetry = configure_observability(service_name=SERVICE_NAME, service_version=SERVICE_VERSION)

app = FastAPI(title="Hello API", version=SERVICE_VERSION)


@app.get("/api/health")
async def health() -> dict[str, str]:
    set_current_span_attributes(**{"hello.operation": "health"})
    telemetry.logger.info("health checked", extra={"event.name": "hello.health"})
    return {"status": "ok", "service": SERVICE_NAME}


@app.get("/api/hello")
async def hello(name: str = "world") -> dict[str, str]:
    set_current_span_attributes(**{"hello.operation": "hello", "hello.name": name})
    telemetry.logger.info(
        "hello requested",
        extra={
            "event.name": "hello.requested",
            "hello.name": name,
        },
    )
    return {"message": f"hello, {name}"}


instrument_fastapi_app(app, telemetry)
