.PHONY: state-reset
state-reset:
	@set -euo pipefail; \
	lock_file="$(STATE_LOCK_FILE)"; \
	if [ ! -e "$$lock_file" ]; then \
		echo "OK   No Terraform/OpenTofu state lock found: $$lock_file"; \
		exit 0; \
	fi; \
	echo "This will remove the Terraform/OpenTofu state lock only:"; \
	echo "  - $$lock_file"; \
	if command -v jq >/dev/null 2>&1; then \
		lock_summary="$$(jq -r '[.Operation,.Who,.Created] | map(select(. != null and . != "")) | join("; ")' "$$lock_file" 2>/dev/null || true)"; \
		if [ -n "$$lock_summary" ]; then echo "Lock: $$lock_summary"; fi; \
	fi; \
	if [ "$(AUTO_APPROVE)" != "1" ]; then \
		if [ ! -t 0 ]; then echo "ABORTED: state reset requires AUTO_APPROVE=1 in non-interactive mode. No state files were changed."; exit 2; fi; \
		printf "Proceed with Terraform/OpenTofu state lock removal? [y/N] "; read -r confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then echo "ABORTED: state reset cancelled by user. No state files were changed."; exit 0; fi; \
	fi; \
	rm -f "$$lock_file"; \
	echo "OK   Removed Terraform/OpenTofu state lock: $$lock_file"

# Adapters keep a variant preamble (kind refreshes the split kubeconfig; lima
# may open the API tunnel) and set KUBECONFIG_STACK_LABEL.
KUBECONFIG_STACK_LABEL ?= kubeconfig
define check_kubeconfig_body
default_kubeconfig="$(DEFAULT_KUBECONFIG_PATH)"; \
	"$(KUBECONFIG_HELPER)" --execute --action ensure-valid --kubeconfig "$$default_kubeconfig"; \
	default_count=$$("$(KUBECONFIG_HELPER)" --execute --action count-contexts --kubeconfig "$$default_kubeconfig"); \
	default_current=$$(kubectl --kubeconfig "$$default_kubeconfig" config current-context 2>/dev/null || true); \
	[ -n "$$default_current" ] || default_current="<none>"; \
	echo "OK   default kubeconfig: $$default_kubeconfig ($$default_count context(s), current=$$default_current)"; \
	"$(KUBECONFIG_HELPER)" --execute --action ensure-valid --kubeconfig "$(KUBECONFIG_PATH)"; \
	stack_count=$$("$(KUBECONFIG_HELPER)" --execute --action count-contexts --kubeconfig "$(KUBECONFIG_PATH)"); \
	stack_current=$$(kubectl --kubeconfig "$(KUBECONFIG_PATH)" config current-context 2>/dev/null || true); \
	[ -n "$$stack_current" ] || stack_current="<none>"; \
	echo "OK   $(KUBECONFIG_STACK_LABEL): $(KUBECONFIG_PATH) ($$stack_count context(s), current=$$stack_current)"; \
	kubie_lint_output="$$("$(KUBECONFIG_HELPER)" --execute --action lint || true)"; \
	if [ -n "$$kubie_lint_output" ]; then \
		echo "WARN kubie lint:"; \
		printf '%s\n' "$$kubie_lint_output" | sed 's/^/  /'; \
	elif command -v kubie >/dev/null 2>&1; then \
		echo "OK   kubie lint"; \
	fi
endef

CONFLICTING_CLUSTER_CHECK ?=
.PHONY: check-conflicting-clusters-stopped
check-conflicting-clusters-stopped:
	@$(MAKE) $(CONFLICTING_CLUSTER_CHECK)

GITEA_SYNC_KUBECONFIG_TARGET ?= check-kubeconfig
GITEA_SYNC_ASSERT_TARGET ?=
GITEA_LOCAL_ACCESS_MODE_DEFAULT ?= port-forward
GITEA_SYNC_EXTRA_ENV ?=
.PHONY: gitea-sync
gitea-sync: workflow-validate-stage
	@set -euo pipefail; \
	$(MAKE) check-platform-env; \
	$(MAKE) $(GITEA_SYNC_KUBECONFIG_TARGET) >/dev/null; \
	$(MAKE) $(GITEA_SYNC_ASSERT_TARGET) >/dev/null; \
	stack_path="$(abspath $(STACK_DIR))"; \
	script="$$stack_path/scripts/sync-gitea.sh"; \
	if [ ! -x "$$script" ]; then echo "Missing $$script"; exit 1; fi; \
	mode_flag="--execute"; \
	sync_stage_file="$(abspath $(STAGE_FILE_REL_900))"; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then sync_stage_file="$(stage_var_file)"; fi; \
	if [ "$(DRY_RUN)" = "1" ]; then mode_flag="--dry-run"; fi; \
	GITEA_POLICIES_REMOTE="$${GITEA_POLICIES_REMOTE:-http://127.0.0.1:30090/platform/policies.git}" \
	GITEA_BRANCH="$${GITEA_BRANCH:-main}" \
	GITEA_USER="$${GITEA_USER:-gitea-admin}" \
	GITEA_PASSWORD="$${GITEA_PASSWORD:-$${PLATFORM_ADMIN_PASSWORD}}" \
	GITEA_LOCAL_ACCESS_MODE="$${GITEA_LOCAL_ACCESS_MODE:-$(GITEA_LOCAL_ACCESS_MODE_DEFAULT)}" \
	GITEA_SYNC_TFVARS_FILE="$$sync_stage_file" \
	$(GITEA_SYNC_EXTRA_ENV) \
	STACK_DIR="$$stack_path" \
	KUBECONFIG="$(KUBECONFIG_PATH)" \
	KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" \
	"$$script" "$$mode_flag"
