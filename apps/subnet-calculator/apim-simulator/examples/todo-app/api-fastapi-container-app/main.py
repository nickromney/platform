from __future__ import annotations

import logging
import time
import uuid
from dataclasses import dataclass
from itertools import count
from threading import Lock
from typing import Annotated, Any

from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel, StringConstraints

from app.telemetry import (
    ObservabilityRuntime,
    configure_observability,
    get_correlation_id,
    instrument_fastapi_app,
    reset_correlation_id,
    set_correlation_id,
    set_current_span_attributes,
)

TodoTitle = Annotated[str, StringConstraints(strip_whitespace=True, min_length=1, max_length=120)]

TODO_SERVICE_NAME = "todo-api"
TODO_SERVICE_VERSION = "0.2.0"
logger = logging.getLogger(TODO_SERVICE_NAME)
_TODO_METRICS: TodoMetrics | None = None


@dataclass(frozen=True)
class TodoMetrics:
    requests: Any
    request_duration: Any
    todos_created: Any
    todos_updated: Any


def _get_todo_metrics(telemetry: ObservabilityRuntime) -> TodoMetrics:
    global _TODO_METRICS
    if _TODO_METRICS is not None:
        return _TODO_METRICS

    meter = telemetry.meter
    _TODO_METRICS = TodoMetrics(
        requests=meter.create_counter(
            "todo.api.requests",
            description="Count of requests handled by the todo API",
        ),
        request_duration=meter.create_histogram(
            "todo.api.request.duration",
            unit="s",
            description="End-to-end todo API request duration",
        ),
        todos_created=meter.create_counter(
            "todo.api.todos.created",
            description="Todos created by the toy API",
        ),
        todos_updated=meter.create_counter(
            "todo.api.todos.updated",
            description="Todo update operations handled by the toy API",
        ),
    )
    return _TODO_METRICS


def _request_route_label(request: Request) -> str:
    route = request.scope.get("route")
    route_path = getattr(route, "path", None)
    if route_path:
        return str(route_path)
    return request.url.path


def _access_log_fields(request: Request, *, status_code: int, duration_seconds: float) -> dict[str, Any]:
    return {
        "event.name": "http.request.completed",
        "http.request.method": request.method,
        "url.path": request.url.path,
        "http.route": _request_route_label(request),
        "http.response.status_code": status_code,
        "duration_ms": round(duration_seconds * 1000, 3),
        "correlation_id": get_correlation_id() or getattr(request.state, "correlation_id", None),
    }


class Todo(BaseModel):
    id: int
    title: str
    completed: bool = False


class CreateTodoRequest(BaseModel):
    title: TodoTitle


class UpdateTodoRequest(BaseModel):
    completed: bool


class TodoStore:
    def __init__(self) -> None:
        self._lock = Lock()
        self._ids = count(1)
        self._todos: dict[int, Todo] = {}

    def list(self) -> list[Todo]:
        with self._lock:
            return [todo.model_copy(deep=True) for todo in self._todos.values()]

    def create(self, title: str) -> Todo:
        with self._lock:
            todo = Todo(id=next(self._ids), title=title, completed=False)
            self._todos[todo.id] = todo
            return todo.model_copy(deep=True)

    def update(self, todo_id: int, completed: bool) -> Todo:
        with self._lock:
            todo = self._todos.get(todo_id)
            if todo is None:
                raise KeyError(todo_id)
            todo.completed = completed
            return todo.model_copy(deep=True)


def create_app() -> FastAPI:
    telemetry = configure_observability(service_name=TODO_SERVICE_NAME, service_version=TODO_SERVICE_VERSION)
    store = TodoStore()

    app = FastAPI(title="Todo API", version=TODO_SERVICE_VERSION)
    app.state.telemetry = telemetry
    app.state.todo_metrics = _get_todo_metrics(telemetry)

    @app.middleware("http")
    async def observe_requests(request: Request, call_next):
        correlation_id = request.headers.get("x-correlation-id") or f"corr-{uuid.uuid4()}"
        request.state.correlation_id = correlation_id
        token = set_correlation_id(correlation_id)
        start = time.perf_counter()

        try:
            response = await call_next(request)
        except Exception:
            duration_seconds = time.perf_counter() - start
            app.state.todo_metrics.requests.add(
                1,
                {
                    "http.request.method": request.method,
                    "http.response.status_code": 500,
                    "http.route": _request_route_label(request),
                },
            )
            app.state.todo_metrics.request_duration.record(
                duration_seconds,
                {
                    "http.request.method": request.method,
                    "http.response.status_code": 500,
                    "http.route": _request_route_label(request),
                },
            )
            telemetry.logger.exception(
                "request failed",
                extra=_access_log_fields(request, status_code=500, duration_seconds=duration_seconds),
            )
            raise
        else:
            response.headers.setdefault("x-correlation-id", correlation_id)
            duration_seconds = time.perf_counter() - start
            attrs = {
                "http.request.method": request.method,
                "http.response.status_code": response.status_code,
                "http.route": _request_route_label(request),
            }
            app.state.todo_metrics.requests.add(1, attrs)
            app.state.todo_metrics.request_duration.record(duration_seconds, attrs)
            telemetry.logger.info(
                "request completed",
                extra=_access_log_fields(request, status_code=response.status_code, duration_seconds=duration_seconds),
            )
            return response
        finally:
            reset_correlation_id(token)

    @app.get("/api/health")
    async def health() -> dict[str, str]:
        set_current_span_attributes(**{"todo.operation": "health"})
        return {"status": "ok", "service": TODO_SERVICE_NAME}

    @app.get("/api/todos")
    async def list_todos() -> dict[str, list[Todo]]:
        set_current_span_attributes(**{"todo.operation": "list"})
        return {"items": store.list()}

    @app.post("/api/todos", status_code=201)
    async def create_todo(payload: CreateTodoRequest) -> Todo:
        set_current_span_attributes(**{"todo.operation": "create"})
        app.state.todo_metrics.todos_created.add(1, {"todo.operation": "create"})
        return store.create(payload.title)

    @app.patch("/api/todos/{todo_id}")
    async def update_todo(todo_id: int, payload: UpdateTodoRequest) -> Todo:
        set_current_span_attributes(**{"todo.operation": "update"})
        app.state.todo_metrics.todos_updated.add(
            1,
            {
                "todo.operation": "update",
                "todo.completed": payload.completed,
            },
        )
        try:
            return store.update(todo_id, payload.completed)
        except KeyError as exc:
            raise HTTPException(status_code=404, detail="Todo not found") from exc

    instrument_fastapi_app(app, telemetry)
    return app


app = create_app()
