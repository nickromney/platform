#!/usr/bin/env bash
set -euo pipefail

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[1;33m'
  NC=$'\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  NC=''
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

ok() { printf '%sOK%s   %s\n' "${GREEN}" "${NC}" "$*"; }
warn() { printf '%sWARN%s %s\n' "${YELLOW}" "${NC}" "$*"; }
fail_note() { printf '%sFAIL%s %s\n' "${RED}" "${NC}" "$*"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n%s\n' "$*"; }

usage() {
  cat <<'EOF'
Usage: check-version.sh [--dry-run] [--execute]

Checks:
  - release version declarations stay synchronized across the repo
  - SHA-pinned GitHub Actions still resolve from their trailing '# v...' selectors
  - digest-pinned Docker images still match their pinned tags
  - the pinned Astral uv builder tag stays consistent across Dockerfiles
  - npm, Bun, and uv dependency age gates stay aligned

Options:
  --dry-run   Accepted for parity with other repo scripts. This command is read-only.
  --execute   Accepted for parity with other repo scripts. This command is read-only.
  -h, --help  Show this help.

Environment:
  CHECK_VERSION_SKIP_UPSTREAM=1       Skip network-backed upstream resolution.
  CHECK_VERSION_GITHUB_API_BASE=...   Override the GitHub API base URL.
  CHECK_VERSION_DOCKER_HUB_BASE=...   Override the Docker Hub API base URL.
  CHECK_VERSION_TIMEOUT_SECONDS=...   HTTP timeout in seconds. Default: 15.
  CHECK_VERSION_NPM_MIN_RELEASE_AGE=7 Expected npm min-release-age.
  CHECK_VERSION_BUN_MIN_RELEASE_AGE=604800
                                      Expected Bun minimumReleaseAge.
  CHECK_VERSION_UV_EXCLUDE_NEWER='7 days'
                                      Expected uv exclude-newer value.
EOF
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --)
      shift
      break
      ;;
    -*)
      shell_cli_unknown_flag "$(shell_cli_script_name)" "$1"
      usage >&2
      exit 1
      ;;
    *)
      shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
      usage >&2
      exit 1
      ;;
  esac
done

if [[ $# -gt 0 ]]; then
  shell_cli_unexpected_arg "$(shell_cli_script_name)" "$1"
  usage >&2
  exit 1
fi

shell_cli_maybe_execute_or_preview_summary usage \
  "would check release versions, pinned actions, pinned Docker digests, uv builder tags, and dependency age gates"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -n "${CHECK_VERSION_WORKFLOW_FILES:-}" ]]; then
  WORKFLOW_FILES="${CHECK_VERSION_WORKFLOW_FILES}"
elif [[ -n "${CHECK_VERSION_WORKFLOW_FILE:-}" ]]; then
  WORKFLOW_FILES="${CHECK_VERSION_WORKFLOW_FILE}"
else
  WORKFLOW_FILES="${ROOT_DIR}/.github/workflows/ci.yml ${ROOT_DIR}/.github/workflows/release.yml"
fi
COMPOSE_FILES="${CHECK_VERSION_COMPOSE_FILES:-${ROOT_DIR}/compose.otel.yml ${ROOT_DIR}/compose.todo.otel.yml}"
DOCKERFILES="${CHECK_VERSION_DOCKERFILES:-${ROOT_DIR}/Dockerfile ${ROOT_DIR}/examples/hello-api/Dockerfile ${ROOT_DIR}/examples/todo-app/api-fastapi-container-app/Dockerfile ${ROOT_DIR}/examples/mcp-server/Dockerfile}"
CHECK_VERSION_SKIP_UPSTREAM="${CHECK_VERSION_SKIP_UPSTREAM:-0}"
CHECK_VERSION_GITHUB_API_BASE="${CHECK_VERSION_GITHUB_API_BASE:-https://api.github.com}"
CHECK_VERSION_DOCKER_HUB_BASE="${CHECK_VERSION_DOCKER_HUB_BASE:-https://hub.docker.com/v2}"
CHECK_VERSION_TIMEOUT_SECONDS="${CHECK_VERSION_TIMEOUT_SECONDS:-15}"
CHECK_VERSION_NPM_MIN_RELEASE_AGE="${CHECK_VERSION_NPM_MIN_RELEASE_AGE:-7}"
CHECK_VERSION_BUN_MIN_RELEASE_AGE="${CHECK_VERSION_BUN_MIN_RELEASE_AGE:-604800}"
CHECK_VERSION_UV_EXCLUDE_NEWER="${CHECK_VERSION_UV_EXCLUDE_NEWER:-7 days}"
FAILURES=0
UV_BIN="${UV_BIN:-uv}"

require() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || {
    printf '%s\n' "$bin not found in PATH" >&2
    exit 1
  }
}

require "${UV_BIN}"

github_commit_sha() {
  "${UV_BIN}" run --project "${ROOT_DIR}" python - "$CHECK_VERSION_GITHUB_API_BASE" "$1" "$2" "$CHECK_VERSION_TIMEOUT_SECONDS" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

base, repo, ref, timeout = sys.argv[1:5]
url = f"{base.rstrip('/')}/repos/{repo}/commits/{urllib.parse.quote(ref, safe='')}"
request = urllib.request.Request(
    url,
    headers={
        "Accept": "application/vnd.github+json",
        "User-Agent": "apim-simulator-check-version",
    },
)
with urllib.request.urlopen(request, timeout=int(timeout)) as response:
    payload = json.load(response)
print(payload["sha"])
PY
}

docker_tag_digest() {
  "${UV_BIN}" run --project "${ROOT_DIR}" python - "$CHECK_VERSION_DOCKER_HUB_BASE" "$1" "$2" "$CHECK_VERSION_TIMEOUT_SECONDS" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

base, image, tag, timeout = sys.argv[1:5]
if "/" in image:
    namespace, repo = image.split("/", 1)
else:
    namespace, repo = "library", image
url = (
    f"{base.rstrip('/')}/namespaces/{namespace}/repositories/"
    f"{repo}/tags/{urllib.parse.quote(tag, safe='')}"
)
with urllib.request.urlopen(url, timeout=int(timeout)) as response:
    payload = json.load(response)
print(payload["digest"])
PY
}

check_release_version_sync() {
  local output
  if ! output="$(
    "${UV_BIN}" run --project "${ROOT_DIR}" python - "$ROOT_DIR" <<'PY'
import json
import re
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])

def package_version(path: Path) -> str:
    return json.loads(path.read_text(encoding="utf-8"))["version"]

def python_constant(path: Path, pattern: str) -> str:
    match = re.search(pattern, path.read_text(encoding="utf-8"), flags=re.MULTILINE)
    if not match:
        raise SystemExit(f"missing version declaration in {path}")
    return match.group(1)

versions = {
    "pyproject.toml": tomllib.loads((root / "pyproject.toml").read_text(encoding="utf-8"))["project"]["version"],
    "app/main.py": python_constant(root / "app/main.py", r'^APIM_SERVICE_VERSION = "([^"]+)"$'),
    "examples/hello-api/main.py": python_constant(root / "examples/hello-api/main.py", r'^SERVICE_VERSION = "([^"]+)"$'),
    "examples/todo-app/api-fastapi-container-app/main.py": python_constant(
        root / "examples/todo-app/api-fastapi-container-app/main.py",
        r'^TODO_SERVICE_VERSION = "([^"]+)"$',
    ),
    "ui/package.json": package_version(root / "ui/package.json"),
    "examples/todo-app/frontend-astro/package.json": package_version(root / "examples/todo-app/frontend-astro/package.json"),
    "examples/todo-app/api-clients/proxyman/todo-through-apim.har": json.loads(
        (root / "examples/todo-app/api-clients/proxyman/todo-through-apim.har").read_text(encoding="utf-8")
    )["log"]["creator"]["version"],
}

expected = next(iter(versions.values()))
out_of_sync = {path: version for path, version in versions.items() if version != expected}

print(expected)
for path, version in versions.items():
    print(f"{path}\t{version}")

if out_of_sync:
    raise SystemExit(1)
PY
  )"; then
    fail_note "Release version declarations are not synchronized"
    printf '%s\n' "${output}"
    return
  fi

  local expected
  expected="$(printf '%s\n' "${output}" | sed -n '1p')"
  ok "Release version declarations are synchronized at ${expected}"
}

