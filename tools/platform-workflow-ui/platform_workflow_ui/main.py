from __future__ import annotations

import html
import json
import os
import re
import shutil
import subprocess
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
    run_inventory_json,
    run_workflow_json,
    app_default,
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
]
ACTIONS = ["readiness", "plan", "apply", "status", "show-urls", "check-health", "check-security", "check-rbac", "state-reset"]
VARIANTS = ["kubernetes/kind", "kubernetes/lima", "kubernetes/slicer"]
PRESET_GROUPS = [
    ("preset_resource_profile", "Resource profile", [("default", "Stage default"), ("minimal", "Minimal"), ("local-12gb", "Local 12 GB"), ("local-idp-12gb", "Local IDP 12 GB"), ("airplane", "Airplane")]),
    ("preset_image_distribution", "Image distribution", [("default", "Stage default"), ("pull", "Pull"), ("local-cache", "Local cache"), ("preload", "Preload"), ("baked", "Baked"), ("airplane", "Airplane")]),
    ("preset_network_profile", "Network profile", [("default", "Stage default"), ("cilium", "Cilium"), ("default-cni", "Default CNI")]),
    ("preset_observability_stack", "Observability stack", [("default", "Stage default"), ("victoria", "VictoriaLogs"), ("lgtm", "LGTM"), ("minimal-observability", "Minimal"), ("none", "None")]),
    ("preset_identity_stack", "Identity stack", [("default", "Stage default"), ("keycloak", "Keycloak"), ("dex", "Dex")]),
    ("preset_app_set", "App set", [("default", "Stage default"), ("reference-apps", "Reference apps"), ("no-reference-apps", "No reference apps"), ("sentiment-only", "Sentiment only")]),
]
APP_OPTIONS = [("sentiment", "Sentiment"), ("subnetcalc", "Subnetcalc")]
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
        if "variants" not in options_payload:
            options_payload["variants"] = [{"id": variant_to_target(variant), "path": variant} for variant in VARIANTS]
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

    @app.get("/inventory", response_class=HTMLResponse)
    def inventory_fragment(variant: str = "kubernetes/kind", stage: str = "900") -> str:
        code, stdout, stderr = run_inventory_json(resolved_root, variant=variant, stage=stage)
        if code != 0:
            message = html.escape(stderr.strip() or stdout.strip() or "Status unavailable")
            return f'<section class="inventory"><div class="notice error">Inventory unavailable</div><pre class="output">{message}</pre></section>'
        try:
            payload = json.loads(stdout)
        except json.JSONDecodeError:
            return f'<section class="inventory"><div class="notice error">Inventory unavailable</div><pre class="output">{html.escape(stdout)}</pre></section>'
        return inventory_panel(payload, prereq_tools())

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
            "preset_resource_profile": "default",
            "preset_image_distribution": "default",
            "preset_network_profile": "default",
            "preset_observability_stack": "default",
            "preset_identity_stack": "default",
            "preset_app_set": "default",
            "custom_worker_count": "",
            "custom_node_image": "",
            "custom_enable_backstage": "",
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
    keys = (
        "variant",
        "stage",
        "action",
        "sentiment",
        "subnetcalc",
        "preset_resource_profile",
        "preset_image_distribution",
        "preset_network_profile",
        "preset_observability_stack",
        "preset_identity_stack",
        "preset_app_set",
        "custom_worker_count",
        "custom_node_image",
        "custom_enable_backstage",
        "auto_approve",
        "command",
        "source",
    )
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
        "preset_resource_profile": str(form.get("preset_resource_profile") or "default"),
        "preset_image_distribution": str(form.get("preset_image_distribution") or "default"),
        "preset_network_profile": str(form.get("preset_network_profile") or "default"),
        "preset_observability_stack": str(form.get("preset_observability_stack") or "default"),
        "preset_identity_stack": str(form.get("preset_identity_stack") or "default"),
        "preset_app_set": str(form.get("preset_app_set") or "default"),
        "custom_worker_count": str(form.get("custom_worker_count") or ""),
        "custom_node_image": str(form.get("custom_node_image") or ""),
        "custom_enable_backstage": str(form.get("custom_enable_backstage") or ""),
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
        return f'<div class="preview-error"><div class="notice error">Preview failed</div><pre class="output preview-error-output">{message}</pre></div>'
    result = parse_preview(stdout)
    return preview_panel(repo_root, result, payload) + latest_output_panel(history)


def preview_command(repo_root: Path, payload: dict[str, Any]) -> str:
    args = build_workflow_args(payload, subcommand="preview")
    code, stdout, _stderr = run_workflow_json(repo_root, args)
    if code != 0:
        return ""
    return str(parse_preview(stdout).get("command", ""))


def guided_tab() -> str:
    variant_facts = {
        "kubernetes/kind": ("Kind", "Kubernetes IN Docker"),
        "kubernetes/lima": ("Lima", "K3s in Lima VM"),
        "kubernetes/slicer": ("Slicer", "K3s in Slicer"),
    }
    stage_descs = {
        "100": "Cluster substrate and resource sizing",
        "200": "Cilium networking layer",
        "300": "Hubble visibility for Cilium",
        "400": "Argo CD GitOps controller",
        "500": "Gitea internal Git provider",
        "600": "Policy and certificate foundations",
        "700": "App repos and reference workloads",
        "800": "Observability, gateway TLS, dashboards",
        "900": "SSO, IDP, Backstage, authenticated surfaces",
    }
    variant_btns = []
    for variant in VARIANTS:
        title, subtitle = variant_facts.get(variant, (variant, variant))
        active = " active" if variant == "kubernetes/kind" else ""
        variant_btns.append(
            f'<button type="button" class="guided-btn guided-variant-btn{active}" data-variant="{html.escape(variant)}"'
            f' data-tooltip="{html.escape(variant)}" onclick="selectVariant(\'{html.escape(variant)}\', this)">'
            f'<strong>{html.escape(title)}</strong><span>{html.escape(subtitle)}</span></button>'
        )
    stage_btns = []
    for stage, label in STAGES:
        active = " active" if stage == "900" else ""
        desc = stage_descs.get(stage, "")
        stage_btns.append(
            f'<button type="button" class="guided-btn guided-stage-btn{active}" data-stage="{html.escape(stage)}"'
            f' data-tooltip="{html.escape(desc)}" onclick="selectStage(\'{html.escape(stage)}\')">'
            f'<strong>{html.escape(stage)}</strong><span>{html.escape(label)}</span></button>'
        )
    profiles = [
        ("stage-defaults", "Stage defaults", "Baseline — no overrides applied"),
        ("minimal-local", "Minimal local", "Stage 700, minimal resources, no reference apps"),
        ("idp-demo", "IDP demo", "Kind stage 900, local IDP profile, 12 GB"),
        ("airplane", "Airplane", "Stage 900, local cache, no pull required"),
    ]
    profile_btns = []
    for key, name, desc in profiles:
        active = " active" if key == "stage-defaults" else ""
        profile_btns.append(
            f'<button type="button" class="guided-btn guided-profile-btn{active}" data-profile="{html.escape(key)}"'
            f' onclick="applySetupProfile(\'{html.escape(key)}\')">'
            f'<strong>{html.escape(name)}</strong><span>{html.escape(desc)}</span></button>'
        )
    action_defs = [
        ("readiness", "Readiness", "Check prerequisites"),
        ("plan", "Plan", "Preview Terraform changes"),
        ("apply", "Apply", "Deploy the selected stage"),
        ("status", "Status", "Check runtime status"),
        ("show-urls", "URLs", "Show service endpoints"),
    ]
    action_btns = []
    for action, label, desc in action_defs:
        active = " active" if action == "apply" else ""
        action_btns.append(
            f'<button type="button" class="guided-btn guided-action-btn{active}" data-action="{html.escape(action)}"'
            f' onclick="selectAction(\'{html.escape(action)}\')">'
            f'<strong>{html.escape(label)}</strong><span>{html.escape(desc)}</span></button>'
        )
    return f"""
<div class="guided-layout">
  <div class="guided-section">
    <div class="guided-section-head"><span class="guided-step">1</span><strong>Runtime</strong></div>
    <div class="guided-group">{''.join(variant_btns)}</div>
  </div>
  <div class="guided-section">
    <div class="guided-section-head"><span class="guided-step">2</span><strong>Stage</strong><small>Cumulative — each stage includes all prior stages</small></div>
    <div class="guided-group guided-stages">{''.join(stage_btns)}</div>
  </div>
  <div class="guided-section">
    <div class="guided-section-head"><span class="guided-step">3</span><strong>Profile</strong></div>
    <div class="guided-group">{''.join(profile_btns)}</div>
  </div>
  <div class="guided-section">
    <div class="guided-section-head"><span class="guided-step">4</span><strong>Action</strong></div>
    <div class="guided-group">{''.join(action_btns)}</div>
  </div>
</div>
"""


