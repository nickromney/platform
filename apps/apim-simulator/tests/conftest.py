from __future__ import annotations

from fnmatch import fnmatch
from pathlib import Path
from typing import Any

import pytest
import yaml

CONTRACT_MATRIX_PATH = Path(__file__).resolve().parent.parent / "contracts" / "contract_matrix.yml"
ENFORCED_STATUSES = {"supported", "adapted", "partial"}


def _load_contract_matrix() -> dict[str, dict[str, Any]]:
    if not CONTRACT_MATRIX_PATH.exists():
        raise pytest.UsageError(f"Contract matrix not found: {CONTRACT_MATRIX_PATH}")

    payload = yaml.safe_load(CONTRACT_MATRIX_PATH.read_text(encoding="utf-8")) or {}
    contracts = payload.get("contracts")
    if not isinstance(contracts, list):
        raise pytest.UsageError("contracts/contract_matrix.yml must define a top-level 'contracts' list")

    out: dict[str, dict[str, Any]] = {}
    errors: list[str] = []

    for index, entry in enumerate(contracts, start=1):
        if not isinstance(entry, dict):
            errors.append(f"contracts[{index}] must be a mapping")
            continue

        contract_id = entry.get("id")
        if not isinstance(contract_id, str) or not contract_id.strip():
            errors.append(f"contracts[{index}] is missing a non-empty string 'id'")
            continue
        contract_id = contract_id.strip()

        if contract_id in out:
            errors.append(f"duplicate contract id: {contract_id}")
            continue

        owner_tests = entry.get("owner_tests") or []
        if not isinstance(owner_tests, list) or not all(isinstance(item, str) and item.strip() for item in owner_tests):
            errors.append(f"{contract_id}: owner_tests must be a list of non-empty strings")
            continue

        doc_refs = entry.get("doc_refs") or []
        if not isinstance(doc_refs, list) or not all(isinstance(item, str) and item.strip() for item in doc_refs):
            errors.append(f"{contract_id}: doc_refs must be a list of non-empty strings")
            continue

        out[contract_id] = {
            "status": str(entry.get("status") or "").strip().lower(),
            "owner_tests": [item.strip() for item in owner_tests],
            "doc_refs": [item.strip() for item in doc_refs],
        }

    if errors:
        raise pytest.UsageError("Contract matrix validation failed:\n- " + "\n- ".join(errors))

    return out


def _iter_contract_ids(item: pytest.Item) -> set[str]:
    contract_ids: set[str] = set()
    for mark in item.iter_markers("contract"):
        if not mark.args:
            raise pytest.UsageError(f"{item.nodeid}: contract marker must include at least one contract id")
        for arg in mark.args:
            if not isinstance(arg, str) or not arg.strip():
                raise pytest.UsageError(f"{item.nodeid}: contract marker args must be non-empty strings")
            contract_ids.add(arg.strip())
    return contract_ids


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line(
        "markers",
        "contract(*ids): associates a test with one or more contract ids from contracts/contract_matrix.yml",
    )
    config._contract_matrix = _load_contract_matrix()


def pytest_collection_finish(session: pytest.Session) -> None:
    contracts: dict[str, dict[str, Any]] = getattr(session.config, "_contract_matrix", {})
    marked_items: dict[str, set[str]] = {contract_id: set() for contract_id in contracts}
    contract_ids_by_nodeid: dict[str, set[str]] = {}
    errors: list[str] = []

    for item in session.items:
        item_contract_ids = _iter_contract_ids(item)
        if not item_contract_ids:
            continue
        contract_ids_by_nodeid[item.nodeid] = item_contract_ids
        for contract_id in item_contract_ids:
            if contract_id not in contracts:
                errors.append(f"{item.nodeid}: unknown contract id {contract_id!r}")
                continue
            marked_items[contract_id].add(item.nodeid)

    for contract_id, metadata in contracts.items():
        if metadata["status"] not in ENFORCED_STATUSES:
            continue

        if not marked_items[contract_id]:
            errors.append(f"{contract_id}: no collected tests are marked with this contract id")

        owner_patterns = metadata["owner_tests"]
        if not owner_patterns:
            errors.append(f"{contract_id}: enforced contracts must declare at least one owner_tests entry")
            continue

        for pattern in owner_patterns:
            matched_nodeids = [item.nodeid for item in session.items if fnmatch(item.nodeid, pattern)]
            if not matched_nodeids:
                errors.append(f"{contract_id}: owner test pattern {pattern!r} matched no collected tests")
                continue
            if not any(contract_id in contract_ids_by_nodeid.get(nodeid, set()) for nodeid in matched_nodeids):
                errors.append(
                    f"{contract_id}: owner test pattern {pattern!r} matched tests, "
                    f"but none were marked with {contract_id}"
                )

    if errors:
        raise pytest.UsageError("Contract coverage validation failed:\n- " + "\n- ".join(errors))
