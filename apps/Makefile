USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs test js-check update trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-apim-simulator compose-smoke-chatgpt-sim compose-smoke-idp-core compose-smoke-platform-mcp compose-smoke-sentiment compose-smoke-subnetcalc apim-simulator-test chatgpt-sim-test idp-core-test langfuse-demos-test platform-mcp-test sentiment-test shared-apphttp-test shared-appshell-test shared-idpauth-test subnetcalc-test
MAKE_SUGGEST_SCRIPT := ../scripts/suggest-make-goal.sh

include ../mk/common.mk

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TRIVY_SCAN_SCRIPT := $(MAKEFILE_DIR)../scripts/trivy-scan-apps.sh

define app_wrapper_dirs_with_target
$(shell for makefile in ./*/Makefile; do grep -q '^$(1):' "$$makefile" || continue; dirname "$$makefile" | cut -c3-; done | LC_ALL=C sort)
endef

APP_COMPOSE_SMOKE_DIRS := $(call app_wrapper_dirs_with_target,compose-smoke)
APP_JS_CHECK_DIRS := $(call app_wrapper_dirs_with_target,app-js-check)
APP_TEST_DIRS := $(call app_wrapper_dirs_with_target,test)
APP_UPDATE_DIRS := $(call app_wrapper_dirs_with_target,update)

.PHONY: prereqs test js-check update trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-apim-simulator compose-smoke-chatgpt-sim compose-smoke-idp-core compose-smoke-platform-mcp compose-smoke-sentiment compose-smoke-subnetcalc apim-simulator-test chatgpt-sim-test idp-core-test langfuse-demos-test platform-mcp-test sentiment-test shared-apphttp-test shared-appshell-test shared-idpauth-test subnetcalc-test

##@ Workflow
prereqs: ## Check shared app workflow prerequisites without requiring Trivy
	@echo "compose smoke prerequisites are repo-local:"
	@echo "  - docker"
	@echo "  - docker compose, nerdctl compose, colima nerdctl compose, or podman compose"
	@echo "  - biome and deno for checked browser JavaScript"
	@echo ""
	@echo "Trivy remains opt-in. Use 'make trivy-prereqs' when you want scanning."

test: shared-apphttp-test shared-appshell-test shared-idpauth-test ## Run the default app checks
	@$(foreach app,$(APP_TEST_DIRS),$(MAKE) --no-print-directory -C ./$(app) test && ) true

js-check: ## Check dependency-free typed JavaScript contracts for lightweight apps
	@biome check ./shared/web/api-types.d.ts
	@$(MAKE) --no-print-directory -C ./shared/appshell js-check
	@$(MAKE) --no-print-directory -C ./shared/idpauth js-check
	@$(foreach app,$(APP_JS_CHECK_DIRS),$(MAKE) --no-print-directory -C ./$(app) app-js-check && ) true

update: ## Update dependency locks across app roots using native package managers
	@$(foreach app,$(APP_UPDATE_DIRS),$(MAKE) --no-print-directory -C ./$(app) update && ) true

##@ Security
trivy: trivy-scan ## Alias for trivy-scan

trivy-prereqs: ## Check Trivy runner and local prerequisites
	@"$(TRIVY_SCAN_SCRIPT)" --mode prereqs --execute

trivy-scan-fs: ## Scan local apps/ source trees for vulnerabilities, misconfigurations, and secrets
	@"$(TRIVY_SCAN_SCRIPT)" --mode fs --execute

trivy-scan-images: ## Build and scan the canonical workload images used by the Kubernetes demos
	@"$(TRIVY_SCAN_SCRIPT)" --mode images --execute

trivy-scan-gitea: ## Scan the seeded Gitea app repos instead of only local apps/
	@SCAN_GITEA=1 "$(TRIVY_SCAN_SCRIPT)" --mode gitea --execute

trivy-scan: ## Scan local apps/ source trees and the canonical workload images
	@"$(TRIVY_SCAN_SCRIPT)" --mode all --execute

trivy-scan-all: ## Scan local apps/, workload images, and the optional in-cluster Gitea mirrors
	@SCAN_GITEA=1 "$(TRIVY_SCAN_SCRIPT)" --mode all --execute

##@ Smoke
compose-smoke: ## Run the compose smoke checks for app-local stacks
	@$(foreach app,$(APP_COMPOSE_SMOKE_DIRS),$(MAKE) --no-print-directory -C ./$(app) compose-smoke && ) true

compose-smoke-apim-simulator: ## Run the APIM simulator direct public compose smoke check
	@$(MAKE) --no-print-directory -C ./apim-simulator compose-smoke

apim-simulator-test: ## Run the APIM Simulator Go unit tests
	@$(MAKE) --no-print-directory -C ./apim-simulator app-test

chatgpt-sim-test: ## Run the ChatGPT Sim Go unit tests
	@$(MAKE) --no-print-directory -C ./chatgpt-sim app-test

idp-core-test: ## Run the IDP Core Go unit tests
	@$(MAKE) --no-print-directory -C ./idp-core app-test

langfuse-demos-test: ## Run the Langfuse demos Go unit tests
	@$(MAKE) --no-print-directory -C ./langfuse-demos app-test

platform-mcp-test: ## Run the Platform MCP Go unit tests
	@$(MAKE) --no-print-directory -C ./platform-mcp app-test

sentiment-test: ## Run the sentiment Go unit tests
	@$(MAKE) --no-print-directory -C ./sentiment app-test

shared-apphttp-test: ## Run the shared app HTTP Go unit tests
	@$(MAKE) --no-print-directory -C ./shared/apphttp test

shared-appshell-test: ## Run the shared app shell Go unit tests
	@$(MAKE) --no-print-directory -C ./shared/appshell test

shared-idpauth-test: ## Run the shared IDP auth Go unit tests
	@$(MAKE) --no-print-directory -C ./shared/idpauth test

subnetcalc-test: ## Run the subnetcalc Go unit tests
	@$(MAKE) --no-print-directory -C ./subnetcalc app-test

compose-smoke-chatgpt-sim: ## Run the lightweight ChatGPT Sim compose smoke check
	@$(MAKE) --no-print-directory -C ./chatgpt-sim compose-smoke

compose-smoke-idp-core: ## Run the lightweight IDP Core compose smoke check
	@$(MAKE) --no-print-directory -C ./idp-core compose-smoke

compose-smoke-platform-mcp: ## Run the lightweight Platform MCP compose smoke check
	@$(MAKE) --no-print-directory -C ./platform-mcp compose-smoke

compose-smoke-sentiment: ## Run the lightweight sentiment compose smoke check
	@$(MAKE) --no-print-directory -C ./sentiment compose-smoke

compose-smoke-subnetcalc: ## Run the lightweight subnetcalc compose smoke check
	@$(MAKE) --no-print-directory -C ./subnetcalc compose-smoke
