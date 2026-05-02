from __future__ import annotations

import html
import json
import os
import re
import threading
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any

from fastapi import FastAPI, Form, HTTPException, Request
from fastapi.responses import HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles

from platform_workflow_ui.workflow import (
    JobStore,
    build_workflow_args,
    parse_preview,
    run_workflow_json,
    stage_default,
    stage_has_app_toggles,
    variant_to_target,
)


DEFAULT_REPO_ROOT = Path(__file__).resolve().parents[3]
STAGES = [
    ("100", "cluster"),
    ("200", "cilium"),
    ("300", "hubble"),
    ("400", "argocd"),
    ("500", "gitea"),
    ("600", "policies"),
    ("700", "app repos"),
    ("800", "observability"),
    ("900", "sso"),
    ("950-local-idp", "local-idp"),
]
ACTIONS = ["plan", "apply", "status", "show-urls", "check-health", "check-security", "check-rbac", "state-reset"]
VARIANTS = ["kubernetes/kind", "kubernetes/lima", "kubernetes/slicer"]
ANSI_PATTERN = re.compile(r"\x1b\[([0-9;]*)m")
OSC_PATTERN = re.compile(r"\x1b\][^\x07]*(?:\x07|\x1b\\)")
ANSI_CLASS_BY_CODE = {
    30: "ansi-black",
    31: "ansi-red",
    32: "ansi-green",
    33: "ansi-yellow",
    34: "ansi-blue",
    35: "ansi-magenta",
    36: "ansi-cyan",
    37: "ansi-white",
    90: "ansi-bright-black",
    91: "ansi-bright-red",
    92: "ansi-bright-green",
    93: "ansi-bright-yellow",
    94: "ansi-bright-blue",
    95: "ansi-bright-magenta",
    96: "ansi-bright-cyan",
    97: "ansi-bright-white",
}


def create_app(repo_root: Path | None = None, job_store: JobStore | None = None) -> FastAPI:
    resolved_root = repo_root or Path(os.environ.get("PLATFORM_REPO_ROOT", DEFAULT_REPO_ROOT))
    app = FastAPI(title="Platform Workflow UI")
    app.state.repo_root = resolved_root
    app.state.jobs = job_store or JobStore(resolved_root)
    app.state.command_history = CommandHistory()
    app.mount("/static", StaticFiles(directory=Path(__file__).parent / "static"), name="static")

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok", "service": "platform-workflow-ui"}

    @app.get("/", response_class=HTMLResponse)
    def index() -> str:
        return page()

    @app.get("/favicon.ico")
    def favicon() -> Response:
        favicon_path = resolved_root / "sites" / "docs" / "app" / "favicon.ico"
        if not favicon_path.is_file():
            raise HTTPException(status_code=404, detail="favicon not found")
        return Response(favicon_path.read_bytes(), media_type="image/x-icon")

    @app.get("/api/options")
    def options() -> Response:
        code, stdout, stderr = run_workflow_json(resolved_root, ["options", "--execute", "--output", "json"])
        if code != 0:
            return JSONResponse({"error": stderr.strip() or stdout.strip()}, status_code=400)
        options_payload = json.loads(stdout)
        options_payload.pop("targets", None)
        options_payload["variants"] = VARIANTS
        return JSONResponse(options_payload)

    @app.post("/preview", response_class=HTMLResponse)
    async def preview_fragment(request: Request) -> str:
        payload = await form_payload(request)
        history = app.state.command_history.snapshot()
        return history_panel(history, str(payload["variant"]), oob=True) + render_preview(resolved_root, payload, history)

    @app.post("/run", response_class=HTMLResponse)
    async def run_fragment(request: Request) -> str:
        payload = await form_payload(request)
        command = str(payload.get("command") or preview_command(resolved_root, payload) or "")
        if command:
            payload["command"] = command
            history_kind = "Dry-run" if payload.get("dry_run") else action_label(str(payload["action"]))
            payload["history_id"] = app.state.command_history.add(command, history_kind, str(payload["variant"]), payload)
        job = app.state.jobs.start(payload, on_finish=app.state.command_history.record_exit)
        return job_fragment(job, app.state.command_history.snapshot())

    @app.get("/jobs/{job_id}", response_class=HTMLResponse)
    def job_status(job_id: str) -> str:
        job = app.state.jobs.get(job_id)
        if job is None:
            raise HTTPException(status_code=404, detail="job not found")
        if not job.running and job.returncode is not None:
            app.state.command_history.record_exit(job.payload.get("history_id"), job.returncode, job.text)
        return job_fragment(job, app.state.command_history.snapshot())

    @app.post("/next", response_class=HTMLResponse)
    def next_fragment(
        variant: str = Form(...),
        stage: str = Form(...),
        action: str = Form("apply"),
    ) -> str:
        payload = {
            "variant": variant,
            "stage": stage,
            "action": action,
            "auto_approve": action in {"apply", "reset", "state-reset"},
            "sentiment": "",
            "subnetcalc": "",
        }
        return render_preview(resolved_root, payload, app.state.command_history.snapshot())

    return app


class CommandHistory:
    def __init__(self, limit: int = 5) -> None:
        self.limit = limit
        self._items: list[dict[str, Any]] = []
        self._lock = threading.Lock()

    def add(self, command: str, kind: str, variant: str, payload: dict[str, Any] | None = None) -> str:
        if not command.strip():
            return ""
        item = {
            "id": uuid.uuid4().hex,
            "command": command,
            "kind": kind,
            "variant": variant,
            "exit_status": "running",
            "timestamp": datetime.now().astimezone().strftime("%H:%M:%S"),
        }
        if payload:
            item["payload"] = history_payload(payload)
        with self._lock:
            if self._items and self._items[0]["command"] == command and self._items[0]["kind"] == kind:
                return self._items[0]["id"]
            self._items = [item, *self._items]
            self._items = self._items[: self.limit]
            return item["id"]

    def record_exit(self, history_id: str | None, returncode: int, output: str = "") -> None:
        if not history_id:
            return
        with self._lock:
            for item in self._items:
                if item.get("id") == history_id:
                    item["exit_status"] = str(returncode)
                    item["output"] = output
                    return

    def snapshot(self) -> list[dict[str, Any]]:
        with self._lock:
            return [dict(item) for item in self._items]