check_action_pins() {
  local pins
  pins="$(
    "${UV_BIN}" run --project "${ROOT_DIR}" python - ${WORKFLOW_FILES} <<'PY'
import re
import sys
from pathlib import Path

pattern = re.compile(
    r'uses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-f]{40})(?:\s*#\s*(v[^\s]+))?'
)
seen = set()
for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    if not path.is_file():
        raise SystemExit(f"workflow file not found: {path}")
    for repo, sha, selector in pattern.findall(path.read_text(encoding="utf-8")):
        item = (repo, sha, selector)
        if item in seen:
            continue
        seen.add(item)
        print(f"{repo}\t{sha}\t{selector}")
PY
  )"

  section "GitHub Actions"

  local repo sha selector resolved
  while IFS=$'\t' read -r repo sha selector; do
    [[ -n "${repo}" ]] || continue
    if [[ -z "${selector}" ]]; then
      fail_note "${repo} is pinned by SHA without a trailing '# v...' selector comment"
      continue
    fi

    if [[ "${CHECK_VERSION_SKIP_UPSTREAM}" == "1" ]]; then
      warn "${repo} ${selector} upstream resolution skipped"
      continue
    fi

    resolved="$(github_commit_sha "${repo}" "${selector}" 2>/dev/null || true)"
    if [[ -z "${resolved}" ]]; then
      warn "Could not resolve ${repo} ${selector}"
      continue
    fi

    if [[ "${resolved}" == "${sha}" ]]; then
      ok "${repo} ${selector} resolves to the pinned SHA"
    else
      fail_note "${repo} ${selector} resolves to ${resolved}, but the workflow pins ${sha}"
    fi
  done <<< "${pins}"
}

check_npm_age_gates() {
  section "npm Age Gates"

  local output
  if ! output="$(
    "${UV_BIN}" run --project "${ROOT_DIR}" python - "$ROOT_DIR" "$CHECK_VERSION_NPM_MIN_RELEASE_AGE" <<'PY'
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected = sys.argv[2]
failures = []
files = [
    path
    for path in sorted(root.rglob(".npmrc"))
    if ".git" not in path.parts and "node_modules" not in path.parts and "dist" not in path.parts
]
for path in files:
    values = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    if values.get("min-release-age") != expected:
        failures.append(f"{path.relative_to(root)}: min-release-age={values.get('min-release-age', '<missing>')}")

if failures:
    print("\n".join(failures))
    raise SystemExit(1)

print(len(files))
PY
  )"; then
    fail_note "npm min-release-age is not ${CHECK_VERSION_NPM_MIN_RELEASE_AGE} for every .npmrc"
    printf '%s\n' "${output}"
    return
  fi

  ok "All .npmrc files set min-release-age=${CHECK_VERSION_NPM_MIN_RELEASE_AGE} (${output} file(s))"
}

check_bun_age_gates() {
  section "Bun Age Gates"

  local output
  if ! output="$(
    "${UV_BIN}" run --project "${ROOT_DIR}" python - "$ROOT_DIR" "$CHECK_VERSION_BUN_MIN_RELEASE_AGE" <<'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected = sys.argv[2]
failures = []
files = [
    path
    for path in sorted(root.rglob("bunfig.toml"))
    if ".git" not in path.parts and "node_modules" not in path.parts and "dist" not in path.parts
]
pattern = re.compile(r"^\s*minimumReleaseAge\s*=\s*(\d+)\s*$", re.MULTILINE)
for path in files:
    match = pattern.search(path.read_text(encoding="utf-8"))
    value = match.group(1) if match else "<missing>"
    if value != expected:
        failures.append(f"{path.relative_to(root)}: minimumReleaseAge={value}")

if failures:
    print("\n".join(failures))
    raise SystemExit(1)

print(len(files))
PY
  )"; then
    fail_note "Bun minimumReleaseAge is not ${CHECK_VERSION_BUN_MIN_RELEASE_AGE} for every bunfig.toml"
    printf '%s\n' "${output}"
    return
  fi

  if [[ "${output}" == "0" ]]; then
    ok "No bunfig.toml files found"
  else
    ok "All bunfig.toml files set minimumReleaseAge=${CHECK_VERSION_BUN_MIN_RELEASE_AGE} (${output} file(s))"
  fi
}

