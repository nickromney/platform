from __future__ import annotations

from typing import Final

ENVIRONMENT_REQUEST_CAPABILITY_SCHEMA_VERSION: Final = "platform.environment_request_capabilities/v1"
ENVIRONMENT_WORKFLOW: Final = "environment"
ENVIRONMENT_CREATE_ACTION: Final = "create"
ENVIRONMENT_DELETE_ACTION: Final = "delete"
SUPPORTED_ENVIRONMENT_ACTIONS: Final[tuple[str, ...]] = (ENVIRONMENT_CREATE_ACTION, ENVIRONMENT_DELETE_ACTION)
ENVIRONMENT_ACTION_PATTERN: Final = f"^({'|'.join(SUPPORTED_ENVIRONMENT_ACTIONS)})$"
DEFAULT_ENVIRONMENT_ACTION: Final = ENVIRONMENT_CREATE_ACTION
DEFAULT_ENVIRONMENT_TYPE: Final = "development"
ENVIRONMENT_DRY_RUN: Final = True
ENVIRONMENT_REQUIRED_FIELDS: Final[tuple[str, ...]] = ("runtime", "app", "environment")
ENVIRONMENT_OPTIONAL_FIELDS: Final[tuple[str, ...]] = ("action", "environment_type")
ENVIRONMENT_ACTION_LABELS: Final[dict[str, str]] = {
    ENVIRONMENT_CREATE_ACTION: "Create environment",
    ENVIRONMENT_DELETE_ACTION: "Delete environment",
}


def environment_request_capabilities() -> dict[str, object]:
    return {
        "schema_version": ENVIRONMENT_REQUEST_CAPABILITY_SCHEMA_VERSION,
        "workflow": ENVIRONMENT_WORKFLOW,
        "dry_run": ENVIRONMENT_DRY_RUN,
        "supported_actions": list(SUPPORTED_ENVIRONMENT_ACTIONS),
        "default_action": DEFAULT_ENVIRONMENT_ACTION,
        "default_environment_type": DEFAULT_ENVIRONMENT_TYPE,
        "required_fields": list(ENVIRONMENT_REQUIRED_FIELDS),
        "optional_fields": list(ENVIRONMENT_OPTIONAL_FIELDS),
    }


def environment_event(action: str) -> str:
    if action not in SUPPORTED_ENVIRONMENT_ACTIONS:
        supported = ", ".join(SUPPORTED_ENVIRONMENT_ACTIONS)
        raise ValueError(f"unsupported environment action {action!r}; expected one of: {supported}")
    return f"{ENVIRONMENT_WORKFLOW}.{action}"


def environment_portal_action(runtime: str) -> dict[str, object]:
    return {
        "id": environment_event(DEFAULT_ENVIRONMENT_ACTION),
        "label": ENVIRONMENT_ACTION_LABELS[DEFAULT_ENVIRONMENT_ACTION],
        "runtime": runtime,
        "dry_run": ENVIRONMENT_DRY_RUN,
    }