def form_value(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool):
        return "true" if value else ""
    return str(value)


def history_payload(payload: dict[str, Any]) -> dict[str, str]:
    keys = ("variant", "stage", "action", "sentiment", "subnetcalc", "auto_approve", "command", "source")
    return {key: form_value(payload.get(key)) for key in keys}


async def form_payload(request: Request) -> dict[str, Any]:
    form = await request.form()
    action = str(form.get("action") or "apply")
    return {
        "variant": str(form.get("variant") or "kubernetes/kind"),
        "stage": str(form.get("stage") or "900"),
        "action": action,
        "sentiment": str(form.get("sentiment") or ""),
        "subnetcalc": str(form.get("subnetcalc") or ""),
        "auto_approve": str(form.get("auto_approve") or "") in {"1", "true", "on"} or action in {"apply", "reset", "state-reset"},
        "command": str(form.get("command") or ""),
        "dry_run": str(form.get("dry_run") or "") in {"1", "true", "on"},
        "source": str(form.get("source") or "dropdowns"),
    }


def render_preview(repo_root: Path, payload: dict[str, Any], history: list[dict[str, Any]] | None = None) -> str:
    args = build_workflow_args(payload, subcommand="preview")
    code, stdout, stderr = run_workflow_json(repo_root, args)
    if code != 0:
        message = html.escape(stderr.strip() or stdout.strip() or "Preview failed")
        return f'<div class="notice error">Preview failed</div><pre class="output">{message}</pre>'
    result = parse_preview(stdout)
    return preview_panel(repo_root, result, payload) + latest_output_panel(history)


def preview_command(repo_root: Path, payload: dict[str, Any]) -> str:
    args = build_workflow_args(payload, subcommand="preview")
    code, stdout, _stderr = run_workflow_json(repo_root, args)
    if code != 0:
        return ""
    return str(parse_preview(stdout).get("command", ""))


def page() -> str:
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Platform Workflow</title>
  <script src="/static/htmx.min.js"></script>
  <style>{styles()}</style>
</head>
<body>
  <main>
    <form id="workflow-form"
      hx-post="/preview"
      hx-target="#result"
      hx-trigger="load, change delay:120ms from:select, submit"
      hx-swap="innerHTML">
      <section class="controls">
        <label class="control-field">Variant {select("variant", [(variant, variant) for variant in VARIANTS], "kubernetes/kind")}</label>
        <label class="control-field">Stage {select("stage", [(stage, f"{stage} {label}") for stage, label in STAGES], "900")}</label>
        <label class="control-field">Action {select("action", [(action, action) for action in ACTIONS], "apply")}</label>
        <label class="control-field app-toggle">Sentiment {app_select("sentiment", "900", "sentiment")}</label>
        <label class="control-field app-toggle">Subnetcalc {app_select("subnetcalc", "900", "subnetcalc")}</label>
        <input type="hidden" name="auto_approve" value="1">
        <input type="hidden" name="source" value="dropdowns">
      </section>
    </form>
    {quick_actions({"variant": "kubernetes/kind", "stage": "900"})}
    {history_panel([])}
    <section id="result" class="result" aria-live="polite">
      <div class="notice">Loading preview...</div>
    </section>
  </main>
  <script>
    function stageDefault(stage, app) {{
      if (stage === '950-local-idp') {{
        return app === 'sentiment';
      }}
      return ['700', '800', '900'].includes(stage);
    }}

    function updateAppToggles(stage) {{
      document.querySelectorAll('.app-toggle').forEach((node) => {{
        node.hidden = !['700', '800', '900', '950-local-idp'].includes(stage);
      }});
      ['sentiment', 'subnetcalc'].forEach((app) => {{
        const select = document.querySelector(`select[name="${{app}}"]`);
        if (!select) return;
        const enabled = stageDefault(stage, app);
        const previous = select.value;
        select.innerHTML = '';
        [
          ['', `Stage default: ${{enabled ? 'enabled' : 'disabled'}}`],
          [enabled ? 'off' : 'on', enabled ? 'Disable' : 'Enable'],
        ].forEach(([value, label]) => {{
          const option = document.createElement('option');
          option.value = value;
          option.textContent = label;
          select.append(option);
        }});
        select.value = [...select.options].some((option) => option.value === previous) ? previous : '';
      }});
    }}

    document.body.addEventListener('change', (event) => {{
      if (event.target && event.target.name === 'stage') {{
        updateAppToggles(event.target.value);
        updateQuickActionState();
      }}
      if (event.target && event.target.name === 'variant') {{
        updateQuickActionState();
        document.querySelectorAll('.variant-shortcuts button').forEach((node) => {{
          node.classList.toggle('active', node.dataset.variant === event.target.value);
        }});
      }}
      if (event.target && event.target.name === 'action') {{
        updateQuickActionState();
      }}
      if (event.target && event.target.tagName === 'SELECT') {{
        updateSelectedFields();
      }}
    }});
    function selectVariant(variant, button) {{
      const select = document.querySelector('select[name="variant"]');
      if (!select) return;
      select.value = variant;
      setSource('variant shortcut');
      updateQuickActionState();
      document.querySelectorAll('.variant-shortcuts button').forEach((node) => {{
        node.classList.toggle('active', node === button);
      }});
      select.dispatchEvent(new Event('change', {{ bubbles: true }}));
    }}
    function selectStage(stage) {{
      const select = document.querySelector('select[name="stage"]');
      if (!select) return;
      select.value = stage;
      setSource('stage ladder');
      select.dispatchEvent(new Event('change', {{ bubbles: true }}));
    }}
    function selectAction(action) {{
      const select = document.querySelector('select[name="action"]');
      if (!select) return;
      select.value = action;
      setSource('action button');
      select.dispatchEvent(new Event('change', {{ bubbles: true }}));
    }}
    function setSource(source) {{
      document.querySelectorAll('input[name="source"]').forEach((node) => {{ node.value = source; }});
    }}
    function copyCommand(id, button) {{
      const node = document.getElementById(id);
      if (!node || !navigator.clipboard) return;
      navigator.clipboard.writeText(node.innerText).then(() => {{
        if (!button) return;
        const previous = button.innerText;
        button.innerText = 'Copied';
        window.setTimeout(() => {{ button.innerText = previous; }}, 1200);
      }});
    }}
    function copyOutput(id, button) {{
      copyCommand(id, button);
    }}
    function showCommandTab(tab) {{
      document.querySelectorAll('.command-tab').forEach((node) => {{
        node.classList.toggle('active', node.dataset.tab === tab);
      }});
      document.querySelectorAll('.command-pane').forEach((node) => {{
        node.hidden = node.dataset.pane !== tab;
      }});
    }}
    function toggleOutputFollow(jobId) {{
      const state = window.platformWorkflowTail && window.platformWorkflowTail[jobId];
      if (!state) return;
      state.follow = !state.follow;
      state.manual = true;
      if (state.follow) {{
        const output = document.getElementById(`output-${{jobId}}`);
        if (output) output.scrollTop = output.scrollHeight;
      }}
      updateOutputFollowControls(jobId);
    }}
    function updateOutputFollowControls(jobId) {{
      const state = window.platformWorkflowTail && window.platformWorkflowTail[jobId];
      const label = document.getElementById(`follow-state-${{jobId}}`);
      const button = document.getElementById(`follow-toggle-${{jobId}}`);
      if (!state || !label || !button) return;
      label.textContent = state.follow ? 'Follow latest' : 'Follow paused';
      button.textContent = state.follow ? 'Pause follow' : 'Follow latest';
    }}
    function updateQuickActionState() {{
      const variant = document.querySelector('select[name="variant"]').value;
      const stage = document.querySelector('select[name="stage"]').value;
      document.querySelectorAll('.quick-actions input[name="variant"]').forEach((node) => {{ node.value = variant; }});
      document.querySelectorAll('.quick-actions input[name="stage"]').forEach((node) => {{ node.value = stage; }});
      document.querySelectorAll('.stage-ladder button').forEach((node) => {{
        node.classList.toggle('active', node.dataset.stage === stage);
        node.hidden = variant !== 'kubernetes/kind' && node.dataset.stage === '950-local-idp';
      }});
      document.querySelectorAll('.variant-shortcuts button').forEach((node) => {{
        node.classList.toggle('active', node.dataset.variant === variant);
      }});
      document.querySelectorAll('.action-bar button').forEach((node) => {{
        node.classList.toggle('active', node.dataset.action === document.querySelector('select[name="action"]').value);
      }});
    }}
    function updateSelectedFields() {{
      document.querySelectorAll('.control-field').forEach((label) => {{
        const select = label.querySelector('select');
        label.classList.toggle('selected', !!select && select.value !== '');
      }});
    }}
    updateAppToggles(document.querySelector('select[name="stage"]').value);
    updateQuickActionState();
    updateSelectedFields();
  </script>
