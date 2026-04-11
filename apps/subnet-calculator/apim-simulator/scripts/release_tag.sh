#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${VERSION:-}}"
DRY_RUN="${DRY_RUN:-0}"
TAG_BRANCH="${TAG_BRANCH:-main}"

usage() {
  cat <<'EOF'
Usage:
  make release-tag VERSION=X.Y.Z

Environment:
  DRY_RUN=1         Print the tagging plan without changing git state.
  TAG_BRANCH=...    Branch required for tagging. Defaults to main.
EOF
}

if [[ -z "${VERSION}" ]]; then
  usage >&2
  exit 1
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must match X.Y.Z" >&2
  exit 1
fi

TAG="v${VERSION}"
CURRENT_BRANCH="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD)"

if [[ "${DRY_RUN}" != "1" && "${CURRENT_BRANCH}" != "${TAG_BRANCH}" ]]; then
  echo "release tags must be created from ${TAG_BRANCH}; current branch is ${CURRENT_BRANCH}" >&2
  exit 1
fi

if [[ "${DRY_RUN}" != "1" && -n "$(git -C "${ROOT_DIR}" status --short)" ]]; then
  echo "git worktree must be clean before creating a release tag" >&2
  exit 1
fi

CURRENT_VERSION="$(
  cd "${ROOT_DIR}"
  python3 - <<'PY'
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
  echo "tag ${TAG} already exists" >&2
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
