#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="${CHECK_VERSION_REPO_ROOT:-${ROOT_DIR}}"
WORKFLOW_FILE="${CHECK_VERSION_WORKFLOW_FILE:-${REPO_ROOT}/.github/workflows/release.yml}"
CHECK_VERSION_SKIP_UPSTREAM="${CHECK_VERSION_SKIP_UPSTREAM:-0}"
CHECK_VERSION_GITHUB_API_BASE="${CHECK_VERSION_GITHUB_API_BASE:-https://api.github.com}"
CHECK_VERSION_TIMEOUT_SECONDS="${CHECK_VERSION_TIMEOUT_SECONDS:-15}"
CHECK_VERSION_NPM_MIN_RELEASE_AGE="${CHECK_VERSION_NPM_MIN_RELEASE_AGE:-7}"
CHECK_VERSION_BUN_MIN_RELEASE_AGE="${CHECK_VERSION_BUN_MIN_RELEASE_AGE:-604800}"
CHECK_VERSION_UV_EXCLUDE_NEWER="${CHECK_VERSION_UV_EXCLUDE_NEWER:-7 days}"
FAILURES=0

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

ok() { printf '%sOK%s   %s\n' "${GREEN}" "${NC}" "$*"; }
warn() { printf '%sWARN%s %s\n' "${YELLOW}" "${NC}" "$*"; }
fail_note() { printf '%sFAIL%s %s\n' "${RED}" "${NC}" "$*"; FAILURES=$((FAILURES + 1)); }
section() { printf '\n%s\n' "$*"; }

usage() {
  cat <<'EOF'
Usage: check-version.sh [--dry-run] [--execute]

Checks:
  - root GitHub Actions pins remain SHA-pinned with selector comments
  - repo-local dependency age gates stay aligned across .npmrc, bunfig.toml,
    and uv-managed pyproject.toml files

Options:
  --dry-run   Accepted for parity with other repo scripts. This command is read-only.
  --execute   Accepted for parity with other repo scripts. This command is read-only.
  -h, --help  Show this help.

Environment:
  CHECK_VERSION_REPO_ROOT=...           Override the repo root to scan.
  CHECK_VERSION_WORKFLOW_FILE=...       Override the workflow file to validate.
  CHECK_VERSION_SKIP_UPSTREAM=1         Skip network-backed upstream resolution.
  CHECK_VERSION_GITHUB_API_BASE=...     Override the GitHub API base URL.
  CHECK_VERSION_TIMEOUT_SECONDS=...     HTTP timeout in seconds. Default: 15.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run|--execute)
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

require() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1 || {
    printf '%s\n' "$bin not found in PATH" >&2
    exit 1
  }
}

require python3

github_commit_sha() {
  python3 - "$CHECK_VERSION_GITHUB_API_BASE" "$1" "$2" "$CHECK_VERSION_TIMEOUT_SECONDS" <<'PY'
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
        "User-Agent": "platform-check-version",
    },
)
with urllib.request.urlopen(request, timeout=int(timeout)) as response:
    payload = json.load(response)
print(payload["sha"])
PY
}

tracked_files() {
  local pattern="$1"

  if command -v git >/dev/null 2>&1 && git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "${REPO_ROOT}" ls-files -- "${pattern}" | sed "s#^#${REPO_ROOT}/#"
    return 0
  fi

  find "${REPO_ROOT}" \
    \( -path '*/.git' -o -path '*/node_modules' -o -path '*/.run' -o -path '*/dist' -o -path '*/build' -o -path '*/.venv' -o -path '*/venv' \) -prune \
    -o -type f -name "${pattern}" -print
}

