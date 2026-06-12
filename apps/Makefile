USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs test js-check update trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-% %-test shared-apphttp-test shared-appshell-test shared-idpauth-test
MAKE_SUGGEST_SCRIPT := ../scripts/suggest-make-goal.sh

include ../mk/common.mk

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
TRIVY_SCAN_SCRIPT := $(MAKEFILE_DIR)../scripts/trivy-scan-apps.sh
MAKE_KNOWN_GOALS_SCRIPT := $(MAKEFILE_DIR)../scripts/make-known-goals.sh

define app_wrapper_dirs_with_target
$(shell for makefile in ./*/Makefile; do dir="$${makefile%/Makefile}"; goals="$$( "$(MAKE_KNOWN_GOALS_SCRIPT)" --dir "$$dir" --execute 2>/dev/null )"; for goal in $$goals; do [ "$$goal" = "$(1)" ] && { printf '%s\n' "$${dir#./}"; break; }; done; done | LC_ALL=C sort)
endef

APP_COMPOSE_SMOKE_DIRS = $(call app_wrapper_dirs_with_target,compose-smoke)
APP_JS_CHECK_DIRS = $(call app_wrapper_dirs_with_target,app-js-check)
APP_TEST_DIRS = $(call app_wrapper_dirs_with_target,test)
APP_UPDATE_DIRS = $(call app_wrapper_dirs_with_target,update)

.PHONY: prereqs test js-check update trivy trivy-prereqs trivy-scan trivy-scan-fs trivy-scan-images trivy-scan-gitea trivy-scan-all compose-smoke compose-smoke-% %-test shared-apphttp-test shared-appshell-test shared-idpauth-test

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

compose-smoke-%: ## Run an app wrapper compose smoke check
	@app="$*"; \
	case " $(APP_COMPOSE_SMOKE_DIRS) " in \
	  *" $$app "*) $(MAKE) --no-print-directory -C "./$$app" compose-smoke ;; \
	  *) echo "App wrapper '$$app' does not declare compose-smoke." >&2; exit 2 ;; \
	esac

%-test: ## Run an app wrapper unit test workflow
	@app="$*"; \
	case " $(call app_wrapper_dirs_with_target,app-test) " in \
	  *" $$app "*) $(MAKE) --no-print-directory -C "./$$app" app-test ;; \
	  *) echo "App wrapper '$$app' does not declare app-test." >&2; exit 2 ;; \
	esac

shared-apphttp-test: ## Run the shared app HTTP Go unit tests
	@$(MAKE) --no-print-directory -C ./shared/apphttp test

shared-appshell-test: ## Run the shared app shell Go unit tests
	@$(MAKE) --no-print-directory -C ./shared/appshell test

shared-idpauth-test: ## Run the shared IDP auth Go unit tests
	@$(MAKE) --no-print-directory -C ./shared/idpauth test
