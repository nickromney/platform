#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="${CHECK_VERSION_REPO_ROOT:-${ROOT_DIR}}"
WORKFLOW_FILE="${CHECK_VERSION_WORKFLOW_FILE:-}"
APIM_SIMULATOR_VENDOR_METADATA_FILE="${CHECK_VERSION_APIM_SIMULATOR_VENDOR_METADATA_FILE:-${REPO_ROOT}/apps/subnetcalc/apim-simulator.vendor.json}"
APIM_SIMULATOR_VENDOR_DIR="${CHECK_VERSION_APIM_SIMULATOR_VENDOR_DIR:-${REPO_ROOT}/apps/subnetcalc/apim-simulator}"
CHECK_VERSION_SKIP_UPSTREAM="${CHECK_VERSION_SKIP_UPSTREAM:-0}"
CHECK_VERSION_GITHUB_API_BASE="${CHECK_VERSION_GITHUB_API_BASE:-https://api.github.com}"
CHECK_VERSION_TIMEOUT_SECONDS="${CHECK_VERSION_TIMEOUT_SECONDS:-15}"
CHECK_VERSION_NPM_MIN_RELEASE_AGE="${CHECK_VERSION_NPM_MIN_RELEASE_AGE:-7}"
CHECK_VERSION_BUN_MIN_RELEASE_AGE="${CHECK_VERSION_BUN_MIN_RELEASE_AGE:-604800}"
CHECK_VERSION_UV_EXCLUDE_NEWER="${CHECK_VERSION_UV_EXCLUDE_NEWER:-7 days}"
FAILURES=0
EXECUTE=0
DRY_RUN=0

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
  - the vendored apim-simulator tag and commit SHA are recorded
  - repo-local dependency age gates stay aligned across .npmrc, bunfig.toml,
    and uv-managed pyproject.toml files outside the vendored apim-simulator tree

Options:
  --dry-run   Accepted for parity with other repo scripts. This command is read-only.
  --execute   Accepted for parity with other repo scripts. This command is read-only.
  -h, --help  Show this help.

Environment:
  CHECK_VERSION_REPO_ROOT=...           Override the repo root to scan.
  CHECK_VERSION_WORKFLOW_FILE=...       Override the single workflow file to validate.
  CHECK_VERSION_APIM_SIMULATOR_VENDOR_METADATA_FILE=...
                                        Override the APIM simulator vendoring metadata file.
  CHECK_VERSION_APIM_SIMULATOR_VENDOR_DIR=...
                                        Override the vendored APIM simulator directory.
  CHECK_VERSION_SKIP_UPSTREAM=1         Skip network-backed upstream resolution.
  CHECK_VERSION_GITHUB_API_BASE=...     Override the GitHub API base URL.
  CHECK_VERSION_TIMEOUT_SECONDS=...     HTTP timeout in seconds. Default: 15.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --execute)
      EXECUTE=1
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

if [[ "${DRY_RUN}" == "1" ]]; then
  printf 'INFO dry-run: would run platform version checks under %s\n' "${REPO_ROOT}"
  exit 0
fi

if [[ "${EXECUTE}" != "1" ]]; then
  usage
  printf 'INFO dry-run: would run platform version checks under %s\n' "${REPO_ROOT}"
  exit 0
fi

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
  section "GitHub Actions"

  local workflow_file_found=0
  local workflow_file="" pins="" repo="" sha="" selector="" resolved="" label=""

  while IFS= read -r workflow_file; do
    [[ -n "${workflow_file}" ]] || continue
    workflow_file_found=1
    pins="$(
      python3 - "$workflow_file" <<'PY'
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

    label="$(basename "${workflow_file}")"
    if [[ -z "${pins}" ]]; then
      warn "${label} has no SHA-pinned GitHub Actions"
      continue
    fi

    while IFS=$'\t' read -r repo sha selector; do
      [[ -n "${repo}" ]] || continue
      if [[ -z "${selector}" ]]; then
        fail_note "${label}: ${repo} is pinned by SHA without a trailing '# v...' selector comment"
        continue
      fi

      if [[ "${CHECK_VERSION_SKIP_UPSTREAM}" == "1" ]]; then
        warn "${label}: ${repo} ${selector} upstream resolution skipped"
        continue
      fi

      resolved="$(github_commit_sha "${repo}" "${selector}" 2>/dev/null || true)"
      if [[ -z "${resolved}" ]]; then
        warn "${label}: could not resolve ${repo} ${selector}"
        continue
      fi

      if [[ "${resolved}" == "${sha}" ]]; then
        ok "${label}: ${repo} ${selector} resolves to the pinned SHA"
      else
        fail_note "${label}: ${repo} ${selector} resolves to ${resolved}, but the workflow pins ${sha}"
      fi
    done <<< "${pins}"
  done < <(workflow_files)

  if [[ "${workflow_file_found}" != "1" ]]; then
    fail_note "No GitHub workflow files found to validate"
  fi
}

