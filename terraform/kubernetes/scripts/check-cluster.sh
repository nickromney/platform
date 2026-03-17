#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/platform-env.sh"
platform_load_env

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

ok() { echo "${GREEN}✔${NC} $*"; }
warn() { echo "${YELLOW}⚠${NC} $*"; }
fail() {
	echo "${RED}✖${NC} $*" >&2
	exit 1
}

require() {
	local bin="$1"
	command -v "$bin" >/dev/null 2>&1 || fail "$bin not found in PATH"
}

require curl
require jq

GITEA_USER="${GITEA_USER:-gitea-admin}"
if [[ -z "${GITEA_PWD:-}" ]]; then
	platform_require_vars PLATFORM_ADMIN_PASSWORD || exit 1
	GITEA_PWD="${PLATFORM_ADMIN_PASSWORD}"
else
	GITEA_PWD="${GITEA_PWD}"
fi
GITEA_HOST="${GITEA_HOST:-localhost:30090}"
REGISTRY_HOST="${REGISTRY_HOST:-localhost:30090}"
EXPECT_SENTIMENT_REPO="${EXPECT_SENTIMENT_REPO:-1}"
EXPECT_SUBNETCALC_REPO="${EXPECT_SUBNETCALC_REPO:-1}"
EXPECT_ACTIONS_RUNS="${EXPECT_ACTIONS_RUNS:-1}"
EXPECT_NAMESPACE_SSO="${EXPECT_NAMESPACE_SSO:-1}"
EXPECT_NAMESPACE_OBSERVABILITY="${EXPECT_NAMESPACE_OBSERVABILITY:-1}"
EXPECT_NAMESPACE_PLATFORM_GATEWAY="${EXPECT_NAMESPACE_PLATFORM_GATEWAY:-1}"

check_gitea_repos() {
	echo "=== Gitea Repos ==="

	local repos
	repos=$(curl -s -u "${GITEA_USER}:${GITEA_PWD}" "http://${GITEA_HOST}/api/v1/orgs/platform/repos" 2>/dev/null | jq -r '.[].name' 2>/dev/null || echo "")

	if [ -z "$repos" ]; then
		warn "No repos found (or Gitea unreachable)"
		return 1
	fi

	local expected_repos=("policies")

	if [ "${EXPECT_SENTIMENT_REPO}" = "1" ]; then
		expected_repos+=("sentiment")
	fi

	if [ "${EXPECT_SUBNETCALC_REPO}" = "1" ]; then
		expected_repos+=("subnet-calculator")
	fi

	for repo in "${expected_repos[@]}"; do
		if echo "$repos" | grep -qx "$repo"; then
			ok "Repo: $repo"
		else
			fail "Missing repo: $repo"
		fi
	done

	echo ""
	ok "All expected repos exist"
	echo ""
}

check_gitea_actions() {
	echo "=== Gitea Actions (recent runs) ==="

	if [ "${EXPECT_ACTIONS_RUNS}" != "1" ]; then
		warn "Skipping workflow run checks (actions runner not expected)"
		echo ""
		return 0
	fi

	local repos=()

	if [ "${EXPECT_SENTIMENT_REPO}" = "1" ]; then
		repos+=("sentiment")
	fi

	if [ "${EXPECT_SUBNETCALC_REPO}" = "1" ]; then
		repos+=("subnet-calculator")
	fi

	if [ "${#repos[@]}" -eq 0 ]; then
		warn "Skipping workflow run checks (no app repos expected)"
		echo ""
		return 0
	fi

	for repo in "${repos[@]}"; do
		echo "--- $repo ---"
		local json
		json=$(curl -s -u "${GITEA_USER}:${GITEA_PWD}" "http://${GITEA_HOST}/api/v1/repos/platform/${repo}/actions/runs?limit=3" 2>/dev/null || echo "{}")

		if echo "$json" | jq -e '.workflow_runs' >/dev/null 2>&1; then
			local count
			count=$(echo "$json" | jq -r '.workflow_runs | length' 2>/dev/null || echo "0")
			if [ "$count" -eq 0 ] || [ "$count" = "0" ]; then
				warn "No workflow runs for $repo"
				continue
			fi

			echo "$json" | jq -r '.workflow_runs[] | "\(.head_sha[0:8]) \(.status) \(.conclusion // "nil")"' 2>/dev/null || warn "Failed to parse $repo workflows"
		else
			warn "No workflows or API error for $repo"
		fi
		echo ""
	done
}