def expert_tab() -> str:
    return f"""
<div class="expert-layout">
  <div class="expert-controls">
    <label class="control-field">Variant {select("variant", [(v, v) for v in VARIANTS], "kubernetes/kind")}</label>
    <label class="control-field">Stage {select("stage", [(s, f"{s} {lb}") for s, lb in STAGES], "900")}</label>
    <label class="control-field">Action {select("action", [(a, a) for a in ACTIONS], "apply")}</label>
  </div>
  {preset_panel()}
  {apps_panel()}
  {advanced_overrides_panel()}
</div>
"""


def page() -> str:
    return f"""<!doctype html>
<html lang="en" data-theme="dark">
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
      hx-trigger="load, change delay:120ms from:select, change delay:250ms from:input, submit"
      hx-swap="innerHTML">
      <div class="tab-bar">
        <nav class="tab-nav" role="tablist">
          <button type="button" class="tab-btn active" role="tab" aria-selected="true" data-tab="guided" onclick="switchTab('guided')">Guided</button>
          <button type="button" class="tab-btn" role="tab" aria-selected="false" data-tab="expert" onclick="switchTab('expert')">Expert</button>
        </nav>
        <div class="tab-bar-end">
          <div class="preset-summary" aria-live="polite"><span>Setup</span><strong id="preset-summary-text">Stage defaults</strong></div>
          <button id="theme-switcher" class="theme-switcher" type="button" aria-label="Switch to light theme" title="Switch theme" onclick="toggleTheme()">
            <svg class="theme-icon theme-icon-sun" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"></circle><path d="M12 2v3M12 19v3M4.9 4.9 7 7M17 17l2.1 2.1M2 12h3M19 12h3M4.9 19.1 7 17M17 7l2.1-2.1"></path></svg>
            <svg class="theme-icon theme-icon-moon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20.5 14.5A8.5 8.5 0 0 1 9.5 3.5 7 7 0 1 0 20.5 14.5Z"></path></svg>
          </button>
        </div>
      </div>
      <div id="tab-guided" class="tab-panel" role="tabpanel">
        {guided_tab()}
      </div>
      <div id="tab-expert" class="tab-panel" role="tabpanel" hidden>
        {expert_tab()}
      </div>
      <input type="hidden" name="auto_approve" value="1">
      <input type="hidden" name="source" value="dropdowns">
    </form>
    <section id="inventory" hx-get="/inventory" hx-include="#workflow-form" hx-trigger="load, every 15s" hx-swap="innerHTML">
      <div class="notice">Checking prereqs...</div>
    </section>
    {history_panel([])}
    <section id="result" class="result" aria-live="polite">
      <div class="notice">Loading preview...</div>
    </section>
  </main>
  <script>
    function switchTab(tab) {{
      document.querySelectorAll('.tab-panel').forEach((panel) => {{
        panel.hidden = panel.id !== `tab-${{tab}}`;
      }});
      document.querySelectorAll('.tab-btn').forEach((btn) => {{
        btn.classList.toggle('active', btn.dataset.tab === tab);
        btn.setAttribute('aria-selected', btn.dataset.tab === tab ? 'true' : 'false');
      }});
      if (tab === 'guided') syncGuidedTabState();
      try {{ localStorage.setItem('platform-workflow-ui-tab', tab); }} catch (_e) {{}}
    }}
    function syncGuidedTabState() {{
      const variant = (document.querySelector('select[name="variant"]') || {{}}).value || '';
      const stage = (document.querySelector('select[name="stage"]') || {{}}).value || '';
      const action = (document.querySelector('select[name="action"]') || {{}}).value || '';
      document.querySelectorAll('.guided-variant-btn').forEach((btn) => {{
        btn.classList.toggle('active', btn.dataset.variant === variant);
      }});
      document.querySelectorAll('.guided-stage-btn').forEach((btn) => {{
        btn.classList.toggle('active', btn.dataset.stage === stage);
      }});
      document.querySelectorAll('.guided-action-btn').forEach((btn) => {{
        btn.classList.toggle('active', btn.dataset.action === action);
      }});
    }}
    function stageDefault(stage, app) {{
      return ['700', '800', '900'].includes(stage);
    }}
    function effectiveAppDefault(stage, app) {{
      const appSet = document.querySelector('input[name="preset_app_set"]:checked');
      const preset = appSet ? appSet.value : 'default';
      if (preset === 'reference-apps') return true;
      if (preset === 'no-reference-apps') return false;
      if (preset === 'sentiment-only') return app === 'sentiment';
      return stageDefault(stage, app);
    }}
    function updateAppToggles(stage) {{
      document.querySelectorAll('.app-toggle').forEach((node) => {{
        node.hidden = !['700', '800', '900'].includes(stage);
      }});
      ['sentiment', 'subnetcalc'].forEach((app) => {{
        const select = document.querySelector(`select[name="${{app}}"]`);
        if (!select) return;
        const enabled = effectiveAppDefault(stage, app);
        const previous = select.value;
        const previousDefault = select.dataset.defaultValue || '';
        const defaultValue = enabled ? 'on' : 'off';
        select.innerHTML = '';
        [['on', 'Enabled'], ['off', 'Disabled']].forEach(([value, label]) => {{
          const option = document.createElement('option');
          option.value = value;
          option.textContent = label;
          select.append(option);
        }});
        if (previous && previous !== previousDefault) {{
          select.value = previous;
        }} else {{
          select.value = defaultValue;
        }}
        select.dataset.defaultValue = defaultValue;
        const hint = document.getElementById(`${{app}}-default-hint`);
        if (hint) hint.textContent = `Default: ${{enabled ? 'enabled' : 'disabled'}}`;
      }});
    }}
    document.body.addEventListener('change', (event) => {{
      if (event.target && event.target.name === 'stage') {{
        updateAppToggles(event.target.value);
      }}
      if (event.target && event.target.name === 'preset_app_set') {{
        updateAppToggles(document.querySelector('select[name="stage"]').value);
      }}
      if (event.target && (event.target.tagName === 'SELECT' || event.target.tagName === 'INPUT')) {{
        updateSelectedFields();
        updatePresetSummary();
        syncGuidedTabState();
      }}
    }});
    function selectVariant(variant, button) {{
      const sel = document.querySelector('select[name="variant"]');
      if (!sel) return;
      sel.value = variant;
      setSource('variant shortcut');
      sel.dispatchEvent(new Event('change', {{ bubbles: true }}));
    }}
    function selectStage(stage) {{
      const sel = document.querySelector('select[name="stage"]');
      if (!sel) return;
      sel.value = stage;
      setSource('stage ladder');
      sel.dispatchEvent(new Event('change', {{ bubbles: true }}));
    }}
    function selectAction(action) {{
      const sel = document.querySelector('select[name="action"]');
      if (!sel) return;
      sel.value = action;
      setSource('action button');
      sel.dispatchEvent(new Event('change', {{ bubbles: true }}));
    }}
    function setSource(source) {{
      document.querySelectorAll('input[name="source"]').forEach((node) => {{ node.value = source; }});
    }}
    function setSelectValue(name, value) {{
      const sel = document.querySelector(`select[name="${{name}}"]`);
      if (sel) {{ sel.value = value; return; }}
      const radio = document.querySelector(`input[name="${{name}}"][value="${{value}}"]`);
      if (radio) radio.checked = true;
    }}
    function applySetupProfile(profile) {{
      const profiles = {{
        'stage-defaults': {{
          values: {{
            preset_resource_profile: 'default',
            preset_image_distribution: 'default',
            preset_network_profile: 'default',
            preset_observability_stack: 'default',
            preset_identity_stack: 'default',
            preset_app_set: 'default',
          }},
        }},
        'minimal-local': {{
          stage: '700',
          values: {{
            preset_resource_profile: 'minimal',
            preset_image_distribution: 'pull',
            preset_network_profile: 'cilium',
            preset_observability_stack: 'default',
            preset_identity_stack: 'default',
            preset_app_set: 'no-reference-apps',
          }},
        }},
        'idp-demo': {{
          variant: 'kubernetes/kind',
          stage: '900',
          values: {{
            preset_resource_profile: 'local-idp-12gb',
            preset_image_distribution: 'local-cache',
            preset_network_profile: 'cilium',
            preset_observability_stack: 'default',
            preset_identity_stack: 'default',
            preset_app_set: 'default',
          }},
        }},
        'airplane': {{
          stage: '900',
          values: {{
            preset_resource_profile: 'airplane',
            preset_image_distribution: 'airplane',
            preset_network_profile: 'cilium',
            preset_observability_stack: 'default',
            preset_identity_stack: 'default',
            preset_app_set: 'default',
          }},
        }},
      }};
      const config = profiles[profile];
      if (!config) return;
      if (config.variant) setSelectValue('variant', config.variant);
      if (config.stage) setSelectValue('stage', config.stage);
      Object.entries(config.values).forEach(([name, value]) => setSelectValue(name, value));
      setSource('setup profile');
      setActiveSetupProfile(profile);
      const stage = document.querySelector('select[name="stage"]').value;
      updateAppToggles(stage);
      syncGuidedTabState();
      updateSelectedFields();
      updatePresetSummary();
      const trigger = document.querySelector('select[name="stage"]') || document.querySelector('select[name="preset_resource_profile"]');
      if (trigger) trigger.dispatchEvent(new Event('change', {{ bubbles: true }}));
    }}
    function setActiveSetupProfile(profile) {{
      document.querySelectorAll('.setup-card, .guided-profile-btn').forEach((node) => {{
        node.classList.toggle('active', node.dataset.profile === profile);
      }});
    }}
    function updatePresetSummary() {{
      const labels = [];
      document.querySelectorAll('input[name^="preset_"]:checked').forEach((input) => {{
        if (!input.value || input.value === 'default') return;
        const fieldset = input.closest('fieldset');
        const legend = fieldset ? fieldset.querySelector('legend') : null;
        const label = legend ? legend.textContent.trim() : input.name;
        const optionLabel = input.closest('label') ? input.closest('label').innerText.trim() : input.value;
        labels.push(`${{label}}: ${{optionLabel}}`);
      }});
      const target = document.getElementById('preset-summary-text');
      if (!target) return;
      if (!labels.length) {{
        target.textContent = 'Stage defaults';
        setActiveSetupProfile('stage-defaults');
        return;
      }}
      const visible = labels.slice(0, 2).join(' | ');
      const more = labels.length > 2 ? ` | +${{labels.length - 2}} more` : '';
      target.textContent = `${{labels.length}} override${{labels.length === 1 ? '' : 's'}}: ${{visible}}${{more}}`;
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
    function copyOutput(id, button) {{ copyCommand(id, button); }}
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
    function updateSelectedFields() {{
      document.querySelectorAll('.control-field').forEach((label) => {{
        const sel = label.querySelector('select');
        const input = label.querySelector('input');
        let selected = false;
        if (sel) {{
          if (sel.dataset.defaultValue) {{
            selected = sel.value !== sel.dataset.defaultValue;
          }} else {{
            selected = sel.value !== '';
          }}
        }}
        if (input) {{
          selected = selected || (input.type === 'radio' ? input.checked && input.value !== 'default' : input.value !== '');
        }}
        label.classList.toggle('selected', selected);
      }});
    }}
    updateAppToggles(document.querySelector('select[name="stage"]').value);
    syncGuidedTabState();
    updateSelectedFields();
    updatePresetSummary();
    try {{
      const savedTab = localStorage.getItem('platform-workflow-ui-tab');
      if (savedTab === 'expert') switchTab('expert');
    }} catch (_e) {{}}
    function applyTheme(theme) {{
      const resolved = theme === 'light' ? 'light' : 'dark';
      document.documentElement.setAttribute('data-theme', resolved);
      const button = document.getElementById('theme-switcher');
      if (button) button.setAttribute('aria-label', resolved === 'dark' ? 'Switch to light theme' : 'Switch to dark theme');
      try {{ localStorage.setItem('platform-workflow-ui-theme', resolved); }} catch (_err) {{}}
    }}
    function toggleTheme() {{
      const current = document.documentElement.getAttribute('data-theme') || 'dark';
      applyTheme(current === 'dark' ? 'light' : 'dark');
    }}
    try {{ applyTheme(localStorage.getItem('platform-workflow-ui-theme') || 'dark'); }} catch (_err) {{ applyTheme('dark'); }}
  </script>
</body>
</html>"""