</body>
</html>"""


def preview_panel(repo_root: Path, result: dict[str, Any], payload: dict[str, Any]) -> str:
    command = html.escape(str(result.get("command", "")))
    variant = html.escape(str(payload["variant"]))
    stage = html.escape(str(result.get("stage", payload["stage"])))
    action = html.escape(str(result.get("action", payload["action"])))
    raw_action = str(result.get("action", payload["action"]))
    source = html.escape(str(payload.get("source") or "dropdowns"))
    intent = html.escape(intent_summary(str(result.get("action", payload["action"])), stage, variant))
    consequence = html.escape(consequence_summary(str(result.get("action", payload["action"]))))
    button_label = html.escape(action_label(raw_action))
    risk = action_risk(raw_action)
    risk_label = html.escape(risk[0])
    risk_class = html.escape(risk[1])
    stage_delta = html.escape(stage_delta_hint(stage))
    workflow_execute = html.escape(workflow_command(payload, standard_flag="--execute"))
    workflow_dry_run = html.escape(workflow_command(payload, standard_flag="--dry-run"))
    preflight = preflight_badges(repo_root, payload)
    hidden = hidden_inputs({**payload, "command": str(result.get("command", "")), "dry_run": ""})
    dry_run_hidden = hidden_inputs({**payload, "command": str(result.get("command", "")), "dry_run": "1"})
    return f"""
<div class="provenance-strip">
  <span>Source <strong>{source}</strong></span>
  <span class="risk-badge {risk_class}">{risk_label}</span>
  {preflight}
</div>
<div class="summary">
  <div><span>Variant</span><strong>{variant}</strong></div>
  <div><span>Stage</span><strong>{stage}</strong></div>
  <div><span>Action</span><strong>{action}</strong></div>
</div>
<div class="stage-delta">{stage_delta}</div>
<div class="intent-summary">
  <div><span>Intent</span><strong>{intent}</strong></div>
  <div><span>Consequence</span><strong>{consequence}</strong></div>
