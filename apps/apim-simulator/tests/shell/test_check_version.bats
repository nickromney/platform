#!/usr/bin/env bats

setup() {
  export REPO_ROOT
  REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/../.." && pwd)"
  export SCRIPT="${REPO_ROOT}/scripts/check-version.sh"
  export MOCK_ROOT="$BATS_TEST_TMPDIR/mock"
  export GITHUB_FIXTURES="$MOCK_ROOT/github"
  export DOCKER_FIXTURES="$MOCK_ROOT/docker"
  mkdir -p "$GITHUB_FIXTURES" "$DOCKER_FIXTURES"

  uv run --project "$REPO_ROOT" python - "$REPO_ROOT" "$GITHUB_FIXTURES" "$DOCKER_FIXTURES" <<'PY'
import json
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
github_root = Path(sys.argv[2])
docker_root = Path(sys.argv[3])

action_pattern = re.compile(
    r'uses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-f]{40})(?:\s*#\s*(v[^\s]+))?'
)
for workflow_path in sorted((repo_root / ".github/workflows").glob("*.yml")):
    workflow = workflow_path.read_text(encoding="utf-8")
    for repo, sha, selector in action_pattern.findall(workflow):
        if not selector:
            continue
        fixture = github_root / "repos" / repo / "commits" / selector
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text(json.dumps({"sha": sha}), encoding="utf-8")

docker_pattern = re.compile(r'image:\s*([A-Za-z0-9._/-]+):([^@\s]+)@(sha256:[0-9a-f]{64})')
for compose_name in ("compose.otel.yml", "compose.todo.otel.yml"):
    compose_text = (repo_root / compose_name).read_text(encoding="utf-8")
    for image, tag, digest in docker_pattern.findall(compose_text):
        if "/" in image:
            namespace, repo = image.split("/", 1)
        else:
            namespace, repo = "library", image
        fixture = docker_root / "namespaces" / namespace / "repositories" / repo / "tags" / tag
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text(json.dumps({"digest": digest}), encoding="utf-8")

uv_pattern = re.compile(r'COPY --from=ghcr\.io/astral-sh/uv:([^\s]+) /uv /usr/local/bin/uv')
for dockerfile in (
    "Dockerfile",
    "examples/hello-api/Dockerfile",
    "examples/todo-app/api-fastapi-container-app/Dockerfile",
    "examples/mcp-server/Dockerfile",
):
    text = (repo_root / dockerfile).read_text(encoding="utf-8")
    for version in uv_pattern.findall(text):
        fixture = github_root / "repos" / "astral-sh" / "uv" / "commits" / version
        fixture.parent.mkdir(parents=True, exist_ok=True)
        fixture.write_text(json.dumps({"sha": "079e3fd059c3d073151a6ac3b39eb129d66b517d"}), encoding="utf-8")
PY

  export EXPECTED_VERSION
  EXPECTED_VERSION="$(
    uv run --project "$REPO_ROOT" python - <<'PY'
import tomllib
from pathlib import Path

print(tomllib.loads(Path("pyproject.toml").read_text(encoding="utf-8"))["project"]["version"])
PY
  )"
}

@test "check-version passes with matching upstream fixtures" {
  run env \
    CHECK_VERSION_GITHUB_API_BASE="file://$GITHUB_FIXTURES" \
    CHECK_VERSION_DOCKER_HUB_BASE="file://$DOCKER_FIXTURES" \
    "$SCRIPT" --execute

  [ "$status" -eq 0 ]
  [[ "$output" == *"Release version declarations are synchronized at $EXPECTED_VERSION"* ]]
  [[ "$output" == *"actions/checkout v6.0.2 resolves to the pinned SHA"* ]]
  [[ "$output" == *"grafana/otel-lgtm:0.24.0 matches the pinned digest"* ]]
  [[ "$output" == *"All uv-backed Dockerfiles use ghcr.io/astral-sh/uv:0.10.4"* ]]
  [[ "$output" == *"All .npmrc files set min-release-age=7"* ]]
  [[ "$output" == *"All uv-managed pyproject.toml files set exclude-newer='7 days'"* ]]
  [[ "$output" == *"All version checks passed."* ]]
}

@test "check-version fails when an action selector resolves to a different sha" {
  printf '{"sha":"%040d"}\n' 1 >"$GITHUB_FIXTURES/repos/actions/checkout/commits/v6.0.2"

  run env \
    CHECK_VERSION_GITHUB_API_BASE="file://$GITHUB_FIXTURES" \
    CHECK_VERSION_DOCKER_HUB_BASE="file://$DOCKER_FIXTURES" \
    "$SCRIPT" --execute

  [ "$status" -eq 1 ]
  [[ "$output" == *"actions/checkout v6.0.2 resolves to"* ]]
  [[ "$output" == *"version check(s) failed."* ]]
}