def preset_panel() -> str:
    controls = []
    for name, label, options in PRESET_GROUPS:
        option_items = []
        for value, option_label in options:
            checked = ' checked' if value == "default" else ""
            option_items.append(
                f'<label class="preset-option"><input type="radio" name="{html.escape(name)}" value="{html.escape(value)}"{checked}>'
                f'<span>{html.escape(option_label)}</span></label>'
            )
        controls.append(
            f'<fieldset class="preset-column"><legend>{html.escape(label)}</legend>{"".join(option_items)}</fieldset>'
        )
    return f"""
<section class="workflow-panel presets-panel" aria-label="Setup presets">
  <div class="panel-title-row">
    <div>
      <h2>Setup presets</h2>
      <p>Choose an opinionated path first, then inspect or tune the exact overlays.</p>
    </div>
    <span id="preset-summary-compact">Curated setup profiles</span>
  </div>
  <div class="setup-grid" aria-label="Curated setup profiles">
    <div class="setup-card active" data-profile="stage-defaults">
      <span>Curated default</span>
      <strong>Stage defaults</strong>
      <small>Pure stage ladder. Good for learning the baseline.</small>
      <button type="button" onclick="applySetupProfile('stage-defaults')">Select</button>
    </div>
    <div class="setup-card" data-profile="minimal-local">
      <span>Low resource</span>
      <strong>Minimal local</strong>
      <small>Stage 700, minimal resource profile, reference apps off.</small>
      <button type="button" onclick="applySetupProfile('minimal-local')">Select</button>
    </div>
    <div class="setup-card" data-profile="idp-demo">
      <span>12 GB laptop</span>
      <strong>IDP demo</strong>
      <small>Kind stage 900 with the local IDP profile.</small>
      <button type="button" onclick="applySetupProfile('idp-demo')">Select</button>
    </div>
    <div class="setup-card" data-profile="airplane">
      <span>Offline prep</span>
      <strong>Airplane</strong>
      <small>Stage 900 with local cache and preload enabled.</small>
      <button type="button" onclick="applySetupProfile('airplane')">Select</button>
    </div>
  </div>
  <details class="fine-tune-panel detailed-view">
    <summary>Detailed view</summary>
    <h3>Individual preset controls</h3>
    <div class="ninite-grid">{''.join(controls)}</div>
  </details>
</section>
"""




