#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-}"
DRY_RUN="${DRY_RUN:-0}"
EXECUTE=0
SKIP_CHECKS="${SKIP_CHECKS:-0}"
VERSION_FILE="${VERSION_FILE:-${ROOT_DIR}/VERSION}"

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
  SKIP_CHECKS=1    Skip check-version, lint, and shell tests.
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

TAG="v${VERSION}"
RELEASE_COMMIT_SUBJECT="chore(release): bump version to ${VERSION}"
VERSION_REL_PATH="${VERSION_FILE#${ROOT_DIR}/}"
CURRENT_VERSION=""
if [[ -f "${VERSION_FILE}" ]]; then
  CURRENT_VERSION="$(tr -d '[:space:]' <"${VERSION_FILE}")"
fi
VERSION_FILE_STATUS="$(git -C "${ROOT_DIR}" status --short -- "${VERSION_REL_PATH}")"

if [[ "${CURRENT_VERSION}" == "${VERSION}" ]]; then
  RELEASE_COMMIT_PRESENT="$(
    git -C "${ROOT_DIR}" log -F --grep="${RELEASE_COMMIT_SUBJECT}" --format=%s -n 1 2>/dev/null || true
  )"
  if git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null || \
      [[ -n "${RELEASE_COMMIT_PRESENT}" ]]; then
    echo "release ${VERSION} is already complete"
    exit 0
  fi

  if [[ -z "${VERSION_FILE_STATUS}" ]]; then
    echo "release ${VERSION} is already prepared"
    echo "next: merge the release commit, then run make release-tag VERSION=${VERSION} from main"
    exit 0
  fi
fi

if git -C "${ROOT_DIR}" rev-parse -q --verify "refs/tags/${TAG}" >/dev/null; then
  echo "tag ${TAG} already exists" >&2
  exit 1
fi

if [[ "${DRY_RUN}" != "1" ]]; then
  NON_VERSION_STATUS="$(git -C "${ROOT_DIR}" status --short -- . ":(exclude)${VERSION_REL_PATH}")"
  if [[ -n "${NON_VERSION_STATUS}" || ( -n "${VERSION_FILE_STATUS}" && "${CURRENT_VERSION}" != "${VERSION}" ) ]]; then
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

write_version() {
  echo "+ write ${VERSION_REL_PATH} ${VERSION}"
  if [[ "${DRY_RUN}" != "1" ]]; then
    printf '%s\n' "${VERSION}" >"${VERSION_FILE}"
  fi
}

cd "${ROOT_DIR}"

write_version

if [[ "${SKIP_CHECKS}" != "1" ]]; then
  run make check-version
  run make lint
  run bats tests
fi

run git add VERSION
run git commit -m "${RELEASE_COMMIT_SUBJECT}"

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "dry run complete for release commit ${VERSION}"
else
  echo "created release commit for ${VERSION}"
  echo "next: push this branch and merge it"
  echo "next: on updated main, run make release-tag VERSION=${VERSION}"
fi
