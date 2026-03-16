USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-sentiment compose-smoke-subnetcalc
MAKE_SUGGEST_SCRIPT := ../scripts/suggest-make-goal.sh

include ../mk/common.mk

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TRIVY_SCAN_SCRIPT := $(MAKEFILE_DIR)../scripts/trivy-scan-apps.sh

.PHONY: trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-sentiment compose-smoke-subnetcalc

##@ Security
trivy: trivy-scan ## Alias for trivy-scan

trivy-prereqs: ## Check Trivy runner and local prerequisites
	@"$(TRIVY_SCAN_SCRIPT)" prereqs

trivy-scan-fs: ## Scan local apps/ source trees for vulnerabilities, misconfigurations, and secrets
	@"$(TRIVY_SCAN_SCRIPT)" fs

trivy-scan-images: ## Build and scan the canonical workload images used by the Kubernetes demos
	@"$(TRIVY_SCAN_SCRIPT)" images

trivy-scan-gitea: ## Scan the seeded Gitea app repos instead of only local apps/
	@SCAN_GITEA=1 "$(TRIVY_SCAN_SCRIPT)" gitea

trivy-scan: ## Scan local apps/ source trees and the canonical workload images
	@"$(TRIVY_SCAN_SCRIPT)" all

trivy-scan-all: ## Scan local apps/, workload images, and the optional in-cluster Gitea mirrors
	@SCAN_GITEA=1 "$(TRIVY_SCAN_SCRIPT)" all

##@ Smoke
compose-smoke: compose-smoke-sentiment compose-smoke-subnetcalc ## Run the compose smoke checks for both apps

compose-smoke-sentiment: ## Run the lightweight sentiment compose smoke check
	@./sentiment/tests/compose-smoke.sh

compose-smoke-subnetcalc: ## Run the lightweight subnet-calculator compose smoke check
	@./subnet-calculator/tests/compose-smoke.sh
