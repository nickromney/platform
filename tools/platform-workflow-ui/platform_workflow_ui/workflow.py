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


APP_STAGES = {"700", "800", "900"}
PRESET_FIELD_GROUPS = {
    "preset_resource_profile": "resource-profile",
    "preset_image_distribution": "image-distribution",
    "preset_network_profile": "network-profile",
    "preset_observability_stack": "observability-stack",
    "preset_identity_stack": "identity-stack",
    "preset_app_set": "app-set",
}
CUSTOM_OVERRIDE_FIELDS = {
    "custom_worker_count": "worker_count",
    "custom_node_image": "node_image",
    "custom_enable_backstage": "enable_backstage",
}
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
    return stage in {"700", "800", "900"}


def app_default(payload: dict[str, Any], app: str) -> bool:
    app_set = str(payload.get("preset_app_set") or "default")
    if app_set == "reference-apps":
        return True
    if app_set == "no-reference-apps":
        return False
    if app_set == "sentiment-only":
        return app == "sentiment"
    return stage_default(str(payload.get("stage") or "900"), app)


def next_stages(variant: str, stage: str, action: str, succeeded: bool) -> list[str]:
    if not succeeded or action != "apply":
        return []
    stages_by_current = {
        "500": ["600", "900"],
        "600": ["700", "800", "900"],
        "700": ["800", "900"],
        "800": ["900"],
    }
    stages = stages_by_current.get(stage, [])
    return stages


def build_workflow_args(payload: dict[str, Any], *, subcommand: str, standard_flag: str = "--execute") -> list[str]:
    variant = variant_to_target(str(payload.get("variant") or "kubernetes/kind"))
    args = [
        subcommand,
        standard_flag,
    ]
    if subcommand == "preview":
        args.extend(["--output", "json"])
    args.extend(
        [
            "--variant",
            variant,
            "--stage",
            str(payload.get("stage") or "900"),
            "--action",
            str(payload.get("action") or "apply"),
        ]
    )
    for field, group in PRESET_FIELD_GROUPS.items():
        value = str(payload.get(field) or "")
        if value and value != "default":
            args.extend(["--preset", f"{group}={value}"])
    for field, option in CUSTOM_OVERRIDE_FIELDS.items():
        value = str(payload.get(field) or "")
        if value:
            args.extend(["--set", f"{option}={value}"])
    if stage_has_app_toggles(str(payload.get("stage") or "900")):
        for app in ("sentiment", "subnetcalc"):
            value = str(payload.get(app) or "")
            default_value = "on" if app_default(payload, app) else "off"
            if value and value != default_value:
                args.extend(["--app", f"{app}={value}"])
    if payload.get("auto_approve") and str(payload.get("action") or "") in {"apply", "reset", "state-reset"}:
        args.append("--auto-approve")
    return args


def run_workflow_json(repo_root: Path, args: list[str]) -> tuple[int, str, str]:
    command = [str(repo_root / "scripts" / "platform-workflow.sh"), *args]
    result = subprocess.run(command, cwd=repo_root, text=True, capture_output=True, check=False)
    return result.returncode, result.stdout, result.stderr


def run_inventory_json(repo_root: Path, *, variant: str = "kubernetes/kind", stage: str = "900") -> tuple[int, str, str]:
    command = [
        str(repo_root / "scripts" / "platform-inventory.sh"),
        "--execute",
        "--variant",
        variant_to_target(variant),
        "--stage",
        stage,
        "--output",
        "json",
    ]
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

    def start(self, payload: dict[str, Any], on_finish: Callable[[str | None, int, str], None] | None = None) -> WorkflowJob:
        standard_flag = "--dry-run" if payload.get("dry_run") else "--execute"
        args = build_workflow_args(payload, subcommand="apply", standard_flag=standard_flag)
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

    def _run(self, job: WorkflowJob, on_finish: Callable[[str | None, int, str], None] | None = None) -> None:
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
            on_finish(job.payload.get("history_id"), returncode, job.text)


def parse_preview(stdout: str) -> dict[str, Any]:
    return json.loads(stdout)
