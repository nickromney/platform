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
    printf '{"targets":["kind","lima","slicer"],"stages":[{"id":"950-local-idp","label":"local-idp"}],"actions":["plan","apply"]}\\n'
    ;;
  preview)
    target="kind"; stage="900"; action="apply"; auto_approve=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --target) target="$2"; shift 2 ;;
        --stage) stage="$2"; shift 2 ;;
        --action) action="$2"; shift 2 ;;
        --auto-approve) auto_approve=" AUTO_APPROVE=1"; shift ;;
        *) shift ;;
      esac
    done
    if [[ "$action" == "reset" || "$action" == "state-reset" || "$action" == "status" || "$action" == "show-urls" ]]; then
      printf '{"target":"%s","stage":"%s","action":"%s","command":"make -C kubernetes/%s %s%s"}\\n' "$target" "$stage" "$action" "$target" "$action" "$auto_approve"
    else
      printf '{"target":"%s","stage":"%s","action":"%s","command":"make -C kubernetes/%s %s %s%s"}\\n' "$target" "$stage" "$action" "$target" "$stage" "$action" "$auto_approve"
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


def test_app_serves_htmx_page_and_static_asset(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))

    page = client.get("/")

    assert page.status_code == 200
    assert 'hx-post="/preview"' in page.text
    assert 'hx-post="/run"' in page.text
    assert "State reset" in page.text
    assert 'value="state-reset"' in page.text
    assert "Reset actions require review before they run." in page.text
    assert "/static/htmx.min.js" in page.text
    assert "FastAPI + HTMX, no Node build" not in page.text
    assert "Variant shortcuts" in page.text
    assert 'data-variant="kubernetes/kind"' in page.text
    assert 'data-variant="kubernetes/lima"' in page.text
    assert 'data-variant="kubernetes/slicer"' in page.text
    assert 'name="variant"' in page.text
    assert 'name="target"' not in page.text
    assert "updateQuickActionVariants(variant)" in page.text
    assert "htmx.trigger(form, 'submit')" not in page.text
    assert "form.requestSubmit()" not in page.text
    assert "Preview</button>" not in page.text
    assert '<section id="history" class="history" aria-label="Recent commands" hidden>' in page.text
    assert "Stage default: enabled" in page.text
    assert "Enable sentiment (stage default)" not in page.text
    assert "width:calc(100vw - 40px)" in page.text
    assert "width:min(1480px" not in page.text
    assert "height:100vh" in page.text
    assert "overflow:hidden" in page.text
    assert "grid-template-rows:auto auto auto minmax(0, 1fr)" in page.text
    assert "height:100%" in page.text
    assert "min-height:0" in page.text
    assert "max-height:none" in page.text

    htmx = client.get("/static/htmx.min.js")
    assert htmx.status_code == 200
    assert len(htmx.text) > 1000


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
    assert 'id="history"' in response.text
    assert 'hx-swap-oob="outerHTML"' in response.text
    assert "<h2>Recent commands</h2>" not in response.text
    assert "Preview" not in response.text
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


def test_job_output_renders_ansi_as_html_and_tails_output(tmp_path: Path) -> None:
    write_workflow_stub(tmp_path)
    client = TestClient(create_app(repo_root=tmp_path))
    job = client.app.state.jobs.start({"variant": "kubernetes/kind", "stage": "500", "action": "apply", "auto_approve": True})
    job.output = [
        "\x1b[0;90m09:05:13.695\x1b[0m \x1b[0;37mSTDOUT\x1b[0m \x1b[0;36mtofu: \x1b[0m\x1b[1m\x1b[32mNo changes.\x1b[0m",
        "kubeconfig_path = \"/Users/nickromney/.kube/kind-kind-local.yaml\"",
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
    assert "window.platformWorkflowTail" in response.text
    assert "state.follow = nearBottom()" in response.text
    assert "output.addEventListener('scroll'" in response.text
    assert "scrollTop = output.scrollHeight" in response.text


def test_stage_helpers_match_tui_scope() -> None:
    for stage in ("100", "200", "300", "400", "500", "600"):
        assert not stage_has_app_toggles(stage)
    for stage in ("700", "800", "900", "950-local-idp"):
        assert stage_has_app_toggles(stage)

    assert next_stages("kubernetes/kind", "500", "apply", True) == ["600", "900", "950-local-idp"]
    assert next_stages("kubernetes/kind", "600", "apply", True) == ["700", "800", "900", "950-local-idp"]
    assert next_stages("kubernetes/lima", "600", "apply", True) == ["700", "800", "900"]
    assert next_stages("kubernetes/lima", "500", "apply", True) == ["600", "900"]
    assert next_stages("kubernetes/kind", "500", "plan", True) == []
    assert next_stages("kubernetes/kind", "500", "apply", False) == []
