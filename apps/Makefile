USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs test trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-sentiment compose-smoke-subnetcalc
MAKE_SUGGEST_SCRIPT := ../scripts/suggest-make-goal.sh

include ../mk/common.mk

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TRIVY_SCAN_SCRIPT := $(MAKEFILE_DIR)../scripts/trivy-scan-apps.sh

.PHONY: prereqs test trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-sentiment compose-smoke-subnetcalc

##@ Workflow
prereqs: ## Check shared app workflow prerequisites without requiring Trivy
	@echo "compose smoke prerequisites are repo-local:"
	@echo "  - docker"
	@echo "  - docker compose, nerdctl compose, colima nerdctl compose, or podman compose"
	@echo "  - bun (for frontend test/build workflows)"
	@echo ""
	@echo "Trivy remains opt-in. Use 'make trivy-prereqs' when you want scanning."

test: ## Run the default app smoke checks
	@$(MAKE) --no-print-directory compose-smoke

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
compose-smoke: compose-smoke-sentiment compose-smoke-subnetcalc ## Run the compose smoke checks for both apps

compose-smoke-sentiment: ## Run the lightweight sentiment compose smoke check
	@./sentiment/tests/compose-smoke.sh --execute

compose-smoke-subnetcalc: ## Run the lightweight subnet-calculator compose smoke check
	@./subnet-calculator/tests/compose-smoke.sh --execute