workflow_files() {
  if [[ -n "${WORKFLOW_FILE}" ]]; then
    printf '%s\n' "${WORKFLOW_FILE}"
    return 0
  fi

  if [[ ! -d "${REPO_ROOT}/.github/workflows" ]]; then
    return 0
  fi

  find "${REPO_ROOT}/.github/workflows" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | LC_ALL=C sort
}

check_apim_simulator_vendor() {
  section "Vendored APIM Simulator"

  local output
  if ! output="$(
    python3 - "${APIM_SIMULATOR_VENDOR_METADATA_FILE}" "${APIM_SIMULATOR_VENDOR_DIR}/pyproject.toml" <<'PY'
import json
import re
import sys
import tomllib
from pathlib import Path

metadata_path = Path(sys.argv[1])
pyproject_path = Path(sys.argv[2])

if not metadata_path.is_file():
    raise SystemExit(f"metadata file not found: {metadata_path}")
if not pyproject_path.is_file():
    raise SystemExit(f"vendored pyproject.toml not found: {pyproject_path}")

metadata = json.loads(metadata_path.read_text(encoding="utf-8"))
upstream = metadata.get("upstream", {})
subset = metadata.get("subset", {})
ref_kind = upstream.get("ref_kind", "")
requested_ref = upstream.get("requested_ref", "")
resolved_commit = upstream.get("resolved_commit", "")
profile = subset.get("profile", "full")

if not requested_ref:
    raise SystemExit("vendored apim-simulator metadata is missing upstream.requested_ref")
if not re.fullmatch(r"[0-9a-f]{40}", resolved_commit):
    raise SystemExit("vendored apim-simulator metadata is missing a 40-character upstream.resolved_commit")

version = tomllib.loads(pyproject_path.read_text(encoding="utf-8"))["project"]["version"]
if ref_kind == "tag" and requested_ref.startswith("v") and requested_ref[1:] != version:
    raise SystemExit(
        f"vendored apim-simulator tag {requested_ref} does not match pyproject version {version}"
    )

print(f"{ref_kind}\t{requested_ref}\t{resolved_commit}\t{version}\t{profile}")
PY
  )"; then
    fail_note "Vendored apim-simulator metadata is incomplete or inconsistent"
    printf '%s\n' "${output}"
    return
  fi

  local ref_kind requested_ref resolved_commit version profile
  IFS=$'\t' read -r ref_kind requested_ref resolved_commit version profile <<< "${output}"
  if [[ "${ref_kind}" == "tag" ]]; then
    ok "apim-simulator ${requested_ref} (${resolved_commit}) is vendored; version ${version}; profile ${profile}"
  else
    warn "apim-simulator was vendored from ${ref_kind} ${requested_ref} (${resolved_commit}); version ${version}; profile ${profile}"
  fi
}

check_npm_age_gates() {
  section "npm Age Gates"

  local output
  if ! output="$(
    python3 - "${REPO_ROOT}" "${CHECK_VERSION_NPM_MIN_RELEASE_AGE}" "${APIM_SIMULATOR_VENDOR_DIR}" <<'PY'
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
expected = sys.argv[2]
vendor_dir = Path(sys.argv[3]).resolve()

def included(path: Path) -> bool:
    resolved = path.resolve()
    return (
        ".git" not in path.parts
        and "node_modules" not in path.parts
        and not resolved.is_relative_to(vendor_dir)
    )

files = sorted(p for p in repo_root.rglob(".npmrc") if included(p))
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
    python3 - "${REPO_ROOT}" "${CHECK_VERSION_BUN_MIN_RELEASE_AGE}" "${APIM_SIMULATOR_VENDOR_DIR}" <<'PY'
import re
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
expected = sys.argv[2]
vendor_dir = Path(sys.argv[3]).resolve()

def included(path: Path) -> bool:
    resolved = path.resolve()
    return (
        ".git" not in path.parts
        and "node_modules" not in path.parts
        and not resolved.is_relative_to(vendor_dir)
    )

files = sorted(p for p in repo_root.rglob("bunfig.toml") if included(p))
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
    python3 - "${REPO_ROOT}" "${CHECK_VERSION_UV_EXCLUDE_NEWER}" "${APIM_SIMULATOR_VENDOR_DIR}" <<'PY'
import sys
import re
from pathlib import Path

repo_root = Path(sys.argv[1])
expected = sys.argv[2]
vendor_dir = Path(sys.argv[3]).resolve()

def included(path: Path) -> bool:
    resolved = path.resolve()
    return (
        ".git" not in path.parts
        and "node_modules" not in path.parts
        and not resolved.is_relative_to(vendor_dir)
    )

files = sorted(p for p in repo_root.rglob("pyproject.toml") if included(p))
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
check_apim_simulator_vendor
check_npm_age_gates
check_bun_age_gates
check_uv_age_gates

printf '\n'
if [[ "${FAILURES}" -gt 0 ]]; then
  printf 'version check(s) failed.\n' >&2
  exit 1
fi

printf 'All version checks passed.\n'
