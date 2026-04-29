#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_DIR="${ROOT_DIR}/scripts"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/lib/shell-cli.sh"

VERSION="${VERSION:-}"
DRY_RUN="${DRY_RUN:-0}"
EXECUTE=0
SKIP_CHECKS="${SKIP_CHECKS:-0}"
UV_BIN="${UV_BIN:-uv}"
RELEASE_FILES=(
  pyproject.toml
  uv.lock
  app/main.py
  examples/hello-api/main.py
  examples/todo-app/api-fastapi-container-app/main.py
  examples/todo-app/api-clients/proxyman/todo-through-apim.har
  ui/package.json
  ui/package-lock.json
  examples/todo-app/frontend-astro/package.json
  examples/todo-app/frontend-astro/package-lock.json
)

usage() {
  cat <<'EOF'
Usage:
  release.sh [--dry-run] [--execute] [--version X.Y.Z]
  release.sh [--dry-run] [--execute] X.Y.Z
  make release VERSION=X.Y.Z

Options:
  --version X.Y.Z  Release version to prepare.
  --dry-run        Print the release plan without changing files.
  --execute        Execute the release preparation.
  -h, --help       Show this help.

Environment:
  VERSION=...      Release version to prepare.
  DRY_RUN=1        Print the release plan without changing files.
  SKIP_CHECKS=1    Skip lint, test, and frontend checks.
EOF
}

script_name="$(basename "$0")"
while [[ $# -gt 0 ]]; do
  if shell_cli_handle_standard_flag usage "$1"; then
    if [[ "$1" == "--dry-run" ]]; then
      DRY_RUN=1
    elif [[ "$1" == "--execute" ]]; then
      EXECUTE=1
    fi
    shift
    continue
  fi

  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { shell_cli_missing_value "${script_name}" "$1"; exit 1; }
      VERSION="$2"
      shift 2
      ;;
    -*)
      shell_cli_unknown_flag "${script_name}" "$1"
      usage >&2
      exit 1
      ;;
    *)
      if [[ -z "${VERSION}" ]]; then
        VERSION="$1"
      elif [[ "${VERSION}" != "$1" ]]; then
        shell_cli_unexpected_arg "${script_name}" "$1"
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
    echo "INFO dry-run: would prepare a release after VERSION is provided"
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
  echo "INFO dry-run: would prepare release ${VERSION}"
  exit 0
fi

CURRENT_VERSION="$(
  cd "${ROOT_DIR}"
  "${UV_BIN}" run --project "${ROOT_DIR}" python - <<'PY'
import tomllib
from pathlib import Path

with Path("pyproject.toml").open("rb") as handle:
    print(tomllib.load(handle)["project"]["version"])
PY
)"

TAG="v${VERSION}"
RELEASE_COMMIT_SUBJECT="chore(release): bump version to ${VERSION}"
VERSION_ALREADY_CURRENT=0

release_file_matches() {
  local path="$1"
  local release_file

  for release_file in "${RELEASE_FILES[@]}"; do
    if [[ "${path}" == "${release_file}" ]]; then
      return 0
    fi
  done

  return 1
}

first_non_release_dirty_path() {
  local path

  while IFS= read -r path; do
    path="${path#???}"
    [[ -n "${path}" ]] || continue
    if [[ "${path}" == *" -> "* ]]; then
      path="${path##* -> }"
    fi
    if ! release_file_matches "${path}"; then
      printf '%s\n' "${path}"
      return 0
    fi
  done < <(git -C "${ROOT_DIR}" status --short)

  return 1
}

release_files_have_changes() {
  if ! git -C "${ROOT_DIR}" diff --quiet -- "${RELEASE_FILES[@]}"; then
    return 0
  fi
  if ! git -C "${ROOT_DIR}" diff --cached --quiet -- "${RELEASE_FILES[@]}"; then
    return 0
  fi

  return 1
}

if [[ "${CURRENT_VERSION}" == "${VERSION}" ]]; then
  RELEASE_COMMIT_PRESENT="$(
    git -C "${ROOT_DIR}" log -F --grep="${RELEASE_COMMIT_SUBJECT}" --format=%s -n 1 2>/dev/null || true
  )"
  if git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null || \
      [[ -n "${RELEASE_COMMIT_PRESENT}" ]]; then
    echo "release ${VERSION} is already complete"
    exit 0
  fi

  VERSION_ALREADY_CURRENT=1
  if [[ "${DRY_RUN}" != "1" ]]; then
    if non_release_dirty_path="$(first_non_release_dirty_path)"; then
      echo "git worktree has non-release changes (${non_release_dirty_path}); commit or stash them before resuming release ${VERSION}" >&2
      exit 1
    fi
    if ! release_files_have_changes; then
      echo "version ${VERSION} is already current, but no release commit or tag exists" >&2
      exit 1
    fi
  fi
fi

if [[ "${VERSION_ALREADY_CURRENT}" != "1" ]]; then
  if git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
    echo "tag ${TAG} already exists" >&2
    exit 1
  fi

  if [[ "${DRY_RUN}" != "1" && -n "$(git -C "${ROOT_DIR}" status --short)" ]]; then
    echo "git worktree must be clean before a real release" >&2
    exit 1
  fi
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

if [[ "${VERSION_ALREADY_CURRENT}" == "1" ]]; then
  echo "version ${VERSION} is already current; resuming release checks and commit"
else
  run "${UV_BIN}" run --project "${ROOT_DIR}" python scripts/bump_version.py "${VERSION}"
  run uv lock
  run_in_dir "${ROOT_DIR}/ui" npm version "${VERSION}" --no-git-tag-version
  run_in_dir "${ROOT_DIR}/examples/todo-app/frontend-astro" npm version "${VERSION}" --no-git-tag-version
fi

if [[ "${SKIP_CHECKS}" != "1" ]]; then
  run make check-version
  run make lint
  run make test
  run make frontend-check
fi

run git add "${RELEASE_FILES[@]}"

run git commit -m "chore(release): bump version to ${VERSION}"

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "dry run complete for release commit ${VERSION}"
else
  echo "created release commit for ${VERSION}"
  echo "next: push this branch and merge it"
  echo "next: on updated main, run make release-tag VERSION=${VERSION}"
fi
