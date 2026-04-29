#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

SOURCE_REPO="${ROOT_DIR}"
COMMIT=""
METADATA_FILE=""

usage() {
  cat <<'EOF'
Usage:
  release_version.sh [--dry-run] [--execute] [--source PATH] [--commit SHA] [--metadata PATH]

Resolve the release version for a source checkout, commit SHA, or vendored
metadata file.

Options:
  --source PATH    apim-simulator checkout to inspect (default: repository root)
  --commit SHA     Commit to inspect (default: HEAD of --source)
  --metadata PATH  Vendored apim-simulator metadata JSON; uses the recorded
                   upstream.resolved_commit
  --dry-run        Show the resolution target without reading git metadata
  --execute        Resolve the release version
  -h, --help       Show this help.
EOF
}

shell_cli_init_standard_flags
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    shift
    continue
  fi

  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "release_version.sh: missing value for $1" >&2; exit 1; }
      SOURCE_REPO="$2"
      shift 2
      ;;
    --commit)
      [[ $# -ge 2 ]] || { echo "release_version.sh: missing value for $1" >&2; exit 1; }
      COMMIT="$2"
      shift 2
      ;;
    --metadata)
      [[ $# -ge 2 ]] || { echo "release_version.sh: missing value for $1" >&2; exit 1; }
      METADATA_FILE="$2"
      shift 2
      ;;
    -*)
      echo "release_version.sh: unknown flag: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      echo "release_version.sh: unexpected argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

shell_cli_maybe_execute_or_preview_summary usage \
  "would resolve APIM simulator release version from source ${SOURCE_REPO}"

if [[ ! -d "${SOURCE_REPO}/.git" ]]; then
  echo "release_version.sh: source is not a git checkout: ${SOURCE_REPO}" >&2
  exit 1
fi

if [[ -n "${METADATA_FILE}" ]]; then
  if [[ ! -f "${METADATA_FILE}" ]]; then
    echo "release_version.sh: metadata file not found: ${METADATA_FILE}" >&2
    exit 1
  fi

  metadata_commit="$(
    python3 - "${METADATA_FILE}" <<'PY'
import json
import sys
from pathlib import Path

metadata = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(metadata["upstream"]["resolved_commit"])
PY
  )"

  if [[ -n "${COMMIT}" && "${COMMIT}" != "${metadata_commit}" ]]; then
    echo "release_version.sh: commit ${COMMIT} does not match metadata commit ${metadata_commit}" >&2
    exit 1
  fi

  COMMIT="${metadata_commit}"
fi

if [[ -z "${COMMIT}" ]]; then
  COMMIT="$(git -C "${SOURCE_REPO}" rev-parse HEAD)"
fi

VERSION="$(
  python3 - "${SOURCE_REPO}" "${COMMIT}" <<'PY'
import subprocess
import sys
import tomllib
from pathlib import Path

repo = Path(sys.argv[1])
commit = sys.argv[2]

try:
    payload = subprocess.check_output(
        ["git", "-C", str(repo), "show", f"{commit}:pyproject.toml"],
        text=True,
    )
except subprocess.CalledProcessError as exc:
    raise SystemExit(f"release_version.sh: could not read pyproject.toml from {commit} in {repo}") from exc

print(tomllib.loads(payload)["project"]["version"])
PY
)"

printf 'v%s\n' "${VERSION}"
