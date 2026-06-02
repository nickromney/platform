from __future__ import annotations

import json
import os
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable, Mapping


DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[3]
WORKFLOW_OPTIONS_PATH = DEFAULT_REPO_ROOT / "kubernetes" / "workflow" / "options.json"


def load_workflow_options(repo_root: Path | None = None) -> dict[str, Any]:
    path = (repo_root or DEFAULT_REPO_ROOT) / "kubernetes" / "workflow" / "options.json"
    return json.loads(path.read_text(encoding="utf-8"))


WORKFLOW_OPTIONS = load_workflow_options()
APP_NAMES = [str(name) for name in WORKFLOW_OPTIONS.get("apps", [])]
APP_STAGES = {stage["id"] for stage in WORKFLOW_OPTIONS.get("stages", []) if stage.get("app_toggles")}
PRESET_FIELD_GROUPS = {
    f"preset_{group['id']}": group["id"].replace("_", "-") for group in WORKFLOW_OPTIONS.get("preset_groups", [])
}
CUSTOM_OVERRIDE_FIELDS = {
    "custom_worker_count": "worker_count",
    "custom_node_image": "node_image",
    "custom_enable_backstage": "enable_backstage",
}
VARIANT_TARGETS = {variant["path"]: variant["id"] for variant in WORKFLOW_OPTIONS.get("variants", [])}
NEXT_APPLY_STAGES = WORKFLOW_OPTIONS.get("ui_rules", {}).get("next_apply_stages_by_stage", {})
TRUTHY_FORM_VALUES = {"1", "true", "on"}
HISTORY_FIELDS = (
    "variant",
    "stage",
    "action",
    *APP_NAMES,
    *PRESET_FIELD_GROUPS.keys(),
    *CUSTOM_OVERRIDE_FIELDS.keys(),
    "auto_approve",
    "command",
    "dry_run",
    "source",
)


def form_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else ""
    return str(value)


def action_uses_auto_approve(action: str) -> bool:
    for option in WORKFLOW_OPTIONS.get("action_metadata", []):
        if option.get("id") == action:
            return bool(option.get("uses_auto_approve"))
    return action in {"apply", "reset", "state-reset"}


@dataclass(frozen=True)
class WorkflowSelection:
    variant: str = "kubernetes/kind"
    stage: str = "900"
    action: str = "apply"
    apps: dict[str, str] = field(default_factory=dict)
    presets: dict[str, str] = field(default_factory=dict)
    custom_overrides: dict[str, str] = field(default_factory=dict)
    auto_approve: bool = False
    command: str = ""
    dry_run: bool = False
    source: str = "dropdowns"

    @classmethod
    def from_mapping(cls, values: Mapping[str, Any]) -> "WorkflowSelection":
        action = _text(values, "action", "apply")
        return cls(
            variant=_text(values, "variant", "kubernetes/kind"),
            stage=_text(values, "stage", "900"),
            action=action,
            apps={app_name: _text(values, app_name) for app_name in APP_NAMES},
            presets={field_name: _text(values, field_name, "default") for field_name in PRESET_FIELD_GROUPS},
            custom_overrides={field_name: _text(values, field_name) for field_name in CUSTOM_OVERRIDE_FIELDS},
            auto_approve=_truthy(values.get("auto_approve")) or action_uses_auto_approve(action),
            command=_text(values, "command"),
            dry_run=_truthy(values.get("dry_run")),
            source=_text(values, "source", "dropdowns"),
        )

    def to_payload(self) -> dict[str, Any]:
        return {
            "variant": self.variant,
            "stage": self.stage,
            "action": self.action,
            **self.apps,
            **self.presets,
            **self.custom_overrides,
            "auto_approve": self.auto_approve,
            "command": self.command,
            "dry_run": self.dry_run,
            "source": self.source,
        }

    def history_payload(self) -> dict[str, str]:
        payload = self.to_payload()
        return {key: form_value(payload.get(key)) for key in HISTORY_FIELDS}

    def workflow_args(self, subcommand: str, *, standard_flag: str = "--execute") -> list[str]:
        args = [subcommand, standard_flag]
        if subcommand == "preview":
            args.extend(["--output", "json"])
        args.extend(["--variant", variant_to_target(self.variant), "--stage", self.stage, "--action", self.action])
        for field, group in PRESET_FIELD_GROUPS.items():
            value = self.presets.get(field, "")
            if value and value != "default":
                args.extend(["--preset", f"{group}={value}"])
        for field, option in CUSTOM_OVERRIDE_FIELDS.items():
            value = self.custom_overrides.get(field, "")
            if value:
                args.extend(["--set", f"{option}={value}"])
        if self.has_app_toggles():
            for app in APP_NAMES:
                value = self.apps.get(app, "")
                default_value = "on" if self.app_default(app) else "off"
                if value and value != default_value:
                    args.extend(["--app", f"{app}={value}"])
        if self.auto_approve and action_uses_auto_approve(self.action):
            args.append("--auto-approve")
        return args

    def run_standard_flag(self) -> str:
        return "--dry-run" if self.dry_run else "--execute"

    def has_app_toggles(self) -> bool:
        return stage_has_app_toggles(self.stage)

    def app_default(self, app: str) -> bool:
        app_set = self.presets.get("preset_app_set") or "default"
        tfvar_name = f"enable_app_repo_{app.replace('-', '_')}"
        for preset in WORKFLOW_OPTIONS.get("presets", []):
            if preset.get("group") == "app_set" and preset.get("id") == app_set:
                overlay = preset.get("overlay", {})
                if tfvar_name in overlay:
                    return bool(overlay[tfvar_name])
        return stage_default(self.stage, app)


def _text(values: Mapping[str, Any], key: str, default: str = "") -> str:
    value = values.get(key)
    if value is None or value == "":
        return default
    return str(value)


def _truthy(value: Any) -> bool:
    if isinstance(value, bool):
        return value
    return str(value or "").lower() in TRUTHY_FORM_VALUES


def history_payload(payload: Mapping[str, Any]) -> dict[str, str]:
    return WorkflowSelection.from_mapping(payload).history_payload()


def variant_to_target(variant: str) -> str:
    return VARIANT_TARGETS.get(variant, variant.rsplit("/", 1)[-1] or "kind")


def stage_has_app_toggles(stage: str) -> bool:
    return stage in APP_STAGES


def stage_default(stage: str, app: str) -> bool:
    return stage in APP_STAGES


def app_default(payload: dict[str, Any], app: str) -> bool:
    return WorkflowSelection.from_mapping(payload).app_default(app)


def next_stages(variant: str, stage: str, action: str, succeeded: bool) -> list[str]:
    if not succeeded or action != "apply":
        return []
    stages = NEXT_APPLY_STAGES.get(stage, [])
    return stages


def build_workflow_args(payload: dict[str, Any], *, subcommand: str, standard_flag: str = "--execute") -> list[str]:
    return WorkflowSelection.from_mapping(payload).workflow_args(subcommand, standard_flag=standard_flag)


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
        selection = WorkflowSelection.from_mapping(payload)
        args = selection.workflow_args("apply", standard_flag=selection.run_standard_flag())
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
