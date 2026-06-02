from __future__ import annotations

from platform_workflow_ui.workflow import WorkflowSelection


def test_workflow_selection_normalizes_input_and_builds_workflow_args() -> None:
    selection = WorkflowSelection.from_mapping(
        {
            "variant": "kubernetes/kind",
            "stage": "900",
            "action": "apply",
            "preset_app_set": "minimal",
            "custom_worker_count": "2",
            "sentiment": "off",
            "subnetcalc": "on",
            "auto_approve": "1",
            "dry_run": "on",
            "source": "stage ladder",
        }
    )

    assert selection.to_payload()["source"] == "stage ladder"
    assert selection.run_standard_flag() == "--dry-run"
    assert selection.workflow_args("preview") == [
        "preview",
        "--execute",
        "--output",
        "json",
        "--variant",
        "kind",
        "--stage",
        "900",
        "--action",
        "apply",
        "--preset",
        "app-set=minimal",
        "--set",
        "worker_count=2",
        "--app",
        "sentiment=off",
        "--auto-approve",
    ]
    assert selection.workflow_args("apply", standard_flag=selection.run_standard_flag())[:2] == ["apply", "--dry-run"]


def test_workflow_selection_history_payload_is_form_safe() -> None:
    selection = WorkflowSelection.from_mapping({"variant": "kubernetes/lima", "stage": "500", "action": "plan"})

    assert selection.history_payload()["variant"] == "kubernetes/lima"
    assert selection.history_payload()["auto_approve"] == ""
    assert selection.history_payload()["dry_run"] == ""