</div>
<div class="command-panel">
  <div class="command-tabs" role="tablist" aria-label="Command views">
    <button type="button" class="command-tab active" data-tab="makefile" onclick="showCommandTab('makefile')">Makefile abstraction</button>
    <button type="button" class="command-tab" data-tab="script" onclick="showCommandTab('script')">Script inputs</button>
  </div>
  <div class="command-pane" data-pane="makefile">
    <div class="command-head">
      <h2>Makefile abstraction</h2>
      <button type="button" title="Copy command" onclick="copyCommand('command-text', this)">Copy</button>
    </div>
    <pre id="command-text" class="command">{command}</pre>
  </div>
  <div class="command-pane" data-pane="script" hidden>
    <div class="command-head">
      <h2>Script inputs</h2>
      <button type="button" title="Copy script command" onclick="copyCommand('workflow-command-text', this)">Copy</button>
    </div>
    <pre id="workflow-command-text" class="command">{workflow_execute}</pre>
  </div>
</div>
<div class="execution-actions">
  <form hx-post="/run" hx-target="#result" hx-swap="innerHTML">
    {dry_run_hidden}
    <button class="dry-run" type="submit">Dry-run</button>
  </form>
  <form hx-post="/run" hx-target="#result" hx-swap="innerHTML">
    {hidden}
    <button class="run" type="submit">Execute {button_label}</button>
  </form>
</div>
<p class="dry-run-note">Dry-run uses <code>{workflow_dry_run}</code>.</p>
"""


def intent_summary(action: str, stage: str, variant: str) -> str:
    target = variant_to_target(variant)
    if action == "plan":
        return f"Preview Terraform changes for {target} stage {stage}."
    if action == "apply":
        return f"Apply the selected {target} stage {stage} workflow."
    if action == "reset":
        return f"Reset the local {target} stack."
    if action == "state-reset":
        return f"Reset Terraform state for the local {target} stack."
    labels = {
        "status": "Check runtime status",
        "show-urls": "Show service URLs",
        "check-health": "Run health checks",
        "check-security": "Run security checks",
        "check-rbac": "Run RBAC checks",
    }
    return f"{labels.get(action, action)} for {target}."


def consequence_summary(action: str) -> str:
    if action == "plan":
        return "Read-only. No local stack changes should be applied."
    if action == "apply":
        return "May create, update, or delete local runtime resources."
    if action == "reset":
        return "Destructive local cleanup. Review the command before running."
    if action == "state-reset":
        return "Destructive state cleanup. Review the command before running."
    return "Runs the selected diagnostic command and streams output here."


def action_risk(action: str) -> tuple[str, str]:
    if action in {"plan", "status", "show-urls", "check-health", "check-security", "check-rbac"}:
        return ("Read-only", "readonly")
    if action == "apply":
        return ("Mutating", "mutating")
    if action in {"reset", "state-reset"}:
        return ("Destructive", "destructive")
    return ("Command", "neutral")


def stage_delta_hint(stage: str) -> str:
    if stage == "950-local-idp":
        return "Kind-only finish stage for the local identity provider path."
    try:
        value = int(stage)
    except ValueError:
        return "The selected stage is passed through to the workflow core."
    if value >= 900:
        return "Stage 900 is cumulative; jumping here includes the earlier platform checkpoints."
    if value >= 700:
        return "Stages 700 and later include app repo/workload toggles."
    return "Stages 100-600 focus on substrate and hide app toggles."


def workflow_command(payload: dict[str, Any], *, standard_flag: str) -> str:
    args = build_workflow_args(payload, subcommand="apply", standard_flag=standard_flag)
    return " ".join(["scripts/platform-workflow.sh", *shell_quote_args(args)])


def shell_quote_args(args: list[str]) -> list[str]:
    rendered = []
    for arg in args:
        if re.match(r"^[A-Za-z0-9_./:=+-]+$", arg):
            rendered.append(arg)
        else:
            rendered.append("'" + arg.replace("'", "'\"'\"'") + "'")
    return rendered


def preflight_badges(repo_root: Path, payload: dict[str, Any]) -> str:
    target = variant_to_target(str(payload.get("variant") or "kubernetes/kind"))
    badges: list[str] = []
    lock_paths = {
        "kind": repo_root / "terraform" / ".run" / "kubernetes" / ".terraform.tfstate.lock.info",
        "lima": repo_root / "terraform" / ".run" / "kubernetes-lima" / ".terraform.tfstate.lock.info",
        "slicer": repo_root / "terraform" / ".run" / "kubernetes-slicer" / ".terraform.tfstate.lock.info",
    }
    lock_path = lock_paths.get(target)
    if lock_path and lock_path.exists():
        badges.append('<span class="preflight-badge blocked">State lock present</span>')
    else:
        badges.append('<span class="preflight-badge ok">No state lock</span>')
    if target in {"kind", "lima", "slicer"}:
        badges.append('<span class="preflight-badge neutral">Runtime conflict checks run in Make</span>')
    return "".join(badges)


def action_label(action: str) -> str:
    labels = {
        "plan": "Plan",
        "apply": "Apply",
        "reset": "Reset",
        "state-reset": "State reset",
        "status": "Status",
        "show-urls": "URLs",
        "check-health": "Check health",
        "check-security": "Check security",
        "check-rbac": "Check RBAC",
    }
    return labels.get(action, action.replace("-", " ").title())


def history_panel(history: list[dict[str, Any]], current_variant: str | None = None, *, oob: bool = False) -> str:
    oob_attr = ' hx-swap-oob="outerHTML"' if oob else ""
    if not history:
        return f'<section id="history" class="history" aria-label="Recent commands" hidden{oob_attr}></section>'
    items = []
    for index, entry in enumerate(history[:5]):
        variant = html.escape(entry.get("variant", ""))
        timestamp = html.escape(entry.get("timestamp", ""))
        status = history_status(entry.get("exit_status", "unknown"))
        command = html.escape(entry["command"])
        command_id = f"recent-command-{index}"
        marker = '<span class="history-current" aria-label="Most recent">&rarr;</span>' if index == 0 else '<span></span>'
        variant_note = ""
        if index == 0 and current_variant and entry.get("variant") and entry.get("variant") != current_variant:
            variant_note = f'<small>Latest run was for {variant}</small>'
        preview_again = history_preview_form(entry)
        items.append(
            f"""<li>{marker}<time datetime="{timestamp}">{timestamp}</time><span class="history-status">{status}</span><code id="{command_id}">{command}</code>{variant_note}<button type="button" title="Copy command" aria-label="Copy command" onclick="copyCommand('{command_id}', this)">Copy</button>{preview_again}</li>"""
        )
    return f"""
