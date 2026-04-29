#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

VERSION="${VERSION:-}"
DRY_RUN="${DRY_RUN:-0}"
EXECUTE=0
TAG_BRANCH="${TAG_BRANCH:-main}"
UV_BIN="${UV_BIN:-uv}"

usage() {
  cat <<'EOF'
Usage:
  release_tag.sh [--dry-run] [--execute] [--branch NAME] [--version X.Y.Z]
  release_tag.sh [--dry-run] [--execute] [--branch NAME] X.Y.Z
  make release-tag VERSION=X.Y.Z

Options:
  --version X.Y.Z  Release version to tag.
  --branch NAME   Branch required for tagging. Defaults to main.
  --dry-run       Print the tagging plan without changing git state.
  --execute       Accepted for parity with other repo scripts.
  -h, --help      Show this help.

Environment:
  VERSION=...      Release version to tag.
  DRY_RUN=1         Print the tagging plan without changing git state.
  TAG_BRANCH=...    Branch required for tagging. Defaults to main.
EOF
}

script_name="$(basename "$0")"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "${script_name}: missing value for $1" >&2; exit 1; }
      VERSION="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || { echo "${script_name}: missing value for $1" >&2; exit 1; }
      TAG_BRANCH="$2"
      shift 2
      ;;
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
    -*)
      echo "${script_name}: unknown flag: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "${VERSION}" ]]; then
        VERSION="$1"
      elif [[ "${VERSION}" != "$1" ]]; then
        echo "${script_name}: unexpected argument: $1" >&2
        usage >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "${VERSION}" ]]; then
  if [[ "${EXECUTE}" != "1" ]]; then
    usage
    echo "INFO dry-run: would create a release tag after VERSION is provided"
    exit 0
  fi

  usage >&2
  exit 1
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must match X.Y.Z" >&2
  exit 1
fi

if [[ "${DRY_RUN}" != "1" && "${EXECUTE}" != "1" ]]; then
  usage
  echo "INFO dry-run: would create annotated tag v${VERSION} from ${TAG_BRANCH}"
  exit 0
fi

TAG="v${VERSION}"

CURRENT_VERSION="$(
  cd "${ROOT_DIR}"
  "${UV_BIN}" run --project "${ROOT_DIR}" python - <<'PY'
import tomllib
from pathlib import Path

with Path("pyproject.toml").open("rb") as handle:
    print(tomllib.load(handle)["project"]["version"])
PY
)"

if [[ "${CURRENT_VERSION}" != "${VERSION}" ]]; then
  echo "pyproject.toml version is ${CURRENT_VERSION}, expected ${VERSION}" >&2
  exit 1
fi

if git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "tag ${TAG} already exists; release is already complete"
  exit 0
fi

CURRENT_BRANCH="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD)"

if [[ "${DRY_RUN}" != "1" && "${CURRENT_BRANCH}" != "${TAG_BRANCH}" ]]; then
  echo "release tags must be created from ${TAG_BRANCH}; current branch is ${CURRENT_BRANCH}" >&2
  exit 1
fi

if [[ "${DRY_RUN}" != "1" && -n "$(git -C "${ROOT_DIR}" status --short)" ]]; then
  echo "git worktree must be clean before creating a release tag" >&2
  exit 1
fi

echo "+ git tag -a ${TAG} -m Release ${TAG}"
if [[ "${DRY_RUN}" != "1" ]]; then
  git -C "${ROOT_DIR}" tag -a "${TAG}" -m "Release ${TAG}"
  echo "created tag ${TAG}"
  echo "next: git push origin ${TAG}"
else
  echo "dry run complete for ${TAG}"
fi
