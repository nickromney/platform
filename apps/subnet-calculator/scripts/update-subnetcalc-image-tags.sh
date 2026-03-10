#!/usr/bin/env bash
set -euo pipefail

: "${GITEA_HTTP_BASE:?GITEA_HTTP_BASE is required (e.g. http://gitea-http.gitea.svc.cluster.local:3000)}"
: "${GITEA_REPO_OWNER:?GITEA_REPO_OWNER is required}"
: "${REGISTRY_HOST:?REGISTRY_HOST is required}"
: "${TAG:?TAG is required}"

: "${REGISTRY_USERNAME:?REGISTRY_USERNAME is required (Gitea username)}"
: "${REGISTRY_PWD:?REGISTRY_PWD is required (Gitea password)}"

POLICIES_REPO_NAME="${POLICIES_REPO_NAME:-policies}"
POLICIES_BRANCH="${POLICIES_BRANCH:-main}"

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

for file in "${files[@]}"; do
	for image in "${images[@]}"; do
		prefix="${REGISTRY_HOST}/${GITEA_REPO_OWNER}/${image}:${TAG}"
		out="$(mktemp)"
		sed -E "s|(image:[[:space:]]*)([^[:space:]]*/)?${image}:[^[:space:]]+|\1${prefix}|g" "${file}" >"${out}"
		mv "${out}" "${file}"
	done
done

git config user.name "gitea-actions"
git config user.email "gitea-actions@local"

git add "${files[@]}"
if git diff --cached --quiet; then
	echo "Manifest already contained ${TAG}"
	exit 0
fi

git commit -m "chore: bump subnetcalc images to ${TAG}" >/dev/null
git push origin "${POLICIES_BRANCH}" >/dev/null

echo "Updated ${POLICIES_REPO_NAME} manifests to ${TAG}"
