from __future__ import annotations

from scripts.check_sample_compat import run_checks


def test_sample_compat_harness_is_green_for_supported_and_adapted_fixtures() -> None:
    result = run_checks()

    assert result["failures"] == []
    assert result["supported"]
    assert result["adapted"]
    assert result["unsupported"]