<section id="history" class="history" aria-label="Recent commands"{oob_attr}>
  <h2>Recent commands</h2>
  <ol>{''.join(items)}</ol>
</section>
"""


def history_status(exit_status: str | None) -> str:
    if exit_status == "running":
        return '<span class="history-status-running">Running</span>'
    if exit_status == "0":
        return '<span class="history-status-ok">Succeeded</span>'
    if exit_status and exit_status != "unknown":
        return f'<span class="history-status-failed">Failed ({html.escape(exit_status)})</span>'
    return '<span class="history-status-unknown">Unknown</span>'


def history_preview_form(entry: dict[str, Any]) -> str:
    payload = entry.get("payload")
    if not isinstance(payload, dict):
        return ""
    fields = hidden_inputs(payload)
    return f'<form hx-post="/preview" hx-target="#result" hx-swap="innerHTML">{fields}<button type="submit">Preview again</button></form>'


def latest_output_panel(history: list[dict[str, Any]] | None) -> str:
    if not history:
        return ""
    entries = [entry for entry in history if str(entry.get("output") or "").strip()]
    if not entries:
        return ""
    panels = []
    for index, entry in enumerate(entries[:2]):
        output = str(entry.get("output") or "")
        command = html.escape(str(entry.get("command") or "latest command"))
        label = "Latest output" if index == 0 else "Previous output"
        output_id = "latest-output-text" if index == 0 else f"previous-output-text-{index}"
        panels.append(
            f"""
<details class="output-drawer" open>
  <summary>{label}</summary>
  <div class="output-meta">{output_meta(entry)}</div>
  <p>{command}</p>
  <pre id="{output_id}" class="output">{ansi_to_html(output)}</pre>
</details>
"""
        )
    return f"""
<div class="latest-output" id="latest-output-drawer">
  <div class="command-head">
    <h2>Pinned output</h2>
    <button type="button" title="Copy latest output" onclick="copyCommand('latest-output-text', this)">Copy latest</button>
    <button type="button" title="Clear output drawer" onclick="document.getElementById('latest-output-drawer').hidden = true">Clear</button>
  </div>
  {''.join(panels)}
</div>
"""


def output_meta(entry: dict[str, Any]) -> str:
    status = html.escape(str(entry.get("exit_status") or "unknown"))
    timestamp = html.escape(str(entry.get("timestamp") or ""))
    kind = html.escape(str(entry.get("kind") or "Command"))
    return f"{kind} | exit {status} | {timestamp}"


def job_fragment(job, history: list[dict[str, Any]] | None = None) -> str:
    output = ansi_to_html(job.text or "Starting workflow...")
    poll = f' hx-get="/jobs/{job.id}" hx-trigger="every 1s" hx-swap="outerHTML"' if job.running else ""
    state = "running" if job.running else ("succeeded" if job.succeeded else "failed")
    next_html = ""
    if not job.running:
        next_html = next_actions(job.payload, job.succeeded)
    tail_script = tail_output_script(job.id)
    result_header = job_result_header(job)
    return f"""
{history_panel(history or [], str(job.payload.get("variant") or "kubernetes/kind"), oob=True)}
<div id="job-{job.id}" class="job"{poll}>
  <div class="notice {state}">Workflow {state}</div>
  {result_header}
  <div class="output-controls" aria-label="Output controls">
    <span id="follow-state-{job.id}" class="follow-state">Follow latest</span>
    <button id="follow-toggle-{job.id}" type="button" onclick="toggleOutputFollow('{job.id}')">Pause follow</button>
    <button type="button" onclick="copyOutput('output-{job.id}', this)">Copy output</button>
  </div>
  <pre id="output-{job.id}" class="output">{output}</pre>
  {next_html}
  {tail_script}
</div>
"""


def job_result_header(job) -> str:
    command = html.escape(" ".join(job.command))
    started = datetime.fromtimestamp(job.started_at).astimezone().strftime("%H:%M:%S")
    finished = job.finished_at or datetime.now().timestamp()
    duration = max(0.0, finished - job.started_at)
    exit_code = "running" if job.returncode is None else str(job.returncode)
    return f"""
<div class="result-header">
  <span>Command <strong>{command}</strong></span>
  <span>Exit <strong>{html.escape(exit_code)}</strong></span>
  <span>Started <strong>{html.escape(started)}</strong></span>
  <span>Duration <strong>{duration:.1f}s</strong></span>
</div>
"""


def tail_output_script(job_id: str) -> str:
    escaped_id = html.escape(job_id)
    return f"""<script>
