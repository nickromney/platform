#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-${VERSION:-}}"
DRY_RUN="${DRY_RUN:-0}"
SKIP_CHECKS="${SKIP_CHECKS:-0}"

usage() {
  cat <<'EOF'
Usage:
  make release VERSION=X.Y.Z

Environment:
  DRY_RUN=1           Print the release plan without changing files.
  SKIP_CHECKS=1       Skip lint, test, and frontend checks.
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

CURRENT_VERSION="$(
  cd "${ROOT_DIR}"
  python3 - <<'PY'
import tomllib
from pathlib import Path

with Path("pyproject.toml").open("rb") as handle:
    print(tomllib.load(handle)["project"]["version"])
PY
)"

if [[ "${CURRENT_VERSION}" == "${VERSION}" ]]; then
  echo "version ${VERSION} is already current" >&2
  exit 1
fi

TAG="v${VERSION}"

if git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "tag ${TAG} already exists" >&2
  exit 1
fi

if [[ "${DRY_RUN}" != "1" && -n "$(git -C "${ROOT_DIR}" status --short)" ]]; then
  echo "git worktree must be clean before a real release" >&2
  exit 1
fi

run() {
  echo "+ $*"
  if [[ "${DRY_RUN}" != "1" ]]; then
    "$@"
  fi
}

run_in_dir() {
  local dir="$1"
  shift
  echo "+ (cd ${dir} && $*)"
  if [[ "${DRY_RUN}" != "1" ]]; then
    (
      cd "${dir}"
      "$@"
    )
  fi
}

cd "${ROOT_DIR}"

run python3 scripts/bump_version.py "${VERSION}"
run uv lock
run_in_dir "${ROOT_DIR}/ui" npm version "${VERSION}" --no-git-tag-version
run_in_dir "${ROOT_DIR}/examples/todo-app/frontend-astro" npm version "${VERSION}" --no-git-tag-version

if [[ "${SKIP_CHECKS}" != "1" ]]; then
  run make lint-check
  run make test
  run make frontend-check
fi

run git add pyproject.toml uv.lock app/main.py examples/hello-api/main.py \
  examples/todo-app/api-fastapi-container-app/main.py \
  examples/todo-app/api-clients/proxyman/todo-through-apim.har \
  ui/package.json ui/package-lock.json \
  examples/todo-app/frontend-astro/package.json \
  examples/todo-app/frontend-astro/package-lock.json

run git commit -m "chore(release): bump version to ${VERSION}"

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "dry run complete for release commit ${VERSION}"
else
  echo "created release commit for ${VERSION}"
  echo "next: push this branch and merge it"
  echo "next: on updated main, run make release-tag VERSION=${VERSION}"
fi