check_registry_images() {
	echo "=== Docker Registry Images ==="

	local images=(
		"subnetcalc-frontend-react:latest"
		"subnetcalc-frontend-typescript-vite:latest"
		"subnetcalc-api-fastapi-container-app:latest"
		"subnetcalc-apim-simulator:latest"
		"sentiment-api:latest"
		"sentiment-auth-ui:latest"
	)

	for img in "${images[@]}"; do
		local name="${img%:*}"

		local result
		result=$(curl -s -u "${GITEA_USER}:${GITEA_PWD}" "http://${REGISTRY_HOST}/v2/platform/${name}/tags/list" 2>/dev/null | jq -r '.tags | if . then join(", ") else "NOT FOUND" end' 2>/dev/null || echo "ERROR")

		if [ "$result" = "NOT FOUND" ] || [ "$result" = "ERROR" ]; then
			fail "Image: platform/${name} - $result"
		else
			ok "Image: platform/${name} - tags: $result"
		fi
	done
	echo ""
}

check_argocd_apps() {
	echo "=== ArgoCD Applications ==="

	if ! command -v kubectl >/dev/null 2>&1; then
		warn "kubectl not available, skipping ArgoCD check"
		return 0
	fi

	local apps
	apps=$(kubectl get applications -n argocd -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.sync.status}{"\t"}{.status.health.status}{"\n"}{end}' 2>/dev/null || echo "")

	if [ -z "$apps" ]; then
		warn "No ArgoCD apps found (or cluster unreachable)"
		return 1
	fi

	local issues=0

	while IFS=$'\t' read -r name sync health; do
		if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then
			ok "App: $name (Synced, Healthy)"
		elif [ "$sync" = "OutOfSync" ]; then
			warn "App: $name (OutOfSync, $health)"
			issues=1
		elif [ "$health" = "Progressing" ]; then
			warn "App: $name (Synced, Progressing)"
			issues=1
		elif [ "$health" = "Missing" ]; then
			fail "App: $name (Missing)"
		else
			warn "App: $name (sync=$sync, health=$health)"
			issues=1
		fi
	done <<<"$apps"

	echo ""
	if [ "$issues" -eq 0 ]; then
		ok "All ArgoCD apps are healthy"
	fi
}

check_pods() {
	echo "=== Kubernetes Pods (non-system) ==="

	if ! command -v kubectl >/dev/null 2>&1; then
		warn "kubectl not available, skipping pod check"
		return 0
	fi

	local namespaces=("dev" "uat")
	local issues=0

	for ns in "${namespaces[@]}"; do
		echo "--- Namespace: $ns ---"

		local pods
		pods=$(kubectl get pods -n "$ns" -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\t"}{.status.reason}{"\n"}{end}' 2>/dev/null || echo "")

		if [ -z "$pods" ]; then
			warn "No pods in $ns"
			continue
		fi

			while IFS=$'\t' read -r name phase reason; do
				detail=""
				if [ -n "$reason" ]; then
					detail=", reason=$reason"
				fi
				if [ "$phase" = "Running" ]; then
					ok "Pod: $name ($phase${detail})"
				elif [ "$phase" = "Pending" ]; then
					warn "Pod: $name ($phase${detail})"
					issues=1
				elif [ "$phase" = "Failed" ] || echo "$reason" | grep -Eq 'BackOff|ImagePull|Error|CrashLoop'; then
					fail "Pod: $name ($phase${detail})"
				else
					warn "Pod: $name ($phase${detail})"
					issues=1
				fi
			done <<<"$pods"
		echo ""
	done

	if [ "$issues" -eq 0 ]; then
		ok "All pods are running"
	fi
}

check_namespaces() {
	echo "=== Kubernetes Namespaces ==="

	if ! command -v kubectl >/dev/null 2>&1; then
		warn "kubectl not available"
		return 0
	fi

	local expected_namespaces=("dev" "uat" "apim" "argocd" "gitea")

	if [ "${EXPECT_NAMESPACE_SSO}" = "1" ]; then
		expected_namespaces+=("sso")
	fi

	if [ "${EXPECT_NAMESPACE_OBSERVABILITY}" = "1" ]; then
		expected_namespaces+=("observability")
	fi

	if [ "${EXPECT_NAMESPACE_PLATFORM_GATEWAY}" = "1" ]; then
		expected_namespaces+=("platform-gateway")
	fi

	for ns in "${expected_namespaces[@]}"; do
		if kubectl get ns "$ns" >/dev/null 2>&1; then
			ok "Namespace: $ns"
		else
			fail "Namespace missing: $ns"
		fi
	done
	echo ""
}

main() {
	echo ""
	ok "Cluster Debug Check"
	echo "===================="
	echo ""

	check_gitea_repos
	check_registry_images
	check_argocd_apps
	check_namespaces
	check_pods

	echo "=== Summary ==="
	echo ""
	ok "Debug check complete"
	echo ""
	echo "If issues found:"
	echo "  - Check Gitea Actions runs at: http://${GITEA_HOST}/platform"
	echo "  - Check ArgoCD UI at: http://localhost:30080"
	echo "  - For stuck pods: kubectl describe pod <name> -n <namespace>"
	echo "  - For image issues: kubectl get events --field-selector involvedObject.name=<pod>,reason=Failed"
}

main "$@"