def apps_panel() -> str:
    app_controls = []
    for name, label in APP_OPTIONS:
        app_controls.append(app_control(name, label, "900"))
    platform_rows = [
        ("hello-platform", "Reference platform workload", "stage 700"),
        ("apim-simulator", "API mediation surface", "stage 700"),
        ("Backstage", "Developer portal", "stage 900"),
        ("IDP core", "Identity portal/API", "stage 900"),
    ]
    rows = "".join(
        f"<li><strong>{html.escape(name)}</strong><span>{html.escape(kind)} | {html.escape(stage)}</span></li>"
        for name, kind, stage in platform_rows
    )
    return f"""
<details class="workflow-panel apps-panel">
  <summary>Apps and platform surfaces</summary>
  <div class="panel-grid">{''.join(app_controls)}</div>
  <ul class="surface-list">{rows}</ul>
</details>
"""


def app_control(name: str, label: str, stage: str) -> str:
    default = stage_default(stage, name)
    return (
        f'<label class="control-field app-toggle">{html.escape(label)}'
        f'{app_select(name, stage, name)}'
        f'<span id="{html.escape(name)}-default-hint" class="field-hint">'
        f'Default: {"enabled" if default else "disabled"}</span>'
        "</label>"
    )


def advanced_overrides_panel() -> str:
    return """
<details class="workflow-panel advanced-overrides">
  <summary>Advanced overrides</summary>
  <div class="panel-grid">
    <label class="control-field">Worker nodes <input name="custom_worker_count" type="number" min="1" step="1" inputmode="numeric" placeholder="stage default"></label>
    <label class="control-field">Node image <input name="custom_node_image" type="text" placeholder="stage default"></label>
    <label class="control-field">Backstage <select name="custom_enable_backstage"><option value="">Stage/preset default</option><option value="on">Enable</option><option value="off">Disable</option></select></label>
  </div>
  <p class="risk-note">Changing stage 100 substrate values such as worker nodes or node image may recreate or restart the cluster.</p>
</details>
"""




def preview_panel(repo_root: Path, result: dict[str, Any], payload: dict[str, Any]) -> str:
    command = html.escape(str(result.get("command", "")))
    variant = html.escape(str(payload["variant"]))
    stage = html.escape(str(result.get("stage", payload["stage"])))
    action = html.escape(str(result.get("action", payload["action"])))
    raw_action = str(result.get("action", payload["action"]))
    selection = html.escape(selection_label(str(payload.get("source") or "dropdowns")))
    intent = html.escape(intent_summary(str(result.get("action", payload["action"])), stage, variant))
    consequence = html.escape(consequence_summary(str(result.get("action", payload["action"]))))
    button_label = html.escape(action_label(raw_action))
    risk = action_risk(raw_action)
    risk_label = html.escape(risk[0])
    risk_class = html.escape(risk[1])
    stage_delta = html.escape(stage_delta_hint(stage))
    architecture = architecture_panel(result)
    presets = preset_summary_panel(result)
    warnings = warnings_panel(result)
    tfvars = generated_tfvars_panel(result)
    workflow_execute = html.escape(workflow_command(payload, standard_flag="--execute"))
    workflow_dry_run = html.escape(workflow_command(payload, standard_flag="--dry-run"))
    preflight = preflight_badges(repo_root, payload)
    hidden = hidden_inputs({**payload, "command": str(result.get("command", "")), "dry_run": ""})
    dry_run_hidden = hidden_inputs({**payload, "command": str(result.get("command", "")), "dry_run": "1"})
    return f"""
<div class="provenance-strip">
  <span class="selection-badge">Selection: {selection}</span>
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
{warnings}
{presets}
{architecture}
{tfvars}
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


def preset_summary_panel(result: dict[str, Any]) -> str:
    presets = result.get("presets")
    if not isinstance(presets, dict):
        return ""
    rows = []
    for key, label in (
        ("resource_profile", "Resource"),
        ("image_distribution", "Images"),
        ("network_profile", "Network"),
        ("observability_stack", "Observability"),
        ("identity_stack", "Identity"),
        ("app_set", "Apps"),
    ):
        value = str(presets.get(key) or "default")
        badge = "stage default" if value == "default" else "preset"
        rows.append(
            f"<div><span>{html.escape(label)}</span><strong>{html.escape(value)}</strong><em>{html.escape(badge)}</em></div>"
        )
    custom = result.get("custom_overrides")
    if isinstance(custom, list) and custom:
        rows.append(f"<div><span>Custom</span><strong>{len(custom)} override(s)</strong><em>custom</em></div>")
    return f"""
<details class="preset-summary-panel">
  <summary>Effective presets</summary>
  <div class="preset-grid">{''.join(rows)}</div>
</details>
"""


def warnings_panel(result: dict[str, Any]) -> str:
    warnings = result.get("warnings")
    if not isinstance(warnings, list) or not warnings:
        return ""
    rows = "".join(f"<li>{html.escape(str(item))}</li>" for item in warnings)
    return f'<div class="warning-panel"><strong>Heads up</strong><ul>{rows}</ul></div>'


def generated_tfvars_panel(result: dict[str, Any]) -> str:
    tfvars = result.get("generated_tfvars")
    path = result.get("tfvars_file")
    if not tfvars:
        return ""
    output_id = "generated-tfvars-text"
    return f"""
<details class="tfvars-panel">
  <summary>Generated operator tfvars</summary>
  <div class="command-head">
    <h2>{html.escape(str(path or "Generated tfvars"))}</h2>
    <button type="button" title="Copy generated tfvars" onclick="copyCommand('{output_id}', this)">Copy</button>
  </div>
  <pre id="{output_id}" class="output">{html.escape(str(tfvars))}</pre>
