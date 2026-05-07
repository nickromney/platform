#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


MAP_LINE_RE = re.compile(r'^\s*(?:"([^"]+)"|([A-Za-z0-9_-]+))\s*=\s*"([^"]*)"\s*$')


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate target external image refs against the workflow image catalog."
    )
    parser.add_argument("--catalog", required=True, type=Path)
    parser.add_argument("--target", required=True)
    parser.add_argument("--tfvars", required=True, type=Path)
    return parser.parse_args()


def hcl_string_map(tfvars: Path, name: str) -> dict[str, str]:
    content = tfvars.read_text(encoding="utf-8").splitlines()
    values: dict[str, str] = {}
    in_map = False

    for line in content:
        stripped = line.strip()
        if not in_map:
            if stripped == f"{name} = {{":
                in_map = True
            continue
        if stripped == "}":
            return values
        if not stripped or stripped.startswith("#"):
            continue
        match = MAP_LINE_RE.match(line)
        if match is None:
            raise ValueError(f"{tfvars}: unsupported {name} line: {line}")
        quoted_key, bare_key, value = match.groups()
        values[quoted_key or bare_key] = value

    raise ValueError(f"{tfvars}: missing {name} map")


def catalog_refs(catalog: dict[str, object], target: str, category: str) -> dict[str, str]:
    registry_hosts = catalog.get("variant_registry_hosts")
    if not isinstance(registry_hosts, dict) or target not in registry_hosts:
        raise ValueError(f"image catalog does not declare registry host for target {target!r}")

    namespace = catalog.get("namespace")
    if not isinstance(namespace, str) or not namespace:
        raise ValueError("image catalog namespace must be a non-empty string")

    images = catalog.get(f"{category}_images")
    if not isinstance(images, list):
        raise ValueError(f"image catalog missing {category}_images")

    refs: dict[str, str] = {}
    for image in images:
        if not isinstance(image, dict):
            raise ValueError(f"{category}_images contains a non-object entry")
        if image.get("external_ref") is False:
            continue
        hcl_key = required_string(image, "hcl_key", category)
        image_name = required_string(image, "image_name", category)
        tag = image.get("default_tag") or "latest"
        if not isinstance(tag, str):
            raise ValueError(f"{category}_images.{hcl_key}.default_tag must be a string when set")
        refs[hcl_key] = f"{registry_hosts[target]}/{namespace}/{image_name}:{tag}"

    return refs


def required_string(image: dict[str, object], key: str, category: str) -> str:
    value = image.get(key)
    image_id = image.get("id", "<unknown>")
    if not isinstance(value, str) or not value:
        raise ValueError(f"{category}_images.{image_id}.{key} must be a non-empty string")
    return value


def diff_lines(expected: dict[str, str], actual: dict[str, str], label: str) -> list[str]:
    lines: list[str] = []
    for key in sorted(expected.keys() - actual.keys()):
        lines.append(f"{label}: missing {key} = {expected[key]}")
    for key in sorted(actual.keys() - expected.keys()):
        lines.append(f"{label}: unexpected {key} = {actual[key]}")
    for key in sorted(expected.keys() & actual.keys()):
        if actual[key] != expected[key]:
            lines.append(f"{label}: {key} expected {expected[key]}, got {actual[key]}")
    return lines


def main() -> int:
    args = parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))

    failures: list[str] = []
    checks = [
        ("platform", "external_platform_image_refs"),
        ("workload", "external_workload_image_refs"),
    ]
    for category, tfvars_key in checks:
        expected = catalog_refs(catalog, args.target, category)
        actual = hcl_string_map(args.tfvars, tfvars_key)
        failures.extend(diff_lines(expected, actual, tfvars_key))

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1

    print(f"validated {args.target} external image refs against image catalog")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
