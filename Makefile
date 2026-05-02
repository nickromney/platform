SHELL := /bin/bash
MAKE_KNOWN_GOALS := help prereqs test status tui build-tui workflow-ui clean-local-state lint fmt lint-yaml lint-markdown lint-bash32 lint-shell lint-cilium lint-cilium-live lint-kyverno lint-kyverno-live fmt-markdown fmt-hcl check-version release release-dry-run release-preview release-tag release-tag-dry-run makefiles apps kubernetes docker sonar-scan
MAKE_SUGGEST_SCRIPT := scripts/suggest-make-goal.sh
MAKEFILE_PATHS_CMD := rg --files -g 'Makefile' | LC_ALL=C sort
LINT_YAML_SCRIPT ?= scripts/lint-yaml.sh
LINT_MARKDOWN_SCRIPT ?= scripts/lint-markdown.sh
LINT_BASH32_SCRIPT ?= scripts/check-bash32-compat.sh
AUDIT_SHELL_SCRIPTS_SCRIPT ?= scripts/audit-shell-scripts.sh
VALIDATE_CILIUM_POLICIES_SCRIPT ?= scripts/validate-cilium-policies.sh
VALIDATE_KYVERNO_POLICIES_SCRIPT ?= scripts/validate-kyverno-policies.sh
FMT_MARKDOWN_SCRIPT ?= scripts/fmt-markdown.sh
FMT_HCL_SCRIPT ?= scripts/fmt-hcl.sh
CHECK_VERSION_SCRIPT ?= scripts/check-repo-version.sh
RELEASE_SCRIPT ?= scripts/release.sh
SONAR_SCAN_SCRIPT ?= scripts/sonar-scan.sh
SONAR_SCAN_REPO ?= $(CURDIR)
RELEASE_TAG_SCRIPT ?= scripts/release_tag.sh
PLATFORM_STATUS_SCRIPT ?= scripts/platform-status.sh
PLATFORM_TUI_GO_BIN ?= go
PLATFORM_TUI_CMD ?= cd tools/platform-tui && $(PLATFORM_TUI_GO_BIN) run ./cmd/platform-tui --repo-root ../..
PLATFORM_TUI_BUILD_CMD ?= $(MAKE) --no-print-directory -C tools/platform-tui build
PLATFORM_WORKFLOW_UI_SCRIPT ?= scripts/platform-workflow-ui.sh
RESET_LOCAL_STATE_SCRIPT ?= scripts/reset-local-state.sh
STATUS_FORMAT ?= text
WORKFLOW_UI_HOST ?= console.127.0.0.1.sslip.io
WORKFLOW_UI_PORT ?= 8443
WORKFLOW_UI_HTTP ?= h2

.DEFAULT_GOAL := default

include mk/common.mk

.PHONY: default help prereqs test status tui build-tui workflow-ui clean-local-state lint fmt lint-yaml lint-markdown lint-bash32 lint-shell lint-cilium lint-cilium-live lint-kyverno lint-kyverno-live fmt-markdown fmt-hcl check-version release release-dry-run release-preview release-tag release-tag-dry-run makefiles apps kubernetes docker sonar-scan

default:
	@$(MAKE) --no-print-directory help

