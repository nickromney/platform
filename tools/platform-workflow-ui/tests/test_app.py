from __future__ import annotations

import stat
import time
from pathlib import Path

from fastapi.testclient import TestClient

from platform_workflow_ui.main import create_app
from platform_workflow_ui.workflow import next_stages, stage_has_app_toggles


def write_workflow_stub(repo_root: Path) -> None:
    scripts = repo_root / "scripts"
    scripts.mkdir()
    workflow = scripts / "platform-workflow.sh"
    workflow.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  options)
    printf '{"variants":[{"id":"kind","path":"kubernetes/kind"},{"id":"lima","path":"kubernetes/lima"},{"id":"slicer","path":"kubernetes/slicer"}],"stages":[{"id":"900","label":"sso"}],"actions":["plan","apply"]}\\n'
    ;;
  preview)
    variant="kind"; stage="900"; action="apply"; auto_approve=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --variant) variant="$2"; shift 2 ;;
        --stage) stage="$2"; shift 2 ;;
        --action) action="$2"; shift 2 ;;
        --auto-approve) auto_approve=" AUTO_APPROVE=1"; shift ;;
        *) shift ;;
      esac
    done
    if [[ "$action" == "reset" || "$action" == "state-reset" || "$action" == "status" || "$action" == "show-urls" ]]; then
      command="make -C kubernetes/${variant} ${action}${auto_approve}"
    else
      command="make -C kubernetes/${variant} ${stage} ${action}${auto_approve}"
    fi
    if [[ "$action" == "reset" || "$action" == "state-reset" || "$action" == "status" || "$action" == "show-urls" ]]; then
      printf '{"variant":{"id":"%s","path":"kubernetes/%s","class":"local-created-cluster","lifecycle_mode":"create","state_scope":"single-local"},"stage":"%s","stage_metadata":{"context":"platform-stack"},"contexts":[{"id":"local-substrate","label":"Local substrate"},{"id":"platform-stack","label":"Platform stack"}],"contract_requirements":[{"id":"cluster-access","label":"Cluster access"},{"id":"identity","label":"Identity"}],"effective_config":{"source_precedence":["stage_baseline","variant_defaults","context_defaults","preset_overlays","custom_overrides"]},"action":"%s","command":"%s"}\\n' "$variant" "$variant" "$stage" "$action" "$command"
    else
      printf '{"variant":{"id":"%s","path":"kubernetes/%s","class":"local-created-cluster","lifecycle_mode":"create","state_scope":"single-local"},"stage":"%s","stage_metadata":{"context":"platform-stack"},"contexts":[{"id":"local-substrate","label":"Local substrate"},{"id":"platform-stack","label":"Platform stack"}],"contract_requirements":[{"id":"cluster-access","label":"Cluster access"},{"id":"identity","label":"Identity"}],"effective_config":{"source_precedence":["stage_baseline","variant_defaults","context_defaults","preset_overlays","custom_overrides"]},"action":"%s","command":"%s"}\\n' "$variant" "$variant" "$stage" "$action" "$command"
    fi
    ;;
  apply)
    echo "OK   stage complete"
    ;;
esac
""",
        encoding="utf-8",
    )
    workflow.chmod(workflow.stat().st_mode | stat.S_IXUSR)
    inventory = scripts / "platform-inventory.sh"
    inventory.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
printf '{"schema_version":"0.1","variant":"kind","stage":"900","generated_at":"2026-05-03T12:00:00Z","health_summary":{"overall_state":"ready","active_variant":"kind"},"variants_order":["kind","lima","slicer"],"variants":{"kind":{"state":"ready","blockers":[]},"lima":{"state":"absent","blockers":["Lima stopped"]},"slicer":{"state":"absent","blockers":[]}}}\\n'
""",
        encoding="utf-8",
    )
    inventory.chmod(inventory.stat().st_mode | stat.S_IXUSR)


def write_preview_failure_workflow_stub(repo_root: Path) -> None:
    scripts = repo_root / "scripts"
    scripts.mkdir()
    workflow = scripts / "platform-workflow.sh"
    workflow.write_text(
        """#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  options)
    printf '{"variants":[{"id":"kind","path":"kubernetes/kind"},{"id":"lima","path":"kubernetes/lima"},{"id":"slicer","path":"kubernetes/slicer"}],"stages":[{"id":"900","label":"sso"}],"actions":["plan","apply"]}\\n'
    ;;
  preview)
    for i in $(seq 1 120); do
      printf 'missing prereq line %03d: install the missing dependency before apply\\n' "$i" >&2
    done
    exit 42
    ;;
esac
""",
        encoding="utf-8",
    )
    workflow.chmod(workflow.stat().st_mode | stat.S_IXUSR)