(() => {{
  window.platformWorkflowTail = window.platformWorkflowTail || {{}};
  const state = window.platformWorkflowTail['{escaped_id}'] || {{ follow: true, manual: false }};
  window.platformWorkflowTail['{escaped_id}'] = state;
  const output = document.getElementById('output-{escaped_id}');
  if (!output) return;
  const nearBottom = () => output.scrollHeight - output.scrollTop - output.clientHeight < 24;
  if (state.boundOutput !== output) {{
    state.boundOutput = output;
    ['wheel', 'pointerdown', 'touchstart', 'keydown'].forEach((eventName) => {{
      output.addEventListener(eventName, () => {{
        state.follow = nearBottom();
        state.manual = false;
        updateOutputFollowControls('{escaped_id}');
      }}, {{ passive: true }});
    }});
    output.addEventListener('scroll', () => {{
      state.follow = nearBottom();
      if (!state.manual) updateOutputFollowControls('{escaped_id}');
    }}, {{ passive: true }});
  }}
  if (state.follow) output.scrollTop = output.scrollHeight;
  updateOutputFollowControls('{escaped_id}');
}})();
</script>"""


def ansi_to_html(value: str) -> str:
    value = OSC_PATTERN.sub("", value).replace("\r", "\n")
    parts: list[str] = []
    active: list[str] = []
    cursor = 0

    def open_span() -> None:
        if active:
            parts.append(f'<span class="{" ".join(active)}">')

    def close_span() -> None:
        if active:
            parts.append("</span>")

    for match in ANSI_PATTERN.finditer(value):
        parts.append(html.escape(value[cursor : match.start()]))
        close_span()
        codes = [int(code) for code in match.group(1).split(";") if code]
        if not codes:
            codes = [0]
        for code in codes:
            if code == 0:
                active = []
            elif code == 1:
                if "ansi-bold" not in active:
                    active.append("ansi-bold")
            elif code == 22:
                active = [name for name in active if name != "ansi-bold"]
            elif code in ANSI_CLASS_BY_CODE:
                active = [name for name in active if not name.startswith("ansi-") or name == "ansi-bold"]
                active.append(ANSI_CLASS_BY_CODE[code])
        open_span()
        cursor = match.end()
    parts.append(html.escape(value[cursor:]))
    close_span()
    return "".join(parts)


def next_actions(payload: dict[str, Any], succeeded: bool) -> str:
    if not succeeded:
        return '<div class="actions"><button hx-post="/preview" hx-target="#result" hx-swap="innerHTML" type="button">Back to preview</button></div>'
    return ""


def quick_actions(payload: dict[str, Any]) -> str:
    variant = str(payload["variant"])
    stage = str(payload.get("stage") or "900")
    return f"""
<section class="quick-actions" aria-label="Quick actions">
  <div class="quick-actions-layout">
    {variant_shortcuts()}
    {stage_ladder(variant)}
    {action_bar(variant, stage)}
    {reset_actions(variant, stage)}
  </div>
</section>
"""


def variant_shortcuts() -> str:
    return '<div class="variant-shortcuts" aria-label="Variant shortcuts">' + variant_buttons() + "</div>"


def stage_ladder(variant: str) -> str:
    target = variant_to_target(variant)
    stage_options = [stage for stage, label in STAGES if target == "kind" or stage != "950-local-idp"]
    buttons = ['<div class="stage-ladder" role="group" aria-label="Stage ladder">']
    for stage in stage_options:
        stage_label = dict(STAGES)[stage]
        active = " active" if stage == "900" else ""
        buttons.append(
            f'<button type="button" class="stage-step{active}" data-stage="{html.escape(stage)}" data-tooltip="{html.escape(stage_label)}" aria-label="Select stage {html.escape(stage)} {html.escape(stage_label)}" onclick="selectStage(\'{html.escape(stage)}\')">{html.escape(stage_display_label(stage))}</button>'
        )
    buttons.append("</div>")
    return "\n".join(buttons)


def action_bar(variant: str, stage: str) -> str:
    target = variant_to_target(variant)
    actions = [
        ("plan", "Plan", f"Review {target} plan for selected stage"),
        ("apply", "Apply", f"Review {target} apply for selected stage"),
        ("status", "Status", f"Check {target} status"),
        ("show-urls", "URLs", f"Show {target} service URLs"),
        ("check-health", "Check health", f"Check {target} health"),
        ("check-security", "Check security", f"Check {target} security"),
        ("check-rbac", "Check RBAC", f"Check {target} RBAC"),
    ]
    forms = ['<div class="action-bar" role="group" aria-label="Actions">']
    for action, label, tooltip in actions:
        active = " active" if action == "apply" else ""
        forms.append(
            f"""<form hx-post="/preview" hx-target="#result" hx-swap="innerHTML">
  <input type="hidden" name="variant" value="{html.escape(variant)}">
  <input type="hidden" name="stage" value="{html.escape(stage)}">
  <input type="hidden" name="action" value="{html.escape(action)}">
  <input type="hidden" name="auto_approve" value="{1 if action == "apply" else 0}">
  <input type="hidden" name="source" value="action button">
  <button type="submit" class="{active.strip()}" data-action="{html.escape(action)}" data-tooltip="{html.escape(tooltip)}" aria-label="{html.escape(tooltip)}" onclick="selectAction('{html.escape(action)}')">{html.escape(label)}</button>
</form>"""
        )
    forms.append("</div>")
    return "\n".join(forms)


def reset_actions(variant: str, stage: str) -> str:
    target = variant_to_target(variant)
    reset_forms = ['<div class="reset-actions" role="group" aria-label="Reset actions">']
    for action, label, tooltip in (
        ("reset", "Reset", f"Review reset for {target}"),
        ("state-reset", "State reset", f"Review Terraform state reset for {target}"),
    ):
        reset_forms.append(
            f"""<form hx-post="/preview" hx-target="#result" hx-swap="innerHTML">
  <input type="hidden" name="variant" value="{html.escape(variant)}">
  <input type="hidden" name="stage" value="{html.escape(stage)}">
  <input type="hidden" name="action" value="{html.escape(action)}">
  <input type="hidden" name="auto_approve" value="1">
  <input type="hidden" name="source" value="reset button">
  <button type="submit" data-tooltip="{html.escape(tooltip)}" aria-label="{html.escape(tooltip)}">{html.escape(label)}</button>