help:
	@echo "Platform workspace Makefile guide"
	@echo ""
	@echo "This root Makefile is primarily informational."
	@echo "Use the focused Makefiles directly with make -C <dir> ... for stack and app workflows."
	@echo ""
	@echo "Focused Makefiles:"
	@$(MAKE) --no-print-directory makefiles | sed '1d;/^  Makefile$$/d'
	@echo ""
	@echo "Root shortcuts:"
	@printf '%b\n' \
		'make apps\tShow the app/frontend Makefiles' \
		'make build-tui\tBuild the optional Bubble Tea platform TUI into tools/platform-tui/bin/' \
		'make check-version\tVerify repo-level dependency/version guardrails' \
		'make clean-local-state [DRY_RUN=1] [INCLUDE_HOST_CACHES=1] [INCLUDE_KUBECONFIGS=1] [INCLUDE_DOCKER=1]\tPreview or clear repo-generated local state plus optional host caches' \
		'make docker\tShow the Docker/Compose Makefiles' \
		'make fmt\tApply repo-level auto-formatters' \
		'make kubernetes\tShow the staged Kubernetes Makefiles' \
		'make lint\tRun repo-level reporting checks' \
		'make lint-bash32\tRun Bash 3.2 shell compatibility checks' \
		'make lint-cilium-live\tValidate deployed Cilium policies via the current kubeconfig' \
		'make lint-kyverno-live\tValidate deployed Kyverno policy matches via the current kubeconfig' \
		'make lint-shell\tRun repo shell audit checks' \
		'make makefiles\tList every Makefile in the repo' \
		'make prereqs\tShow the focused prerequisite entrypoints' \
		'make release VERSION=0.3.0\tBump VERSION, run checks, and create a release commit' \
		'make release-dry-run VERSION=0.3.0\tPreview the release commit flow' \
		'make release-tag VERSION=0.3.0\tCreate an annotated v-version tag from main' \
		'make sonar-scan SONAR_SCAN_REPO=apps/apim-simulator\tRun SonarQube on any local repo' \
		'make status [STATUS_FORMAT=text|json]\tShow root local-runtime status across kind/Lima/Slicer' \
		'make test\tShow the focused test entrypoints' \
		'make tui\tOpen the Bubble Tea local runtime chooser' \
		'make workflow-ui [WORKFLOW_UI_HTTP=h2|http1]\tServe the browser workflow chooser on local HTTPS' \
	| while IFS=$$'\t' read -r command description; do \
		printf '  %-60s %s\n' "$$command" "$$description"; \
	done

makefiles:
	@echo "Makefiles in this repo:"
	@$(MAKEFILE_PATHS_CMD) | sed 's/^/  /'

apps:
	@echo "App Makefiles:"
	@$(MAKE) --no-print-directory makefiles | sed '1d;/^  apps\//!d'
	@echo ""
	@echo "Use any listed path with:"
	@echo "  make -C <dir> help"
	@echo "  make -C <dir> <target>"

kubernetes:
	@echo "Kubernetes workflows:"
	@$(MAKE) --no-print-directory makefiles | sed '1d;/^  kubernetes\//!d'
	@echo ""
	@echo "Common workflow:"
	@echo "  make -C kubernetes/<stack> prereqs"
	@echo "  make -C kubernetes/<stack> 100 apply"
	@echo "  make -C kubernetes/<stack> 900 apply AUTO_APPROVE=1"

docker:
	@echo "Docker/Compose workflows:"
	@$(MAKE) --no-print-directory makefiles | sed '1d;/^  docker\//!d'
	@echo ""
	@echo "Common workflow:"
	@echo "  make -C docker/compose prereqs"
	@echo "  make -C docker/compose up"
	@echo "  make -C docker/compose urls"
	@echo "  make -C docker/compose test"

prereqs:
	@echo "Root prereqs is informational."
	@echo ""
	@echo "Run one of:"
	@echo "  make -C .devcontainer prereqs"
	@echo "  make -C apps prereqs"
	@echo "  make -C apps/apim-simulator prereqs"
	@echo "  make -C apps/sentiment prereqs"
	@echo "  make -C apps/subnetcalc prereqs"
	@echo "  make -C docker/compose prereqs"
	@echo "  make -C sites/docs prereqs"
	@echo "  make -C kubernetes/kind prereqs"
	@echo "  make -C kubernetes/lima prereqs"
	@echo "  make -C kubernetes/slicer prereqs"
	@echo ""
	@echo "Optional root tools:"
	@echo "  go (only for make tui / make build-tui)"

test:
	@echo "Root test is informational."
	@echo ""
	@echo "Run one of:"
	@echo "  make -C apps test"
	@echo "  make -C apps/apim-simulator test"
	@echo "  make -C apps/sentiment test"
	@echo "  make -C apps/subnetcalc test"
	@echo "  make -C docker/compose test"
	@echo "  make -C sites/docs test"
	@echo "  make -C kubernetes/kind test"
	@echo "  make -C kubernetes/lima test"
	@echo "  make -C kubernetes/slicer test"

