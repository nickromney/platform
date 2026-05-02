from __future__ import annotations

import json
import os
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable


APP_STAGES = {"700", "800", "900", "950-local-idp"}
VARIANT_TARGETS = {
    "kubernetes/kind": "kind",
    "kubernetes/lima": "lima",
    "kubernetes/slicer": "slicer",
}


def variant_to_target(variant: str) -> str:
    return VARIANT_TARGETS.get(variant, variant.rsplit("/", 1)[-1] or "kind")


def stage_has_app_toggles(stage: str) -> bool:
    return stage in APP_STAGES


def stage_default(stage: str, app: str) -> bool:
    if stage == "950-local-idp":
        return app == "sentiment"
    return stage in {"700", "800", "900"}


def next_stages(variant: str, stage: str, action: str, succeeded: bool) -> list[str]:
    if not succeeded or action != "apply":
        return []
    stages_by_current = {
        "500": ["600", "900", "950-local-idp"],
        "600": ["700", "800", "900", "950-local-idp"],
        "700": ["800", "900", "950-local-idp"],
        "800": ["900", "950-local-idp"],
        "900": ["950-local-idp"],
    }
    stages = stages_by_current.get(stage, [])
    if variant_to_target(variant) != "kind":
        stages = [candidate for candidate in stages if candidate != "950-local-idp"]
    return stages


def build_workflow_args(payload: dict[str, Any], *, subcommand: str) -> list[str]:
    args = [
        subcommand,
        "--execute",
    ]
    if subcommand == "preview":
        args.extend(["--output", "json"])
    args.extend(
        [
            "--target",
            variant_to_target(str(payload.get("variant") or "kubernetes/kind")),
            "--stage",
            str(payload.get("stage") or "900"),
            "--action",
            str(payload.get("action") or "apply"),
        ]
    )
    if stage_has_app_toggles(str(payload.get("stage") or "900")):
        for app in ("sentiment", "subnetcalc"):
            value = payload.get(app)
            if value:
                args.extend(["--app", f"{app}={value}"])
    if payload.get("auto_approve"):
        args.append("--auto-approve")
    return args


def run_workflow_json(repo_root: Path, args: list[str]) -> tuple[int, str, str]:
    command = [str(repo_root / "scripts" / "platform-workflow.sh"), *args]
    result = subprocess.run(command, cwd=repo_root, text=True, capture_output=True, check=False)
    return result.returncode, result.stdout, result.stderr


@dataclass
class WorkflowJob:
    id: str
    payload: dict[str, Any]
    command: list[str]
    output: list[str] = field(default_factory=list)
    returncode: int | None = None
    started_at: float = field(default_factory=time.time)
    finished_at: float | None = None

    @property
    def running(self) -> bool:
        return self.returncode is None

    @property
    def succeeded(self) -> bool:
        return self.returncode == 0

    @property
    def text(self) -> str:
        return "\n".join(self.output)


class JobStore:
    def __init__(self, repo_root: Path):
        self.repo_root = repo_root
        self.jobs: dict[str, WorkflowJob] = {}
        self.lock = threading.Lock()

    def start(self, payload: dict[str, Any], on_finish: Callable[[str | None, int], None] | None = None) -> WorkflowJob:
        args = build_workflow_args(payload, subcommand="apply")
        job = WorkflowJob(
            id=uuid.uuid4().hex,
            payload=dict(payload),
            command=[str(self.repo_root / "scripts" / "platform-workflow.sh"), *args],
        )
        with self.lock:
            self.jobs[job.id] = job
        thread = threading.Thread(target=self._run, args=(job, on_finish), daemon=True)
        thread.start()
        return job

    def get(self, job_id: str) -> WorkflowJob | None:
        with self.lock:
            return self.jobs.get(job_id)

    def _append(self, job: WorkflowJob, line: str) -> None:
        with self.lock:
            job.output.append(line.rstrip("\n"))

    def _finish(self, job: WorkflowJob, returncode: int) -> None:
        with self.lock:
            job.returncode = returncode
            job.finished_at = time.time()

    def _run(self, job: WorkflowJob, on_finish: Callable[[str | None, int], None] | None = None) -> None:
        env = os.environ.copy()
        process = subprocess.Popen(
            job.command,
            cwd=self.repo_root,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            env=env,
        )
        assert process.stdout is not None
        for line in process.stdout:
            self._append(job, line)
        returncode = process.wait()
        self._finish(job, returncode)
        if on_finish is not None:
            on_finish(job.payload.get("history_id"), returncode)


def parse_preview(stdout: str) -> dict[str, Any]:
    return json.loads(stdout)
