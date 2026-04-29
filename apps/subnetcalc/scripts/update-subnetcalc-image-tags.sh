#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CLI_LIB="${SCRIPT_DIR}/../../../scripts/lib/shell-cli.sh"
if [[ -f "${SHELL_CLI_LIB}" ]]; then
  # shellcheck source=/dev/null
  source "${SHELL_CLI_LIB}"
else
  shell_cli_standard_options() {
    cat <<'EOF'
Options:
  --dry-run  Show a summary and exit before side effects
  --execute  Execute the script body; without it the script prints help and/or preview output
  -h, --help Show this message
EOF
  }

  shell_cli_handle_standard_no_args() {
    local usage_fn="$1"
    local dry_run_summary="$2"
    local execute=0
    local dry_run=0
    local script_name

    shift 2
    script_name="$(basename "$0")"

    while [[ $# -gt 0 ]]; do
      case "$1" in
        -h|--help)
          "${usage_fn}"
          exit 0
          ;;
        --dry-run)
          dry_run=1
          ;;
        --execute)
          execute=1
          ;;
        --)
          shift
          break
          ;;
        -*)
          printf '%s: unknown flag: %s\n' "${script_name}" "$1" >&2
          exit 1
          ;;
        *)
          printf '%s: unexpected argument: %s\n' "${script_name}" "$1" >&2
          exit 1
          ;;
      esac
      shift
    done

    if [[ $# -gt 0 ]]; then
      printf '%s: unexpected argument: %s\n' "${script_name}" "$1" >&2
      exit 1
    fi

    if [[ "${dry_run}" -eq 1 ]]; then
      printf 'INFO dry-run: %s\n' "${dry_run_summary}"
      exit 0
    fi

    if [[ "${execute}" -ne 1 ]]; then
      "${usage_fn}"
      printf 'INFO dry-run: %s\n' "${dry_run_summary}"
      exit 0
    fi
  }
fi

usage() {
  cat <<EOF
Usage: ${0##*/} [--dry-run] [--execute]

Clones the policies repo, rewrites subnet calculator workload image tags, and
pushes the updated manifests back to the configured branch.

$(shell_cli_standard_options)
EOF
}

shell_cli_handle_standard_no_args usage "would update subnet calculator manifest image tags in the configured policies repository" "$@"

: "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required (e.g. http://gitea-http.gitea.svc.cluster.local:3000)}"
: "${GITEA_REPO_OWNER:?GITEA_REPO_OWNER is required}"
: "${REGISTRY_HOST:?REGISTRY_HOST is required}"
: "${TAG:?TAG is required}"

: "${REGISTRY_USERNAME:?REGISTRY_USERNAME is required (Gitea username)}"
: "${REGISTRY_PWD:?REGISTRY_PWD is required (Gitea password)}"

POLICIES_REPO_NAME="${POLICIES_REPO_NAME:-policies}"
POLICIES_BRANCH="${POLICIES_BRANCH:-main}"
PUSH_RETRY_COUNT="${PUSH_RETRY_COUNT:-5}"
PUSH_RETRY_SLEEP_SECONDS="${PUSH_RETRY_SLEEP_SECONDS:-2}"

tmp=""
cleanup() {
	if [[ -n "${tmp}" && -d "${tmp}" ]]; then
		rm -rf "${tmp}"
	fi
}
trap cleanup EXIT

tmp="$(mktemp -d)"

# Ensure non-interactive HTTP auth works for clone/push.
git config --global credential.helper store
host="$(echo "${GITEA_HTTP_BASE}" | sed -E 's#^https?://##')"
proto="$(echo "${GITEA_HTTP_BASE}" | sed -E 's#^(https?)://.*#\1#')"
printf "protocol=%s\nhost=%s\nusername=%s\npassword=%s\n" \
	"${proto}" "${host}" "${REGISTRY_USERNAME}" "${REGISTRY_PWD}" |
	git credential-store store

POLICIES_URL="${GITEA_HTTP_BASE}/${GITEA_REPO_OWNER}/${POLICIES_REPO_NAME}.git"
git clone --depth 1 --branch "${POLICIES_BRANCH}" "${POLICIES_URL}" "${tmp}/policies" >/dev/null

cd "${tmp}/policies"

files=()

# New layout: shared workload manifest used by dev/uat overlays.
if [[ -f "apps/workloads/base/all.yaml" ]]; then
	files+=("apps/workloads/base/all.yaml")
fi

# Backward compatibility for older policy layouts.
if [[ -f "apps/dev/all.yaml" ]]; then
	files+=("apps/dev/all.yaml")
fi
if [[ -f "apps/uat/all.yaml" ]]; then
	files+=("apps/uat/all.yaml")
fi

if [[ ${#files[@]} -eq 0 ]]; then
	echo "No supported subnetcalc manifest files found under apps/" >&2
	exit 1
fi

images=(
  "subnetcalc-api-fastapi-container-app"
  "subnetcalc-apim-simulator"
  "subnetcalc-frontend-react"
  "subnetcalc-frontend-typescript-vite"
)

rewrite_files() {
  local file image prefix out

  for file in "${files[@]}"; do
    for image in "${images[@]}"; do
      prefix="${REGISTRY_HOST}/${GITEA_REPO_OWNER}/${image}:${TAG}"
      out="$(mktemp)"
      sed -E "s|(image:[[:space:]]*)([^[:space:]]*/)?${image}:[^[:space:]]+|\1${prefix}|g" "${file}" >"${out}"
      mv "${out}" "${file}"
    done
  done
}

git config user.name "gitea-actions"
git config user.email "gitea-actions@local"

for attempt in $(seq 1 "${PUSH_RETRY_COUNT}"); do
  git fetch --quiet origin "${POLICIES_BRANCH}"
  git checkout -B "${POLICIES_BRANCH}" "origin/${POLICIES_BRANCH}" >/dev/null

  rewrite_files
  git add "${files[@]}"

  if git diff --cached --quiet; then
    echo "Manifest already contained ${TAG}"
    exit 0
  fi

  git commit -m "chore: bump subnetcalc images to ${TAG}" >/dev/null
  if git push origin HEAD:"${POLICIES_BRANCH}" >/dev/null; then
    echo "Updated ${POLICIES_REPO_NAME} manifests to ${TAG}"
    exit 0
  fi

  git reset --hard "origin/${POLICIES_BRANCH}" >/dev/null
  sleep "${PUSH_RETRY_SLEEP_SECONDS}"
done

echo "Failed to push ${POLICIES_REPO_NAME} manifests after ${PUSH_RETRY_COUNT} attempts" >&2
exit 1