check_action_pins() {
  local pins
  pins="$(
    python3 - "$WORKFLOW_FILE" <<'PY'
import re
import sys
from pathlib import Path

pattern = re.compile(
    r'uses:\s*([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)@([0-9a-f]{40})(?:\s*#\s*(v[^\s]+))?'
)
seen = set()
for repo, sha, selector in pattern.findall(Path(sys.argv[1]).read_text(encoding="utf-8")):
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
    python3 - "${REPO_ROOT}" "${CHECK_VERSION_NPM_MIN_RELEASE_AGE}" <<'PY'
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
expected = sys.argv[2]
files = sorted(p for p in repo_root.rglob(".npmrc") if ".git" not in p.parts and "node_modules" not in p.parts)
for path in files:
    actual = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("min-release-age="):
            actual = line.split("=", 1)[1].strip()
            break
    rel = path.relative_to(repo_root)
    print(f"{rel}\t{actual}")
    if actual != expected:
        raise SystemExit(1)
PY
  )"; then
    fail_note ".npmrc min-release-age gates are not synchronized at ${CHECK_VERSION_NPM_MIN_RELEASE_AGE}"
    printf '%s\n' "${output}"
    return
  fi

  ok "All .npmrc files set min-release-age=${CHECK_VERSION_NPM_MIN_RELEASE_AGE}"
}

check_bun_age_gates() {
  section "Bun Age Gates"

  local output
  if ! output="$(
    python3 - "${REPO_ROOT}" "${CHECK_VERSION_BUN_MIN_RELEASE_AGE}" <<'PY'
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
expected = sys.argv[2]
files = sorted(p for p in repo_root.rglob("bunfig.toml") if ".git" not in p.parts and "node_modules" not in p.parts)
pattern = re.compile(r'^\s*minimumReleaseAge\s*=\s*([0-9]+)\s*$')
for path in files:
    actual = None
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        match = pattern.match(raw_line)
        if match:
            actual = match.group(1)
            break
    rel = path.relative_to(repo_root)
    print(f"{rel}\t{actual}")
    if actual != expected:
        raise SystemExit(1)
PY
  )"; then
    fail_note "bun minimumReleaseAge gates are not synchronized at ${CHECK_VERSION_BUN_MIN_RELEASE_AGE}"
    printf '%s\n' "${output}"
    return
  fi

  ok "All bunfig.toml files set minimumReleaseAge=${CHECK_VERSION_BUN_MIN_RELEASE_AGE}"
}

check_uv_age_gates() {
  section "uv Age Gates"

  local output
  if ! output="$(
    python3 - "${REPO_ROOT}" "${CHECK_VERSION_UV_EXCLUDE_NEWER}" <<'PY'
import sys
import re
from pathlib import Path

repo_root = Path(sys.argv[1])
expected = sys.argv[2]
files = sorted(p for p in repo_root.rglob("pyproject.toml") if ".git" not in p.parts and "node_modules" not in p.parts)
tool_uv_pattern = re.compile(r"^\s*\[tool\.uv\]\s*$")
exclude_newer_pattern = re.compile(r'^\s*exclude-newer\s*=\s*"([^"]+)"\s*$')
for path in files:
    actual = None
    in_tool_uv = False
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line.startswith("[") and line.endswith("]"):
            in_tool_uv = bool(tool_uv_pattern.match(raw_line))
            continue
        if not in_tool_uv:
            continue
        match = exclude_newer_pattern.match(raw_line)
        if match:
            actual = match.group(1)
            break
    if actual is None:
        continue
    rel = path.relative_to(repo_root)
    print(f"{rel}\t{actual}")
    if actual != expected:
        raise SystemExit(1)
PY
  )"; then
    fail_note "uv exclude-newer gates are not synchronized at '${CHECK_VERSION_UV_EXCLUDE_NEWER}'"
    printf '%s\n' "${output}"
    return
  fi

  ok "All uv-managed pyproject.toml files set exclude-newer='${CHECK_VERSION_UV_EXCLUDE_NEWER}'"
}

check_action_pins
check_npm_age_gates
check_bun_age_gates
check_uv_age_gates

printf '\n'
if [[ "${FAILURES}" -gt 0 ]]; then
  printf 'version check(s) failed.\n' >&2
  exit 1
fi

printf 'All version checks passed.\n'