</details>
"""


def architecture_panel(result: dict[str, Any]) -> str:
    variant = result.get("variant")
    if not isinstance(variant, dict):
        return ""
    stage_metadata = result.get("stage_metadata")
    contexts = result.get("contexts")
    contracts = result.get("contract_requirements")
    effective_config = result.get("effective_config")
    context_id = ""
    if isinstance(stage_metadata, dict):
        context_id = str(stage_metadata.get("context") or "")
    context_labels = ", ".join(
        html.escape(str(context.get("label") or context.get("id") or ""))
        for context in contexts
        if isinstance(context, dict)
    ) if isinstance(contexts, list) else ""
    contract_labels = ", ".join(
        html.escape(str(contract.get("label") or contract.get("id") or ""))
        for contract in contracts
        if isinstance(contract, dict)
    ) if isinstance(contracts, list) else ""
    precedence = ""
    if isinstance(effective_config, dict) and isinstance(effective_config.get("source_precedence"), list):
        precedence = " -> ".join(str(source).replace("_", " ") for source in effective_config["source_precedence"])
    rows = [
        ("Adapter", str(variant.get("class") or "")),
        ("Lifecycle", str(variant.get("lifecycle_mode") or "")),
        ("State", str(variant.get("state_scope") or "")),
        ("Stage context", context_id),
        ("Variant contexts", context_labels),
        ("Contracts", contract_labels),
        ("Config precedence", precedence),
    ]
    rendered_rows = []
    for label, value in rows:
        if not value:
            continue
        rendered_rows.append(
            f"<div><span>{html.escape(label)}</span><strong>{html.escape(value)}</strong></div>"
        )
    if not rendered_rows:
        return ""
    return f"""
<details class="architecture-panel">
  <summary>Variant contract</summary>
  <div class="architecture-grid">{''.join(rendered_rows)}</div>
</details>
"""


def prereq_tools() -> list[dict[str, str]]:
    grouped = tool_group_status("OpenTofu / Terraform", ["tofu", "terraform"])
    tools = [
        grouped,
        tool_status("uv"),
        tool_status("python3"),
        tool_status("bun"),
        tool_status("kubectl"),
        tool_status("jq"),
        tool_status("docker"),
    ]
    return tools


def tool_group_status(label: str, commands: list[str]) -> dict[str, str]:
    found = [tool_status(command) for command in commands if shutil.which(command)]
    if not found:
        return {"name": label, "state": "missing", "detail": f"Expected one of: {', '.join(commands)}"}
    first = found[0]
    return {"name": label, "state": "ready", "detail": f"{first['name']}: {first['detail']}"}


def tool_status(command: str) -> dict[str, str]:
    path = shutil.which(command)
    if not path:
        return {"name": command, "state": "missing", "detail": "not found in PATH"}
    version = tool_version(command)
    detail = version or path
    return {"name": command, "state": "ready", "detail": detail}


def tool_version(command: str) -> str:
    version_args = {
        "python3": ["python3", "--version"],
        "docker": ["docker", "--version"],
        "kubectl": ["kubectl", "version", "--client=true"],
    }
    args = version_args.get(command, [command, "--version"])
    try:
        result = subprocess.run(args, text=True, capture_output=True, timeout=2, check=False)
    except (OSError, subprocess.SubprocessError):
        return ""
    output = (result.stdout or result.stderr or "").strip().splitlines()
    return output[0] if output else ""


def inventory_panel(payload: dict[str, Any], tools: list[dict[str, str]] | None = None) -> str:
    health = payload.get("health_summary") if isinstance(payload.get("health_summary"), dict) else {}
    overall = html.escape(str(health.get("overall_state") or payload.get("overall_state") or "unknown"))
    active = html.escape(str(health.get("active_variant") or payload.get("active_variant") or "none"))
    variant_rows = prereq_variant_rows(payload)
    runtime_rows = prereq_runtime_rows(payload)
    registry_rows = prereq_registry_rows(payload)
    tool_rows = prereq_tool_rows(tools or [])
    generated_at = html.escape(str(payload.get("generated_at") or ""))
    return f"""
<details class="inventory prereqs workflow-panel">
  <summary class="inventory-head">
    <h2>Prereqs</h2>
    <span>Overall <strong>{overall}</strong></span>
    <span>Active variant <strong>{active}</strong></span>
    <time>{generated_at}</time>
  </summary>
  <div class="prereq-groups">
    <div>
      <h3>CLI tools</h3>
      <div class="inventory-grid prereq-grid">{tool_rows}</div>
    </div>
    <div>
      <h3>Host runtimes</h3>
      <div class="inventory-grid prereq-grid">{runtime_rows}</div>
    </div>
    <div>
      <h3>Registry auth</h3>
      <div class="inventory-grid prereq-grid">{registry_rows}</div>
    </div>
    <div>
      <h3>Variant readiness</h3>
      <div class="inventory-grid prereq-grid">{variant_rows}</div>
    </div>
  </div>
</details>
"""


def prereq_variant_rows(payload: dict[str, Any]) -> str:
    variants = payload.get("variants")
    order = payload.get("variants_order")
    rows = []
    if isinstance(variants, dict) and isinstance(order, list):
        for variant_id in order:
            item = variants.get(str(variant_id), {})
            if not isinstance(item, dict):
                continue
            blockers = item.get("blockers")
            if isinstance(blockers, list) and blockers:
                blocker_text = ", ".join(str(blocker) for blocker in blockers[:3])
            else:
                blocker_text = "No blockers reported"
            rows.append(
                f"""
<div class="inventory-card {prereq_state_class(str(item.get('state') or 'unknown'))}">
  <span>{html.escape(str(variant_id))}</span>
  <strong>{html.escape(str(item.get('state') or 'unknown'))}</strong>
  <small>{html.escape(blocker_text)}</small>
</div>
"""
            )
    if not rows:
        rows.append('<div class="inventory-card"><span>Status</span><strong>unknown</strong><small>No variant status rows reported.</small></div>')
    return "".join(rows)


def prereq_runtime_rows(payload: dict[str, Any]) -> str:
    runtimes = payload.get("host_runtimes")
    order = payload.get("host_runtimes_order")
    rows = []
    if isinstance(runtimes, dict) and isinstance(order, list):
        for runtime_id in order:
            item = runtimes.get(str(runtime_id), {})
            if not isinstance(item, dict):
                continue
            state = "ready" if item.get("available") and item.get("running") else ("missing" if not item.get("available") else "stopped")
            rows.append(prereq_card(str(item.get("name") or runtime_id), state, str(item.get("detail") or "")))
    return "".join(rows) or prereq_card("Host runtime", "unknown", "No runtime status reported")


def prereq_registry_rows(payload: dict[str, Any]) -> str:
    registries = payload.get("registry_auth")
    order = payload.get("registry_auth_order")
    rows = []
    if isinstance(registries, dict) and isinstance(order, list):
        for registry_id in order:
            item = registries.get(str(registry_id), {})
            if not isinstance(item, dict):
                continue
            state = "ready" if item.get("authenticated") else "missing"
            rows.append(prereq_card(str(item.get("registry") or registry_id), state, str(item.get("detail") or item.get("source") or "")))
    return "".join(rows) or prereq_card("Registry auth", "unknown", "No registry auth status reported")


def prereq_tool_rows(tools: list[dict[str, str]]) -> str:
    return "".join(prereq_card(tool["name"], tool["state"], tool["detail"]) for tool in tools)


def prereq_card(name: str, state: str, detail: str) -> str:
    return f"""
<div class="inventory-card {prereq_state_class(state)}">
  <span>{html.escape(name)}</span>
  <strong>{html.escape(state)}</strong>
  <small>{html.escape(detail)}</small>
