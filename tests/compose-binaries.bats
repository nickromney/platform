#!/usr/bin/env bats

setup() {
  source "$(git -C "$(dirname "${BATS_TEST_FILENAME}")" rev-parse --show-toplevel)/tests/test_helper.bash"
  setup_repo_root
}

@test "docker compose up and build targets build the compose binaries before compose up" {
  for target in build up up-dev up-uat up-all; do
    run make -C "${REPO_ROOT}/docker/compose" -n "${target}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"GOARCH=amd64"*"-C ../../apps/apim-simulator/app build-linux"* ]]
    [[ "${output}" == *"GOARCH=amd64"*"-C ../../apps/subnetcalc/app build-linux"* ]]

    binaries_line="$(printf '%s\n' "${output}" | grep -n 'build-linux' | head -1 | cut -d: -f1)"
    compose_line="$(printf '%s\n' "${output}" | grep -n 'docker compose' | tail -1 | cut -d: -f1)"
    [ -n "${binaries_line}" ]
    [ -n "${compose_line}" ]
    [ "${binaries_line}" -lt "${compose_line}" ]
  done
}

@test "docker compose portal target does not build the app binaries it never starts" {
  run make -C "${REPO_ROOT}/docker/compose" -n up-portal
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"build-linux"* ]]
}

@test "docker compose binary GOARCH matches the platform pinned on the app images" {
  run uv run --locked --project "${REPO_ROOT}" python - <<'PY'
from __future__ import annotations

import os
from pathlib import Path

import yaml

repo_root = Path(os.environ["REPO_ROOT"])
compose = yaml.safe_load((repo_root / "docker/compose/compose.yml").read_text(encoding="utf-8"))
platforms = {svc["platform"] for svc in compose["services"].values() if "platform" in svc}
assert platforms == {"linux/amd64"}, f"compose platforms drifted from GOARCH=amd64: {sorted(platforms)}"

for service in ("apim-simulator", "subnetcalc-api-dev", "subnetcalc-frontend-dev"):
    assert compose["services"][service]["platform"] == "linux/amd64"

print("validated compose binary GOARCH matches image platform")
PY

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"validated compose binary GOARCH matches image platform"* ]]
}