status:
	@"$(PLATFORM_STATUS_SCRIPT)" --execute --output "$(STATUS_FORMAT)"

tui:
	@if ! command -v "$(PLATFORM_TUI_GO_BIN)" >/dev/null 2>&1; then \
		echo "Go is required for make tui."; \
		echo "Install Go, run make build-tui on a host with Go, or use make status / focused Makefiles directly if you do not want the TUI."; \
		exit 1; \
	fi
	@$(PLATFORM_TUI_CMD) --execute

build-tui:
	@$(PLATFORM_TUI_BUILD_CMD)

workflow-ui:
	@"$(PLATFORM_WORKFLOW_UI_SCRIPT)" --execute --host "$(WORKFLOW_UI_HOST)" --port "$(WORKFLOW_UI_PORT)" --http "$(WORKFLOW_UI_HTTP)"

clean-local-state:
	@"$(RESET_LOCAL_STATE_SCRIPT)" \
		$(if $(filter 1,$(DRY_RUN)),--dry-run,--execute) \
		$(if $(filter 1,$(INCLUDE_HOST_CACHES)),--include-host-caches) \
		$(if $(filter 1,$(INCLUDE_KUBECONFIGS)),--include-kubeconfigs) \
		$(if $(filter 1,$(INCLUDE_DOCKER)),--include-docker) \
		$(if $(filter 1,$(INCLUDE_DOCKER_VOLUMES)),--include-docker-volumes)

lint:
	@$(MAKE) --no-print-directory lint-yaml
	@$(MAKE) --no-print-directory lint-markdown
	@$(MAKE) --no-print-directory lint-bash32
	@$(MAKE) --no-print-directory lint-shell
	@$(MAKE) --no-print-directory lint-cilium
	@$(MAKE) --no-print-directory lint-kyverno

fmt:
	@$(MAKE) --no-print-directory fmt-markdown
	@$(MAKE) --no-print-directory lint-yaml
	@$(MAKE) --no-print-directory fmt-hcl

lint-yaml:
	@"$(LINT_YAML_SCRIPT)" --execute

lint-markdown:
	@"$(LINT_MARKDOWN_SCRIPT)" --execute

lint-bash32:
	@/bin/bash "$(LINT_BASH32_SCRIPT)" --execute

lint-shell:
	@"$(AUDIT_SHELL_SCRIPTS_SCRIPT)" --execute

lint-cilium:
	@"$(VALIDATE_CILIUM_POLICIES_SCRIPT)" --mode static --execute

lint-cilium-live:
	@"$(VALIDATE_CILIUM_POLICIES_SCRIPT)" --mode live --execute

lint-kyverno:
	@"$(VALIDATE_KYVERNO_POLICIES_SCRIPT)" --mode static --execute

lint-kyverno-live:
	@"$(VALIDATE_KYVERNO_POLICIES_SCRIPT)" --mode live --execute

fmt-markdown:
	@"$(FMT_MARKDOWN_SCRIPT)" --execute

fmt-hcl:
	@"$(FMT_HCL_SCRIPT)" --execute

check-version:
	@"$(CHECK_VERSION_SCRIPT)" --execute

sonar-scan:
	@SONAR_SCAN_REPO="$(SONAR_SCAN_REPO)" "$(SONAR_SCAN_SCRIPT)" --execute

release:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release VERSION=0.3.0"; exit 1; }
	@"$(RELEASE_SCRIPT)" --execute "$(VERSION)"

release-dry-run:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-dry-run VERSION=0.3.0"; exit 1; }
	@"$(RELEASE_SCRIPT)" --dry-run "$(VERSION)"

release-preview: release-dry-run

release-tag:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-tag VERSION=0.3.0"; exit 1; }
	@"$(RELEASE_TAG_SCRIPT)" --execute "$(VERSION)"

release-tag-dry-run:
	@[ -n "$(VERSION)" ] || { echo "VERSION is required, e.g. make release-tag-dry-run VERSION=0.3.0"; exit 1; }
	@"$(RELEASE_TAG_SCRIPT)" --dry-run "$(VERSION)"