check_uv_age_gates() {
  section "uv Age Gates"

  local output
  if ! output="$(
    "${UV_BIN}" run --project "${ROOT_DIR}" python - "$ROOT_DIR" "$CHECK_VERSION_UV_EXCLUDE_NEWER" <<'PY'
import sys
import tomllib
from pathlib import Path

root = Path(sys.argv[1])
expected = sys.argv[2]
failures = []
checked = 0
files = [
    path
    for path in sorted(root.rglob("pyproject.toml"))
    if ".git" not in path.parts and ".venv" not in path.parts and "dist" not in path.parts
]
for path in files:
    data = tomllib.loads(path.read_text(encoding="utf-8"))
    if "uv" not in data.get("tool", {}):
        continue
    checked += 1
    value = data["tool"]["uv"].get("exclude-newer")
    if value != expected:
        failures.append(f"{path.relative_to(root)}: exclude-newer={value!r}")

if failures:
    print("\n".join(failures))
    raise SystemExit(1)

print(checked)
PY
  )"; then
    fail_note "uv exclude-newer is not '${CHECK_VERSION_UV_EXCLUDE_NEWER}' for every uv-managed pyproject.toml"
    printf '%s\n' "${output}"
    return
  fi

  ok "All uv-managed pyproject.toml files set exclude-newer='${CHECK_VERSION_UV_EXCLUDE_NEWER}' (${output} file(s))"
}

check_docker_digest_pins() {
  local pins
  pins="$(
    "${UV_BIN}" run --project "${ROOT_DIR}" python - ${COMPOSE_FILES} <<'PY'
import re
import sys
from pathlib import Path

pattern = re.compile(r'image:\s*([A-Za-z0-9._/-]+):([^@\s]+)@(sha256:[0-9a-f]{64})')
seen = set()
for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    for image, tag, digest in pattern.findall(path.read_text(encoding="utf-8")):
        item = (image, tag, digest)
        if item in seen:
            continue
        seen.add(item)
        print(f"{image}\t{tag}\t{digest}")
PY
  )"

  section "Docker Images"

  local image tag digest resolved
  while IFS=$'\t' read -r image tag digest; do
    [[ -n "${image}" ]] || continue
    if [[ "${CHECK_VERSION_SKIP_UPSTREAM}" == "1" ]]; then
      warn "${image}:${tag} upstream resolution skipped"
      continue
    fi

    resolved="$(docker_tag_digest "${image}" "${tag}" 2>/dev/null || true)"
    if [[ -z "${resolved}" ]]; then
      warn "Could not resolve ${image}:${tag}"
      continue
    fi

    if [[ "${resolved}" == "${digest}" ]]; then
      ok "${image}:${tag} matches the pinned digest"
    else
      fail_note "${image}:${tag} resolves to ${resolved}, but the compose file pins ${digest}"
    fi
  done <<< "${pins}"
}

check_uv_builder_version() {
  local pins
  pins="$(
    "${UV_BIN}" run --project "${ROOT_DIR}" python - ${DOCKERFILES} <<'PY'
import re
import sys
from pathlib import Path

pattern = re.compile(r'COPY --from=ghcr\.io/astral-sh/uv:([^\s]+) /uv /usr/local/bin/uv')
seen = set()
for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    matches = pattern.findall(path.read_text(encoding="utf-8"))
    for version in matches:
        item = (version, str(path))
        if item in seen:
            continue
        seen.add(item)
        print(f"{version}\t{path}")
PY
  )"

  section "uv Builder"

  local versions
  versions="$(printf '%s\n' "${pins}" | cut -f1 | sed '/^$/d' | sort -u)"
  local version_count
  version_count="$(printf '%s\n' "${versions}" | sed '/^$/d' | wc -l | tr -d ' ')"
  if [[ "${version_count}" -ne 1 ]]; then
    fail_note "uv builder versions are not synchronized across Dockerfiles"
    printf '%s\n' "${pins}"
    return
  fi

  local version
  version="$(printf '%s\n' "${versions}" | sed -n '1p')"
  ok "All uv-backed Dockerfiles use ghcr.io/astral-sh/uv:${version}"

  if [[ "${CHECK_VERSION_SKIP_UPSTREAM}" == "1" ]]; then
    warn "astral-sh/uv ${version} upstream resolution skipped"
    return
  fi

  if github_commit_sha "astral-sh/uv" "${version}" >/dev/null 2>&1; then
    ok "astral-sh/uv tag ${version} resolves upstream"
  else
    warn "Could not resolve astral-sh/uv tag ${version}"
  fi
}

check_release_version_sync
check_action_pins
check_docker_digest_pins
check_uv_builder_version
check_npm_age_gates
check_bun_age_gates
check_uv_age_gates

if [[ "${FAILURES}" -ne 0 ]]; then
  printf '\n%s\n' "${FAILURES} version check(s) failed."
  exit 1
fi

printf '\nAll version checks passed.\n'
