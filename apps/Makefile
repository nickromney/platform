USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs test js-check update trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-apim-simulator compose-smoke-chatgpt-sim compose-smoke-idp-core compose-smoke-platform-mcp compose-smoke-sentiment compose-smoke-subnetcalc chatgpt-sim-test idp-core-test platform-mcp-test sentiment-test subnetcalc-test
MAKE_SUGGEST_SCRIPT := ../scripts/suggest-make-goal.sh

include ../mk/common.mk

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TRIVY_SCAN_SCRIPT := $(MAKEFILE_DIR)../scripts/trivy-scan-apps.sh

.PHONY: prereqs test js-check update trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-apim-simulator compose-smoke-chatgpt-sim compose-smoke-idp-core compose-smoke-platform-mcp compose-smoke-sentiment compose-smoke-subnetcalc chatgpt-sim-test idp-core-test platform-mcp-test sentiment-test subnetcalc-test

##@ Workflow
prereqs: ## Check shared app workflow prerequisites without requiring Trivy
	@echo "compose smoke prerequisites are repo-local:"
	@echo "  - docker"
	@echo "  - docker compose, nerdctl compose, colima nerdctl compose, or podman compose"
	@echo "  - biome and deno for checked browser JavaScript"
	@echo ""
	@echo "Trivy remains opt-in. Use 'make trivy-prereqs' when you want scanning."

test: chatgpt-sim-test idp-core-test platform-mcp-test sentiment-test subnetcalc-test js-check ## Run the default app checks
	@$(MAKE) --no-print-directory compose-smoke

js-check: ## Check dependency-free typed JavaScript contracts for lightweight apps
	@$(MAKE) --no-print-directory -C ./chatgpt-sim/app js-check
	@$(MAKE) --no-print-directory -C ./sentiment/app js-check
	@$(MAKE) --no-print-directory -C ./subnetcalc/app js-check

update: ## Update dependency locks across app roots using native package managers
	@$(MAKE) --no-print-directory -C ./apim-simulator update
	@$(MAKE) --no-print-directory -C ./chatgpt-sim update
	@$(MAKE) --no-print-directory -C ./idp-core update
	@$(MAKE) --no-print-directory -C ./platform-mcp update
	@$(MAKE) --no-print-directory -C ./sentiment update
	@$(MAKE) --no-print-directory -C ./subnetcalc update

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
compose-smoke: compose-smoke-apim-simulator compose-smoke-chatgpt-sim compose-smoke-idp-core compose-smoke-platform-mcp compose-smoke-sentiment compose-smoke-subnetcalc ## Run the compose smoke checks for app-local stacks

compose-smoke-apim-simulator: ## Run the APIM simulator direct public compose smoke check
	@set -e; \
	trap '$(MAKE) --no-print-directory -C ./apim-simulator down >/dev/null 2>&1 || true' EXIT; \
	$(MAKE) --no-print-directory -C ./apim-simulator up-hello; \
	$(MAKE) --no-print-directory -C ./apim-simulator smoke-hello SMOKE_HELLO_MODE=anonymous

chatgpt-sim-test: ## Run the ChatGPT Sim Go unit tests
	@$(MAKE) --no-print-directory -C ./chatgpt-sim/app test

idp-core-test: ## Run the IDP Core Go unit tests
	@$(MAKE) --no-print-directory -C ./idp-core/app test

platform-mcp-test: ## Run the Platform MCP Go unit tests
	@$(MAKE) --no-print-directory -C ./platform-mcp/app test

sentiment-test: ## Run the sentiment Go unit tests
	@$(MAKE) --no-print-directory -C ./sentiment/app test

subnetcalc-test: ## Run the subnetcalc Go unit tests
	@$(MAKE) --no-print-directory -C ./subnetcalc/app test

compose-smoke-chatgpt-sim: ## Run the lightweight ChatGPT Sim compose smoke check
	@./chatgpt-sim/tests/compose-smoke.sh --execute

compose-smoke-idp-core: ## Run the lightweight IDP Core compose smoke check
	@./idp-core/tests/compose-smoke.sh --execute

compose-smoke-platform-mcp: ## Run the lightweight Platform MCP compose smoke check
	@./platform-mcp/tests/compose-smoke.sh --execute

compose-smoke-sentiment: ## Run the lightweight sentiment compose smoke check
	@./sentiment/tests/compose-smoke.sh --execute

compose-smoke-subnetcalc: ## Run the lightweight subnetcalc compose smoke check
	@./subnetcalc/tests/compose-smoke.sh --execute
