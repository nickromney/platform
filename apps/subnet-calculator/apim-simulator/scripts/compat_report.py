#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from app.compat_report import build_compat_report


def _load_payload(path: str) -> dict:
    if path == "-":
        return json.load(sys.stdin)
    return json.loads(Path(path).read_text(encoding="utf-8"))


def main() -> int:
    tofu_show = os.environ.get("TOFU_SHOW", "").strip()
    if not tofu_show:
        print("TOFU_SHOW must point to a terraform/tofu show -json file.", file=sys.stderr)
        return 2

    report = build_compat_report(_load_payload(tofu_show))
    print(json.dumps(report["config_summary"], indent=2))

    if report["adapted"]:
        print("Adapted items:")
        for item in report["adapted"]:
            print(f"- {item['scope']} / {item['feature']}: {item['detail']}")

    if report["unsupported"]:
        print("Unsupported items:")
        for item in report["unsupported"]:
            print(f"- {item['scope']} / {item['feature']}: {item['detail']}")

    if report["unsupported"] and os.environ.get("ALLOW_UNSUPPORTED", "").lower() != "true":
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