</div>
"""


def prereq_state_class(state: str) -> str:
    normalized = state.lower()
    if normalized in {"ready", "running", "ok"}:
        return "ready"
    if normalized in {"missing", "blocked", "conflict", "failed"}:
        return "blocked"
    if normalized in {"stopped", "absent", "unknown"}:
        return "warn"
    return "neutral"


def intent_summary(action: str, stage: str, variant: str) -> str:
    target = variant_to_target(variant)
    if action == "readiness":
        return f"Check prerequisites and readiness for {target}."
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
    if action == "readiness":
        return "Read-only. Streams prerequisite checks and remediation hints."
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
    if action in {"readiness", "plan", "status", "show-urls", "check-health", "check-security", "check-rbac"}:
        return ("Read-only", "readonly")
    if action == "apply":
        return ("Mutating", "mutating")
    if action in {"reset", "state-reset"}:
        return ("Destructive", "destructive")
    return ("Command", "neutral")


def selection_label(source: str) -> str:
    labels = {
        "dropdowns": "Dropdowns",
        "variant shortcut": "Variant shortcut",
        "stage ladder": "Stage ladder",
        "action button": "Action shortcut",
        "reset button": "Reset shortcut",
        "setup profile": "Setup profile",
    }
    return labels.get(source, "Manual selection")


def stage_delta_hint(stage: str) -> str:
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
        badges.append('<span class="preflight-badge neutral">Checked at execution</span>')
    return "".join(badges)


def action_label(action: str) -> str:
    labels = {
        "plan": "Plan",
        "readiness": "Readiness",
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
    diagnostics = ""
    if not job.running:
        next_html = next_actions(job.payload, job.succeeded)
        diagnostics = diagnostic_bundle(job)
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
  {diagnostics}
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


def diagnostic_bundle(job) -> str:
    bundle = {
        "variant": job.payload.get("variant"),
        "stage": job.payload.get("stage"),
        "action": job.payload.get("action"),
        "presets": {
            "resource_profile": job.payload.get("preset_resource_profile", "default"),
            "image_distribution": job.payload.get("preset_image_distribution", "default"),
            "network_profile": job.payload.get("preset_network_profile", "default"),
            "observability_stack": job.payload.get("preset_observability_stack", "default"),
            "identity_stack": job.payload.get("preset_identity_stack", "default"),
            "app_set": job.payload.get("preset_app_set", "default"),
        },
        "custom_overrides": {
            "worker_count": job.payload.get("custom_worker_count", ""),
            "node_image": job.payload.get("custom_node_image", ""),
            "enable_backstage": job.payload.get("custom_enable_backstage", ""),
            "sentiment": job.payload.get("sentiment", ""),
            "subnetcalc": job.payload.get("subnetcalc", ""),
        },
        "command": " ".join(job.command),
        "exit_code": job.returncode,
        "last_output": "\n".join((job.text or "").splitlines()[-80:]),
        "docs": ["docs/ddd/ubiquitous-language.md", "docs/plans/guided-workflow-variant-presets-plan.md"],
    }
    text = json.dumps(bundle, indent=2, sort_keys=True)
    bundle_id = f"diagnostic-bundle-{job.id}"
    return f"""
<details class="diagnostic-bundle">
  <summary>Diagnostic bundle</summary>
  <div class="command-head">
    <h2>Copy this into your LLM or issue</h2>
    <button type="button" title="Copy diagnostic bundle" onclick="copyCommand('{bundle_id}', this)">Copy</button>
  </div>
  <pre id="{bundle_id}" class="output">{html.escape(text)}</pre>
</details>
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


def stage_display_label(stage: str) -> str:
    return stage


def select(name: str, options: list[tuple[str, str]], selected: str) -> str:
    rendered = []
    for value, label in options:
        attrs = ' selected' if value == selected else ""
        rendered.append(f'<option value="{html.escape(value)}"{attrs}>{html.escape(label)}</option>')
    return f'<select name="{html.escape(name)}">' + "".join(rendered) + "</select>"


def app_select(name: str, stage: str, app: str) -> str:
    default = stage_default(stage, app)
    selected = "on" if default else "off"
    options = [
        ("on", "Enabled"),
        ("off", "Disabled"),
    ]
    rendered = []
    for value, label in options:
        attrs = ' selected' if value == selected else ""
        rendered.append(f'<option value="{html.escape(value)}"{attrs}>{html.escape(label)}</option>')
    return f'<select name="{html.escape(name)}" data-default-value="{html.escape(selected)}">' + "".join(rendered) + "</select>"


def hidden_inputs(payload: dict[str, Any]) -> str:
    fields = []
    for key, value in payload.items():
        fields.append(f'<input type="hidden" name="{html.escape(str(key))}" value="{html.escape(str(value))}">')
    return "\n".join(fields)


