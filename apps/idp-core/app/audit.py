import json
from datetime import UTC, datetime
from pathlib import Path
from uuid import uuid4

from app.models import AuditRecord


class AuditWriter:
    def __init__(self, path: Path) -> None:
        self.path = path

    def write(self, *, event: str, runtime: str, workflow: str, request: dict[str, object]) -> AuditRecord:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        record = {
            "id": str(uuid4()),
            "request_id": str(uuid4()),
            "timestamp": datetime.now(UTC).isoformat(),
            "event": event,
            "action": event,
            "actor": "local",
            "runtime": runtime,
            "workflow": workflow,
            "dry_run": bool(request.get("dry_run", True)),
            "result": "planned",
            "request": request,
        }
        with self.path.open("a", encoding="utf-8") as audit_file:
            audit_file.write(json.dumps(record, separators=(",", ":"), sort_keys=True))
            audit_file.write("\n")
        return AuditRecord(id=record["id"], event=event, runtime=runtime)