def test_app_serves_htmx_page_and_static_asset(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    page = client.get("/")

    assert page.status_code == 200
    assert 'hx-post="/preview"' in page.text
    assert 'value="state-reset"' in page.text
    assert "Action" in page.text
    assert 'id="tab-guided"' in page.text
    assert 'id="tab-expert"' in page.text
    assert 'class="tab-btn active"' in page.text
    assert "guided-variant-btn" in page.text
    assert "guided-stage-btn" in page.text
    assert 'data-stage="100"' in page.text
    assert 'data-stage="900"' in page.text
    assert 'data-stage="950-local-idp"' not in page.text
    assert '<option value="950-local-idp">' not in page.text
    assert 'data-action="plan"' in page.text
    assert 'data-action="apply"' in page.text
    assert 'onclick="selectAction(' in page.text
    assert "/static/htmx.min.js" in page.text
    assert "FastAPI + HTMX, no Node build" not in page.text
    assert 'data-variant="kubernetes/kind"' in page.text
    assert 'data-variant="kubernetes/lima"' in page.text
    assert 'data-variant="kubernetes/slicer"' in page.text
    assert 'name="variant"' in page.text
    assert 'name="target"' not in page.text
    assert "syncGuidedTabState()" in page.text
    assert "updateQuickActionState()" not in page.text
    assert "selectStage(stage)" in page.text
    assert "sel.dispatchEvent(new Event('change', { bubbles: true }))" in page.text
    assert "htmx.trigger(form, 'submit')" not in page.text
    assert "form.requestSubmit()" not in page.text
    assert "Preview</button>" not in page.text
    assert '<section id="history" class="history" aria-label="Recent commands" hidden>' in page.text
    assert "Default: enabled" in page.text
    assert "Stage default: enabled" not in page.text
    assert "Enabled" in page.text
    assert "Disabled" in page.text
    assert 'name="sentiment" data-default-value="on"><option value="on" selected>Enabled</option><option value="off">Disabled</option>' in page.text
    assert 'name="subnetcalc" data-default-value="on"><option value="on" selected>Enabled</option><option value="off">Disabled</option>' in page.text
    assert "Enable sentiment (stage default)" not in page.text
    assert "width:calc(100vw - 40px)" in page.text
    assert "width:min(1480px" not in page.text
    assert '<html lang="en" data-theme="dark">' in page.text
    assert 'id="theme-switcher"' in page.text
    assert "function toggleTheme()" in page.text
    assert "platform-workflow-ui-theme" in page.text
    assert "body { margin:0; min-height:100vh; overflow:auto;" in page.text
    assert "grid-template-rows:auto auto auto auto minmax(0, 1fr)" not in page.text
    assert "main { width:calc(100vw - 40px); min-height:100vh;" in page.text
    assert ".result { display:flex; flex-direction:column; min-height:260px;" in page.text
    assert ".preview-error-output" in page.text
    assert "Presets" not in page.text
    assert 'name="preset_resource_profile"' in page.text
    assert "Local IDP 12 GB" in page.text
    assert "Advanced overrides" in page.text
    assert 'name="custom_worker_count"' in page.text
    assert 'hx-get="/inventory"' in page.text
    assert 'id="inventory"' in page.text
    assert "Checking prereqs..." in page.text
    assert "Setup presets" in page.text
    assert "Curated setup profiles" in page.text
    assert "Minimal local" in page.text
    assert "IDP demo" in page.text
    assert "Airplane" in page.text
    assert "Individual preset controls" in page.text
    assert "Expand all" not in page.text
    assert "Collapse all" not in page.text
    assert "applySetupProfile('idp-demo')" in page.text
    assert "+${labels.length - 2} more" in page.text
    assert "Apps and platform surfaces" in page.text
    assert "Kubernetes IN Docker" in page.text
    assert "Reference path" not in page.text
    assert "Docker-backed teaching variant" not in page.text
    assert "Fastest local Kubernetes path" not in page.text
    assert "Local Docker-backed variant" not in page.text
    assert "VM-backed Kubernetes on macOS" not in page.text
    assert "MicroVM-backed Kubernetes" not in page.text
    assert "Pick the machine" not in page.text
    assert ".control-field.selected { outline:" not in page.text
    assert "switchTab(" in page.text
    assert "syncGuidedTabState" in page.text
    assert ".tab-btn" in page.text
    assert ".guided-btn" in page.text

    htmx = client.get("/static/htmx.min.js")
    assert htmx.status_code == 200
    assert len(htmx.text) > 1000


def test_preview_failure_layout_keeps_error_details_reachable(tmp_path: Path) -> None:
    write_preview_failure_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    page = client.get("/")
    preview = client.post(
        "/preview",
        data={"variant": "kubernetes/kind", "stage": "200", "action": "apply", "auto_approve": "1"},
    )

    assert page.status_code == 200
    assert "body { margin:0; min-height:100vh; overflow:auto;" in page.text
    assert "grid-template-rows:auto auto auto auto minmax(0, 1fr)" not in page.text
    assert ".result { display:flex; flex-direction:column; min-height:260px;" in page.text
    assert ".preview-error-output" in page.text
    assert preview.status_code == 200
    assert 'class="preview-error"' in preview.text
    assert 'class="output preview-error-output"' in preview.text
    assert "Preview failed" in preview.text
    assert "missing prereq line 120" in preview.text


def test_preview_fragment_uses_shared_workflow_script(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    response = client.post(
        "/preview",
        data={"variant": "kubernetes/kind", "stage": "500", "action": "apply", "auto_approve": "1"},
    )

    assert response.status_code == 200
    assert "make -C kubernetes/kind 500 apply" in response.text
    assert 'hx-post="/run"' in response.text
    assert 'class="command"' in response.text
    assert "Dry-run" in response.text
    assert "Execute Apply" in response.text
    assert "Intent" in response.text
    assert "Consequence" in response.text
    assert "Variant contract" in response.text
    assert "local-created-cluster" in response.text
    assert "platform-stack" in response.text
    assert "Cluster access" in response.text
    assert "stage baseline -&gt; variant defaults -&gt; context defaults -&gt; preset overlays -&gt; custom overrides" in response.text
    assert '<span class="selection-badge">Selection: Dropdowns</span>' in response.text
    assert "Mutating" in response.text
    assert "Stage 900 is cumulative" not in response.text
    assert "Apply the selected kind stage 500 workflow." in response.text
    assert "May create, update, or delete local runtime resources." in response.text
    assert "Makefile abstraction" in response.text
    assert "Script inputs" in response.text
    assert "showCommandTab('makefile')" in response.text
    assert "showCommandTab('script')" in response.text
    assert "scripts/platform-workflow.sh apply --execute --variant kind --stage 500 --action apply --auto-approve" in response.text
    assert "CI step" not in response.text
    assert "set -euo pipefail" not in response.text
    assert "Dry-run uses" in response.text
    assert "No state lock" in response.text
    assert "Checked at execution" in response.text
    assert 'id="history"' in response.text
    assert 'hx-swap-oob="outerHTML"' in response.text
    assert "<h2>Recent commands</h2>" not in response.text
    assert '<section class="quick-actions"' not in response.text
    assert "Quick actions run immediately, except Reset." not in response.text
    assert ">100</button>" not in response.text
    assert ">950</button>" not in response.text
    assert "button[data-tooltip]::after" in client.get("/").text
    assert 'hx-post="/next"' not in response.text


def test_state_reset_preview_is_non_interactive(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    response = client.post(
        "/preview",
        data={"variant": "kubernetes/kind", "stage": "900", "action": "state-reset"},
    )

    assert response.status_code == 200
    assert "make -C kubernetes/kind state-reset AUTO_APPROVE=1" in response.text
    assert "Destructive" in response.text


def test_read_only_preview_has_read_only_badge_and_no_auto_approve(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    response = client.post(
        "/preview",
        data={"variant": "kubernetes/kind", "stage": "900", "action": "check-health", "auto_approve": "1", "source": "action button"},
    )

    assert response.status_code == 200
    assert "Read-only" in response.text
    assert '<span class="selection-badge">Selection: Action shortcut</span>' in response.text
    assert "make -C kubernetes/kind 900 check-health" in response.text
    assert "AUTO_APPROVE=1" not in response.text
    assert "Stage 900 is cumulative" in response.text


def test_inventory_fragment_uses_read_model_command(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    response = client.get("/inventory?variant=kubernetes/kind&stage=900")

    assert response.status_code == 200
    assert "Prereqs" in response.text
    assert '<details class="inventory prereqs workflow-panel">' in response.text
    assert '<summary class="inventory-head">' in response.text
    assert "Observed inventory" not in response.text
    assert "CLI tools" in response.text
    assert "Host runtimes" in response.text
    assert "Registry auth" in response.text
    assert "Variant readiness" in response.text
    assert "OpenTofu / Terraform" in response.text
    assert "python3" in response.text
    assert "bun" in response.text
    assert "Overall <strong>ready</strong>" in response.text
    assert "Active variant <strong>kind</strong>" in response.text
    assert "Lima stopped" in response.text


def test_run_fragment_polls_job_and_offers_next_actions(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    response = client.post(
        "/run",
        data={"variant": "kubernetes/kind", "stage": "500", "action": "apply", "auto_approve": "1"},
    )

    assert response.status_code == 200
    assert "Workflow" in response.text
    job_id = response.text.split('id="job-', 1)[1].split('"', 1)[0]

    for _ in range(20):
        status = client.get(f"/jobs/{job_id}")
        assert status.status_code == 200
        if "Workflow succeeded" in status.text:
            break
        time.sleep(0.05)
    else:
        raise AssertionError(status.text)

    assert "OK   stage complete" in status.text
    assert "Recent commands" in status.text
    assert "Succeeded" in status.text
    assert "Copy command" in status.text
    assert "Follow latest" in status.text
    assert "Pause follow" in status.text
    assert "Copy output" in status.text
    assert "Preview again" in status.text


def test_preview_preserves_latest_completed_output(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    response = client.post(
        "/run",
        data={"variant": "kubernetes/kind", "stage": "600", "action": "plan"},
    )
    assert response.status_code == 200
    job_id = response.text.split('id="job-', 1)[1].split('"', 1)[0]

    for _ in range(20):
        status = client.get(f"/jobs/{job_id}")
        assert status.status_code == 200
        if "Workflow succeeded" in status.text:
            break
        time.sleep(0.05)
    else:
        raise AssertionError(status.text)

    preview = client.post(
        "/preview",
        data={"variant": "kubernetes/kind", "stage": "900", "action": "plan"},
    )

    assert preview.status_code == 200
    assert "make -C kubernetes/kind 900 plan" in preview.text
    assert "Latest output" in preview.text
    assert "Pinned output" in preview.text
    assert "Clear" in preview.text
    assert "Copy latest" in preview.text
    assert "exit 0" in preview.text
    assert "OK   stage complete" in preview.text


def test_command_history_keeps_last_five_run_commands(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    app = create_app(repo_root=tmp_path)
    client = TestClient(app)

    for stage in ("100", "200", "300", "400", "500", "600"):
        response = client.post(
            "/run",
            data={"variant": "kubernetes/kind", "stage": stage, "action": "plan"},
        )
        assert response.status_code == 200

    for _ in range(20):
        history = app.state.command_history.snapshot()
        if len(history) == 5 and all(entry["exit_status"] == "0" for entry in history):
            break
        time.sleep(0.05)
    else:
        raise AssertionError(history)

    history = app.state.command_history.snapshot()

    assert len(history) == 5
    assert history[0]["command"] == "make -C kubernetes/kind 600 plan"
    assert history[0]["exit_status"] == "0"
    assert history[-1]["command"] == "make -C kubernetes/kind 200 plan"
    assert "make -C kubernetes/kind 100 plan" not in response.text
    assert "Preview again" in response.text


def test_job_output_renders_ansi_as_html_and_tails_output(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))
    job = client.app.state.jobs.start({"variant": "kubernetes/kind", "stage": "500", "action": "apply", "auto_approve": True})
    job.output = [
        "\x1b[0;90m09:05:13.695\x1b[0m \x1b[0;37mSTDOUT\x1b[0m \x1b[0;36mtofu: \x1b[0m\x1b[1m\x1b[32mNo changes.\x1b[0m",
        'kubeconfig_path = "~/.kube/kind-kind-local.yaml"',
    ]
    job.returncode = None

    response = client.get(f"/jobs/{job.id}")

    assert response.status_code == 200
    assert "\x1b[" not in response.text
    assert "09:05:13.695" in response.text
    assert "No changes." in response.text
    assert "ansi-bright-black" in response.text
    assert "ansi-green" in response.text
    assert f"output-{job.id}" in response.text
    assert "Follow latest" in response.text
    assert "Pause follow" in response.text
    assert "Copy output" in response.text
    assert "Command" in response.text
    assert "Exit" in response.text
    assert "Started" in response.text
    assert "Duration" in response.text
    assert "window.platformWorkflowTail" in response.text
    assert "state.follow = nearBottom()" in response.text
    assert "updateOutputFollowControls" in response.text
    assert "output.addEventListener('scroll'" in response.text
    assert "scrollTop = output.scrollHeight" in response.text


def test_stage_helpers_match_tui_scope() -> None:
    for stage in ("100", "200", "300", "400", "500", "600"):
        assert not stage_has_app_toggles(stage)
    for stage in ("700", "800", "900"):
        assert stage_has_app_toggles(stage)
    assert not stage_has_app_toggles("950-local-idp")

    assert next_stages("kubernetes/kind", "500", "apply", True) == ["600", "900"]
    assert next_stages("kubernetes/kind", "600", "apply", True) == ["700", "800", "900"]
    assert next_stages("kubernetes/lima", "600", "apply", True) == ["700", "800", "900"]
    assert next_stages("kubernetes/lima", "500", "apply", True) == ["600", "900"]
    assert next_stages("kubernetes/kind", "500", "plan", True) == []
    assert next_stages("kubernetes/kind", "500", "apply", False) == []