def styles() -> str:
    return """
:root { color-scheme: dark; --ink:#eef7f2; --muted:#a9b9b1; --paper:#101817; --panel:#16211f; --panel-2:#1d2a27; --line:#314540; --accent:#2fb39f; --accent-strong:#58d5bf; --blue:#8ab4ff; --amber:#f2c94c; --danger:#ff8a65; --code:#08110f; --shadow:rgba(0,0,0,.36); --selection:#203d38; --selection-line:#2fb39f; --tooltip-bg:#f6fff9; --tooltip-text:#101817; --tooltip-border:#58d5bf; }
html[data-theme="light"] { color-scheme: light; --ink:#17201d; --muted:#607169; --paper:#f6f8f6; --panel:#ffffff; --panel-2:#edf7f3; --line:#ccd9d3; --accent:#00796b; --accent-strong:#005f54; --blue:#285fb8; --amber:#9a6700; --danger:#b14425; --code:#101b18; --shadow:rgba(18,36,31,.12); --selection:#e6f5ef; --selection-line:#00796b; --tooltip-bg:#10231f; --tooltip-text:#f6fff9; --tooltip-border:#00796b; }
html[data-theme="dark"] { color-scheme: dark; }
* { box-sizing: border-box; }
html, body { min-height:100%; }
body { margin:0; min-height:100vh; overflow:auto; font-family: ui-sans-serif, system-ui, sans-serif; color:var(--ink); background:radial-gradient(circle at 20% -10%, rgba(47,179,159,.22), transparent 34rem), linear-gradient(180deg, var(--paper) 0, #0c1312 100%); }
html[data-theme="light"] body { background:radial-gradient(circle at 20% -10%, rgba(0,121,107,.14), transparent 34rem), linear-gradient(180deg, #ffffff 0, var(--paper) 100%); }
main { width:calc(100vw - 40px); min-height:100vh; margin:0 auto; padding:18px 0; display:flex; flex-direction:column; gap:12px; }
section, .result { background:var(--panel); border:1px solid var(--line); box-shadow:0 10px 28px var(--shadow); }
main > form { display:block; border:1px solid var(--line); box-shadow:0 10px 28px var(--shadow); background:var(--panel); }
label { display:grid; gap:6px; color:var(--muted); font-weight:800; font-size:.78rem; text-transform:uppercase; }
.control-field.selected { background:linear-gradient(90deg, var(--selection), transparent); }
select, input, button { min-height:40px; border:1px solid var(--line); background:var(--panel); color:var(--ink); padding:8px 10px; font:inherit; }
select, input { width:100%; min-width:0; font-weight:700; overflow:hidden; text-overflow:ellipsis; }
button { cursor:pointer; background:var(--accent); color:white; border-color:var(--accent); font-weight:800; }
button:hover { background:var(--accent-strong); }
select:focus-visible, input:focus-visible, button:focus-visible { outline:3px solid var(--amber); outline-offset:2px; }
button[data-tooltip] { position:relative; }
button[data-tooltip]::after { content:attr(data-tooltip); position:absolute; left:50%; bottom:calc(100% + 10px); z-index:20; transform:translateX(-50%); width:max-content; min-width:150px; max-width:320px; padding:8px 10px; border:1px solid var(--tooltip-border); background:var(--tooltip-bg); color:var(--tooltip-text); box-shadow:0 12px 28px var(--shadow); font-size:.78rem; line-height:1.35; font-weight:850; text-align:left; white-space:normal; opacity:0; pointer-events:none; }
button[data-tooltip]::before { content:""; position:absolute; left:50%; bottom:calc(100% + 5px); z-index:21; transform:translateX(-50%) rotate(45deg); width:9px; height:9px; border-right:1px solid var(--tooltip-border); border-bottom:1px solid var(--tooltip-border); background:var(--tooltip-bg); opacity:0; pointer-events:none; }
button[data-tooltip]:hover::after, button[data-tooltip]:focus-visible::after, button[data-tooltip]:hover::before, button[data-tooltip]:focus-visible::before { opacity:1; }
.result { display:flex; flex-direction:column; min-height:260px; padding:16px; overflow:auto; }
.theme-switcher { width:44px; min-width:44px; aspect-ratio:1; padding:0; display:grid; place-items:center; background:transparent; color:var(--amber); border-color:var(--line); border-width:1px; }
.theme-icon { width:20px; height:20px; fill:none; stroke:currentColor; stroke-width:2; stroke-linecap:round; stroke-linejoin:round; }
.theme-icon-moon { display:none; }
html[data-theme="light"] .theme-icon-sun { display:none; }
html[data-theme="light"] .theme-icon-moon { display:block; color:var(--blue); }
.tab-bar { display:flex; align-items:stretch; justify-content:space-between; border-bottom:1px solid var(--line); background:var(--panel-2); }
.tab-nav { display:flex; }
.tab-btn { min-height:46px; background:transparent; color:var(--muted); border:0; border-bottom:3px solid transparent; border-radius:0; padding:0 22px; font-weight:900; font-size:.8rem; letter-spacing:.04em; text-transform:uppercase; }
.tab-btn.active { color:var(--ink); border-bottom-color:var(--accent); background:transparent; }
.tab-btn:hover { color:var(--ink); background:color-mix(in srgb, var(--panel-2) 60%, var(--accent) 8%); }
.tab-bar-end { display:flex; align-items:center; gap:8px; padding:0 10px; }
.tab-panel[hidden] { display:none; }
.preset-summary { border:1px solid var(--line); background:var(--panel); padding:7px 10px; min-height:36px; }
.preset-summary span { display:block; color:var(--muted); font-size:.66rem; text-transform:uppercase; font-weight:800; }
.preset-summary strong { display:block; margin-top:2px; overflow-wrap:anywhere; font-size:.82rem; }
.guided-layout { display:flex; flex-direction:column; }
.guided-section { padding:14px 16px; border-bottom:1px solid var(--line); }
.guided-section:last-child { border-bottom:0; }
.guided-section-head { display:flex; align-items:center; gap:10px; margin-bottom:12px; }
.guided-step { display:grid; place-items:center; width:22px; height:22px; border-radius:50%; background:var(--accent); color:white; font-size:.7rem; font-weight:900; flex-shrink:0; }
.guided-section-head strong { font-size:.88rem; font-weight:900; }
.guided-section-head small { color:var(--muted); font-size:.75rem; font-weight:700; margin-left:4px; }
.guided-group { display:flex; flex-wrap:wrap; gap:8px; }
.guided-btn { min-height:54px; display:grid; gap:2px; align-content:center; background:var(--panel-2); color:var(--ink); border-color:var(--line); padding:8px 14px; text-align:left; }
.guided-btn strong { font-size:.9rem; display:block; font-weight:900; line-height:1.2; }
.guided-btn span { display:block; color:var(--muted); font-size:.72rem; font-weight:700; line-height:1.3; }
.guided-btn:hover { background:color-mix(in srgb, var(--panel-2) 60%, var(--accent) 12%); color:var(--ink); border-color:var(--accent); }
.guided-btn.active { background:var(--selection); border-color:var(--selection-line); box-shadow:inset 3px 0 0 var(--selection-line); color:var(--ink); }
.guided-btn.active strong { color:var(--accent-strong); }
.guided-variant-btn { min-width:148px; }
.guided-stage-btn { min-width:74px; }
.guided-profile-btn { flex:1 1 180px; max-width:300px; }
.guided-action-btn { min-width:120px; }
.expert-layout { display:flex; flex-direction:column; }
.expert-controls { display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:12px; padding:14px; border-bottom:1px solid var(--line); }
.workflow-panel { border:1px solid var(--line); border-top:0; background:color-mix(in srgb, var(--panel) 88%, var(--accent) 12%); padding:10px 14px; }
.workflow-panel summary, .fine-tune-panel summary, .preset-summary-panel summary, .tfvars-panel summary, .diagnostic-bundle summary { cursor:pointer; color:var(--muted); font-size:.78rem; font-weight:800; text-transform:uppercase; }
.panel-title-row { display:flex; justify-content:space-between; gap:14px; align-items:start; }
.panel-title-row h2 { margin:0; font-size:1rem; line-height:1.1; }
.panel-title-row p { margin:5px 0 0; color:var(--muted); font-weight:750; font-size:.86rem; }
.panel-title-row > span { color:var(--muted); font-size:.72rem; font-weight:900; text-transform:uppercase; white-space:nowrap; }
.panel-grid { display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:10px; margin-top:10px; }
.setup-grid { display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:10px; margin-top:10px; }
.setup-card { display:grid; grid-template-rows:auto auto 1fr auto; gap:6px; min-width:0; border:1px solid var(--line); background:var(--panel); padding:10px; box-shadow:0 1px 0 var(--shadow); }
.setup-card.active { border-color:var(--selection-line); box-shadow:inset 4px 0 0 var(--selection-line), 0 1px 0 var(--shadow); background:var(--selection); }
.setup-card span { color:var(--muted); font-size:.68rem; font-weight:800; text-transform:uppercase; }
.setup-card strong { display:block; overflow-wrap:anywhere; }
.setup-card small { color:var(--muted); font-weight:700; line-height:1.35; }
.setup-card button { margin-top:4px; min-height:34px; padding:5px 9px; }
.fine-tune-panel { margin-top:12px; border-top:1px solid var(--line); padding-top:10px; }
.fine-tune-panel h3 { margin:10px 0 0; font-size:.86rem; color:var(--muted); text-transform:uppercase; }
.ninite-grid { display:grid; grid-template-columns:repeat(3, minmax(180px, 1fr)); gap:18px 28px; margin-top:12px; padding:10px; background:var(--panel); border:1px solid var(--line); }
.preset-column { min-width:0; border:0; padding:0; margin:0; }
.preset-column legend { margin:0 0 8px; padding:0; color:var(--ink); font-size:1.05rem; font-weight:900; }
.preset-option { display:grid; grid-template-columns:16px minmax(0, 1fr); align-items:center; gap:6px; margin:3px 0; color:var(--ink); font-size:.9rem; font-weight:650; text-transform:none; }
.preset-option input { width:14px; min-height:14px; padding:0; accent-color:var(--accent); }
.preset-option span { overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.surface-list { display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:8px; list-style:none; padding:0; margin:12px 0 0; }
.surface-list li { border:1px solid var(--line); background:var(--panel); padding:8px; min-width:0; }
.surface-list strong, .surface-list span { display:block; overflow-wrap:anywhere; }
.surface-list span { margin-top:4px; color:var(--muted); font-size:.75rem; font-weight:800; }
.field-hint { color:var(--muted); font-size:.72rem; font-weight:800; text-transform:none; }
.source-badge { display:inline-flex; border:1px solid var(--line); padding:2px 6px; background:var(--panel-2); color:var(--muted); font-size:.66rem; font-weight:800; text-transform:uppercase; }
.risk-note { margin:10px 0 0; color:#8a5b00; font-size:.86rem; font-weight:800; }
.inventory { padding:10px 12px; }
.inventory-head { display:flex; align-items:center; gap:10px; flex-wrap:wrap; color:var(--muted); font-size:.76rem; font-weight:800; text-transform:uppercase; cursor:pointer; }
.inventory-head h2 { margin:0 auto 0 0; font-size:.8rem; color:var(--muted); }
.inventory-head strong { color:var(--ink); }
.inventory-grid { display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:8px; margin-top:8px; }
.inventory-card { border:1px solid var(--line); background:var(--panel-2); padding:8px; min-width:0; }
.prereq-groups { display:grid; gap:12px; margin-top:10px; }
.prereq-groups h3 { margin:0; color:var(--muted); font-size:.74rem; font-weight:900; text-transform:uppercase; }
.prereq-grid { grid-template-columns:repeat(4, minmax(0, 1fr)); }
.inventory-card.ready { border-color:var(--accent); box-shadow:inset 3px 0 0 var(--accent); }
.inventory-card.warn { border-color:var(--amber); box-shadow:inset 3px 0 0 var(--amber); }
.inventory-card.blocked { border-color:var(--danger); box-shadow:inset 3px 0 0 var(--danger); }
.inventory-card span { display:block; color:var(--muted); font-size:.7rem; font-weight:800; text-transform:uppercase; }
.inventory-card strong { display:block; margin-top:3px; }
.inventory-card small { display:block; margin-top:4px; color:var(--muted); overflow-wrap:anywhere; }
.summary { display:grid; grid-template-columns:repeat(3, minmax(0, 1fr)); gap:10px; margin-bottom:16px; }
.summary div { border:1px solid var(--line); padding:10px; background:var(--panel-2); }
.summary span { display:block; color:var(--muted); text-transform:uppercase; font-size:.72rem; font-weight:800; }
.summary strong { display:block; margin-top:6px; }
.provenance-strip { display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin-bottom:12px; }
.selection-badge, .risk-badge, .preflight-badge { display:inline-flex; align-items:center; min-height:28px; border:1px solid var(--line); background:var(--panel-2); padding:4px 8px; font-size:.75rem; font-weight:800; text-transform:uppercase; }
.risk-badge.readonly, .preflight-badge.ok { border-color:var(--accent); color:var(--accent); }
.risk-badge.mutating { border-color:#8a5b00; color:#8a5b00; }
.risk-badge.destructive, .preflight-badge.blocked { border-color:var(--danger); color:var(--danger); }
.preflight-badge.neutral, .risk-badge.neutral { color:var(--muted); }
.stage-delta { margin:-6px 0 14px; color:var(--muted); font-size:.86rem; font-weight:700; }
.intent-summary { display:grid; grid-template-columns:1fr 1fr; gap:10px; margin-bottom:16px; }
.intent-summary div { border:1px solid var(--line); padding:10px; background:var(--selection); }
.intent-summary span { display:block; color:var(--muted); text-transform:uppercase; font-size:.72rem; font-weight:800; }
.intent-summary strong { display:block; margin-top:6px; line-height:1.35; }
.warning-panel { border:1px solid #8a5b00; background:#fff7dd; color:#5b3a00; padding:10px; margin-bottom:14px; font-weight:800; }
.warning-panel ul { margin:6px 0 0; padding-left:18px; }
.preset-summary-panel, .tfvars-panel, .diagnostic-bundle { margin-bottom:14px; border:1px solid var(--line); background:var(--panel-2); padding:10px; }
.preset-grid { display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:8px; margin-top:10px; }
.preset-grid div { border:1px solid var(--line); background:var(--panel); padding:8px; min-width:0; }
.preset-grid span { display:block; color:var(--muted); text-transform:uppercase; font-size:.68rem; font-weight:800; }
.preset-grid strong { display:block; margin-top:4px; overflow-wrap:anywhere; }
.preset-grid em { display:inline-flex; margin-top:6px; color:var(--accent); font-size:.68rem; font-style:normal; font-weight:800; text-transform:uppercase; }
.architecture-panel { margin-bottom:14px; border:1px solid var(--line); background:var(--panel-2); padding:10px; }
.architecture-panel summary { cursor:pointer; color:var(--muted); font-size:.78rem; font-weight:800; text-transform:uppercase; }
.architecture-grid { display:grid; grid-template-columns:repeat(4, minmax(0, 1fr)); gap:8px; margin-top:10px; }
.architecture-grid div { border:1px solid var(--line); background:var(--panel); padding:8px; min-width:0; }
.architecture-grid span { display:block; color:var(--muted); text-transform:uppercase; font-size:.68rem; font-weight:800; }
.architecture-grid strong { display:block; margin-top:5px; overflow-wrap:anywhere; line-height:1.3; font-size:.86rem; }
.history { margin-bottom:16px; border:1px solid var(--line); background:var(--panel-2); padding:10px 12px; }
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
.command-tab { background:var(--panel); color:var(--accent-strong); border-color:var(--accent); }
.command-tab.active { background:var(--ink); color:white; border-color:var(--ink); }
.command-pane[hidden] { display:none; }
pre { margin:0; padding:14px; background:var(--code); color:#e5fff7; overflow:auto; white-space:pre; line-height:1.45; }
.command { min-height:90px; max-height:220px; font-weight:800; color:#8ee8ff; }
.latest-output { margin-top:16px; border-top:1px solid var(--line); padding-top:12px; min-height:0; }
.output-drawer { border:1px solid var(--line); background:var(--panel-2); padding:10px; margin-top:8px; }
.output-drawer summary { cursor:pointer; color:var(--muted); font-size:.78rem; font-weight:800; text-transform:uppercase; }
.output-meta, .result-header { display:flex; gap:8px; flex-wrap:wrap; color:var(--muted); font-size:.76rem; font-weight:800; text-transform:uppercase; margin-bottom:8px; }
.result-header { border:1px solid var(--line); background:var(--panel-2); padding:8px; }
.result-header strong { color:var(--ink); text-transform:none; }
.latest-output p { margin:0 0 8px; color:var(--muted); font-family:ui-monospace, monospace; font-size:.82rem; overflow:auto; white-space:nowrap; }
.latest-output .output { max-height:220px; }
.job { display:flex; flex-direction:column; min-height:360px; max-height:75vh; }
.output-controls { display:flex; gap:8px; align-items:center; margin-bottom:8px; flex-wrap:wrap; }
.output-controls span { color:var(--muted); font-size:.78rem; font-weight:800; text-transform:uppercase; }
.output-controls button { min-height:32px; padding:5px 9px; }
.output { flex:1 1 auto; min-height:0; max-height:45vh; }
.preview-error { display:flex; flex-direction:column; min-height:220px; gap:10px; }
.preview-error-output { max-height:50vh; overflow:auto; }
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
.dry-run:hover { background:var(--selection); }
@media (max-width: 900px) { .summary, .intent-summary, .architecture-grid, .preset-grid, .panel-grid, .setup-grid, .inventory-grid, .surface-list, .history li, .expert-controls { grid-template-columns:1fr; display:grid; } .guided-stages { flex-direction:row; flex-wrap:wrap; } .guided-profile-btn { max-width:none; } .ninite-grid { grid-template-columns:1fr; } .panel-title-row { display:grid; } }
"""


app = create_app()