</form>"""
        )
    reset_forms.append('<span class="reset-note">Review required.</span>')
    reset_forms.append("</div>")
    return "\n".join(reset_forms)


def stage_display_label(stage: str) -> str:
    return "950" if stage == "950-local-idp" else stage


def variant_buttons() -> str:
    buttons = []
    for variant in VARIANTS:
        active = " active" if variant == "kubernetes/kind" else ""
        buttons.append(
            f'<button class="variant-button{active}" type="button" data-variant="{html.escape(variant)}" data-tooltip="Switch to {html.escape(variant)}" aria-label="Switch to {html.escape(variant)}" onclick="selectVariant(\'{html.escape(variant)}\', this)">{html.escape(variant)}</button>'
        )
    return "".join(buttons)


def select(name: str, options: list[tuple[str, str]], selected: str) -> str:
    rendered = []
    for value, label in options:
        attrs = ' selected' if value == selected else ""
        rendered.append(f'<option value="{html.escape(value)}"{attrs}>{html.escape(label)}</option>')
    return f'<select name="{html.escape(name)}">' + "".join(rendered) + "</select>"


def app_select(name: str, stage: str, app: str) -> str:
    default = stage_default(stage, app)
    options = [
        ("", f"Stage default: {'enabled' if default else 'disabled'}"),
        ("off" if default else "on", "Disable" if default else "Enable"),
    ]
    return select(name, options, "")


def hidden_inputs(payload: dict[str, Any]) -> str:
    fields = []
    for key, value in payload.items():
        fields.append(f'<input type="hidden" name="{html.escape(str(key))}" value="{html.escape(str(value))}">')
    return "\n".join(fields)


def styles() -> str:
    return """
