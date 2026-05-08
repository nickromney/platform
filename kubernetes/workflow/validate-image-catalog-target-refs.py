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
    parser.add_argument("--tfvars", type=Path)
    parser.add_argument(
        "--print-expected",
        action="store_true",
        help="Print the catalog-rendered external image ref tfvars maps for the target.",
    )
    parser.add_argument(
        "--allow-source-tags",
        action="store_true",
        help="Allow catalog images with fingerprint sources to use generated src-<digest> tags.",
    )
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


def catalog_refs(catalog: dict[str, object], target: str, category: str) -> tuple[dict[str, str], set[str]]:
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
    source_tag_keys: set[str] = set()
    for image in images:
        if not isinstance(image, dict):
            raise ValueError(f"{category}_images contains a non-object entry")
        if image.get("external_ref") is False:
            continue
        hcl_key = required_string(image, "hcl_key", category)
        image_name = required_string(image, "image_name", category)
        tag = required_string(image, "default_tag", category)
        refs[hcl_key] = f"{registry_hosts[target]}/{namespace}/{image_name}:{tag}"
        if image.get("fingerprint_sources"):
            source_tag_keys.add(hcl_key)

    return refs, source_tag_keys


def render_hcl_key(key: str) -> str:
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", key):
        return key
    escaped = key.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def render_hcl_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def render_hcl_map(name: str, values: dict[str, str]) -> str:
    lines = [f"{name} = {{"]
    if values:
        width = max(len(render_hcl_key(key)) for key in values)
    else:
        width = 0
    for key in sorted(values):
        rendered_key = render_hcl_key(key)
        lines.append(f"  {rendered_key:<{width}} = {render_hcl_string(values[key])}")
    lines.append("}")
    return "\n".join(lines)


def required_string(image: dict[str, object], key: str, category: str) -> str:
    value = image.get(key)
    image_id = image.get("id", "<unknown>")
    if not isinstance(value, str) or not value:
        raise ValueError(f"{category}_images.{image_id}.{key} must be a non-empty string")
    return value


def refs_match(expected: str, actual: str, allow_source_tag: bool) -> bool:
    if actual == expected:
        return True
    if not allow_source_tag:
        return False
    if ":" not in expected or ":" not in actual:
        return False
    expected_repo, _expected_tag = expected.rsplit(":", 1)
    actual_repo, actual_tag = actual.rsplit(":", 1)
    return expected_repo == actual_repo and re.fullmatch(r"src-[0-9a-f]{20}", actual_tag) is not None


def diff_lines(
    expected: dict[str, str],
    actual: dict[str, str],
    label: str,
    source_tag_keys: set[str],
    allow_source_tags: bool,
) -> list[str]:
    lines: list[str] = []
    for key in sorted(expected.keys() - actual.keys()):
        lines.append(f"{label}: missing {key} = {expected[key]}")
    for key in sorted(actual.keys() - expected.keys()):
        lines.append(f"{label}: unexpected {key} = {actual[key]}")
    for key in sorted(expected.keys() & actual.keys()):
        allow_source_tag = allow_source_tags and key in source_tag_keys
        if not refs_match(expected[key], actual[key], allow_source_tag):
            lines.append(f"{label}: {key} expected {expected[key]}, got {actual[key]}")
    return lines


def main() -> int:
    args = parse_args()
    catalog = json.loads(args.catalog.read_text(encoding="utf-8"))

    checks = [
        ("platform", "external_platform_image_refs"),
        ("workload", "external_workload_image_refs"),
    ]

    if args.print_expected:
        rendered_maps = []
        for category, tfvars_key in checks:
            expected, _source_tag_keys = catalog_refs(catalog, args.target, category)
            rendered_maps.append(render_hcl_map(tfvars_key, expected))
        print("\n\n".join(rendered_maps))
        return 0

    if args.tfvars is None:
        print("--tfvars is required unless --print-expected is used", file=sys.stderr)
        return 2

    failures: list[str] = []
    for category, tfvars_key in checks:
        expected, source_tag_keys = catalog_refs(catalog, args.target, category)
        actual = hcl_string_map(args.tfvars, tfvars_key)
        failures.extend(diff_lines(expected, actual, tfvars_key, source_tag_keys, args.allow_source_tags))

    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1

    print(f"validated {args.target} external image refs against image catalog")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