:root { color-scheme: light; --ink:#15201c; --muted:#66736d; --paper:#f6f1e8; --panel:#fffdf8; --line:#c9d5cb; --accent:#0f766e; --accent-strong:#0b5f58; --danger:#a33a22; --code:#10231f; }
* { box-sizing: border-box; }
html, body { height:100%; }
body { margin:0; height:100vh; overflow:hidden; font-family: ui-sans-serif, system-ui, sans-serif; color:var(--ink); background:var(--paper); }
main { width:calc(100vw - 40px); height:100vh; margin:0 auto; padding:18px 0; display:grid; grid-template-rows:auto auto auto minmax(0, 1fr); gap:16px; }
header { display:flex; justify-content:space-between; gap:20px; align-items:end; border-bottom:2px solid var(--ink); padding-bottom:16px; margin-bottom:18px; }
h1 { margin:0; font-size:clamp(2rem, 4vw, 4rem); letter-spacing:0; }
.eyebrow { margin:0 0 6px; color:var(--muted); font-weight:800; text-transform:uppercase; font-size:.78rem; }
section, .result { background:var(--panel); border:1px solid var(--line); }
main > form { display:block; }
.variant-shortcuts { display:flex; gap:8px; align-items:center; flex-wrap:wrap; }
.variant-shortcuts button { min-width:150px; }
.variant-shortcuts button.active, .stage-ladder button.active, .action-bar button.active { background:var(--ink); border-color:var(--ink); box-shadow:0 0 0 2px var(--paper), 0 0 0 4px var(--ink); }
.controls { display:grid; grid-template-columns: minmax(150px, .8fr) minmax(190px, 1fr) minmax(150px, .8fr) minmax(210px, 1.05fr) minmax(210px, 1.05fr); gap:12px; padding:14px; align-items:end; }
label { display:grid; gap:6px; color:var(--muted); font-weight:800; font-size:.78rem; text-transform:uppercase; }
.control-field.selected { outline:2px solid var(--ink); outline-offset:3px; background:#fbfaf4; }
select, button { min-height:40px; border:1px solid var(--ink); background:white; color:var(--ink); padding:8px 10px; font:inherit; }
select { width:100%; min-width:0; font-weight:700; overflow:hidden; text-overflow:ellipsis; }
button { cursor:pointer; background:var(--accent); color:white; border-color:var(--accent); font-weight:800; }
button:hover { background:var(--accent-strong); }
button[data-tooltip] { position:relative; }
button[data-tooltip]::after { content:attr(data-tooltip); position:absolute; left:50%; bottom:calc(100% + 8px); z-index:20; transform:translateX(-50%); width:max-content; max-width:260px; padding:6px 8px; border:1px solid var(--ink); background:var(--ink); color:white; font-size:.75rem; line-height:1.2; font-weight:800; white-space:normal; opacity:0; pointer-events:none; }
button[data-tooltip]:hover::after, button[data-tooltip]:focus-visible::after { opacity:1; }
.result { display:flex; flex-direction:column; min-height:0; height:100%; padding:16px; overflow:hidden; }
.summary { display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:10px; margin-bottom:16px; }
.summary div { border:1px solid var(--line); padding:10px; background:#fbfaf4; }
.summary span { display:block; color:var(--muted); text-transform:uppercase; font-size:.72rem; font-weight:800; }
.summary strong { display:block; margin-top:6px; }
.provenance-strip { display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin-bottom:12px; }
.provenance-strip span, .risk-badge, .preflight-badge { display:inline-flex; align-items:center; min-height:28px; border:1px solid var(--line); background:#fbfaf4; padding:4px 8px; font-size:.75rem; font-weight:800; text-transform:uppercase; }
.risk-badge.readonly, .preflight-badge.ok { border-color:var(--accent); color:var(--accent); }
.risk-badge.mutating { border-color:#8a5b00; color:#8a5b00; }
.risk-badge.destructive, .preflight-badge.blocked { border-color:var(--danger); color:var(--danger); }
.preflight-badge.neutral, .risk-badge.neutral { color:var(--muted); }
.stage-delta { margin:-6px 0 14px; color:var(--muted); font-size:.86rem; font-weight:700; }
.intent-summary { display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-bottom:16px; }
.intent-summary div { border:1px solid var(--line); padding:10px; background:#eef8f4; }
.intent-summary span { display:block; color:var(--muted); text-transform:uppercase; font-size:.72rem; font-weight:800; }
.intent-summary strong { display:block; margin-top:6px; line-height:1.35; }
.history { margin-bottom:16px; border:1px solid var(--line); background:#fbfaf4; padding:10px 12px; }
.history[hidden] { display:none; }
.history h2 { margin:0 0 8px; font-size:.8rem; text-transform:uppercase; color:var(--muted); }
.history ol { display:grid; gap:6px; margin:0; padding:0; list-style:none; }
.history li { display:grid; grid-template-columns:20px 72px 112px minmax(0, 1fr) minmax(0, auto) auto auto; gap:10px; align-items:center; }
.history span { color:var(--muted); font-size:.72rem; font-weight:800; text-transform:uppercase; }
.history-current { color:var(--accent); font-size:1rem; line-height:1; text-align:center; }
.history time { color:var(--muted); font-size:.72rem; font-weight:800; font-variant-numeric:tabular-nums; }
.history-status { font-size:.72rem; font-weight:800; text-transform:uppercase; }
.history-status-running { color:#8a5b00; }
.history-status-ok { color:var(--accent); }
.history-status-failed { color:var(--danger); }
.history-status-unknown { color:var(--muted); }
.history small { color:#8a5b00; font-size:.72rem; font-weight:800; white-space:nowrap; }
.history code { display:block; min-width:0; overflow:auto; white-space:nowrap; font-family:ui-monospace, monospace; color:var(--ink); }
.history button { min-height:32px; padding:5px 9px; }
.history form { margin:0; }
.command-head { display:flex; justify-content:space-between; align-items:center; gap:12px; margin-bottom:8px; }
.command-head h2 { margin:0; font-size:.8rem; text-transform:uppercase; color:var(--muted); }
.command-panel { margin-top:8px; }
.command-tabs { display:flex; gap:8px; margin-bottom:8px; flex-wrap:wrap; }
.command-tab { background:white; color:var(--accent); border-color:var(--accent); }
.command-tab.active { background:var(--ink); color:white; border-color:var(--ink); }
.command-pane[hidden] { display:none; }
pre { margin:0; padding:14px; background:var(--code); color:#e5fff7; overflow:auto; white-space:pre; line-height:1.45; }
.command { min-height:90px; font-weight:800; color:#8ee8ff; }
.latest-output { margin-top:16px; border-top:1px solid var(--line); padding-top:12px; min-height:0; }
.output-drawer { border:1px solid var(--line); background:#fbfaf4; padding:10px; margin-top:8px; }
.output-drawer summary { cursor:pointer; color:var(--muted); font-size:.78rem; font-weight:800; text-transform:uppercase; }
.output-meta, .result-header { display:flex; gap:8px; flex-wrap:wrap; color:var(--muted); font-size:.76rem; font-weight:800; text-transform:uppercase; margin-bottom:8px; }
.result-header { border:1px solid var(--line); background:#fbfaf4; padding:8px; }
.result-header strong { color:var(--ink); text-transform:none; }
.latest-output p { margin:0 0 8px; color:var(--muted); font-family:ui-monospace, monospace; font-size:.82rem; overflow:auto; white-space:nowrap; }
.latest-output .output { max-height:220px; }
.job { display:flex; flex-direction:column; min-height:0; height:100%; }
.output-controls { display:flex; gap:8px; align-items:center; margin-bottom:8px; flex-wrap:wrap; }
.output-controls span { color:var(--muted); font-size:.78rem; font-weight:800; text-transform:uppercase; }
.output-controls button { min-height:32px; padding:5px 9px; }
.output { flex:1 1 auto; min-height:0; max-height:none; }
.ansi-bold { font-weight:800; }
.ansi-black { color:#1f2933; }
.ansi-red, .ansi-bright-red { color:#ff8a80; }
.ansi-green, .ansi-bright-green { color:#8ee88e; }
.ansi-yellow, .ansi-bright-yellow { color:#ffd166; }
.ansi-blue, .ansi-bright-blue { color:#8cb8ff; }
.ansi-magenta, .ansi-bright-magenta { color:#d7a1ff; }
.ansi-cyan, .ansi-bright-cyan { color:#7ce7ff; }
.ansi-white, .ansi-bright-white { color:#f3fff9; }
.ansi-bright-black { color:#8a9791; }
.notice { margin-bottom:12px; font-weight:800; }
.error, .failed { color:var(--danger); }
.running { color:#8a5b00; }
.succeeded { color:var(--accent); }
.execution-actions { display:flex; gap:10px; align-items:center; margin-top:12px; flex-wrap:wrap; }
.execution-actions form { margin:0; }
.run, .dry-run { width:auto; min-width:132px; padding-inline:20px; }
.dry-run { background:white; color:var(--accent); border-color:var(--accent); }
.dry-run:hover { background:#eef8f4; }
.quick-actions { margin-top:16px; padding:12px; }
.quick-actions-layout { display:grid; grid-template-columns:minmax(0, 1fr) auto; gap:10px 14px; align-items:end; }
.stage-ladder { grid-column:1 / 2; display:grid; grid-template-columns:repeat(10, minmax(56px, 1fr)); gap:6px; }
.stage-ladder button { min-width:0; padding-inline:6px; }
.action-bar { grid-column:1 / 2; display:flex; gap:8px; flex-wrap:wrap; align-items:center; }
.action-bar form, .reset-actions form { margin:0; }
.reset-actions { grid-row:1 / span 3; grid-column:2 / 3; display:flex; gap:8px; flex-direction:column; align-items:stretch; min-width:150px; padding-left:14px; border-left:1px solid var(--line); }
.reset-note { display:inline-flex; align-items:center; color:var(--muted); font-size:.82rem; font-weight:800; }
@media (max-width: 900px) { header, .controls, .summary, .intent-summary, .history li, .quick-actions-layout { grid-template-columns:1fr; display:grid; } .variant-shortcuts { flex-wrap:wrap; } .stage-ladder { grid-template-columns:repeat(5, minmax(56px, 1fr)); } .reset-actions { grid-row:auto; grid-column:auto; flex-direction:row; flex-wrap:wrap; padding-left:0; border-left:0; border-top:1px solid var(--line); padding-top:10px; } }
"""


app = create_app()
