SHELL := /bin/bash
MAKE_KNOWN_GOALS := help prereqs init-env test test-ci test-ci-linux test-host-portable status tui build-tui workflow-ui clean-local-state docker-safe-clean hooks lint fmt lint-yaml lint-markdown lint-python lint-bash32 lint-shell lint-shellcheck lint-cilium lint-cilium-live lint-kyverno lint-kyverno-live fmt-markdown fmt-hcl check-version update-versions release release-dry-run release-preview release-tag release-tag-dry-run makefiles apps kubernetes docker sonar-scan
MAKE_SUGGEST_SCRIPT := scripts/suggest-make-goal.sh
MAKEFILE_PATHS_CMD := rg --files -g 'Makefile' | LC_ALL=C sort
APP_ENTRYPOINT_DIRS_CMD := { printf '%s\n' apps; find apps -mindepth 2 -maxdepth 2 -name Makefile -print | xargs -n 1 dirname; } | LC_ALL=C sort
LINT_YAML_SCRIPT ?= scripts/lint-yaml.sh
LINT_MARKDOWN_SCRIPT ?= scripts/lint-markdown.sh
LINT_PYTHON_SCRIPT ?= scripts/lint-python.sh
LINT_BASH32_SCRIPT ?= scripts/check-bash32-compat.sh
AUDIT_SHELL_SCRIPTS_SCRIPT ?= scripts/audit-shell-scripts.sh
LINT_SHELLCHECK_SCRIPT ?= scripts/lint-shellcheck.sh
VALIDATE_CILIUM_POLICIES_SCRIPT ?= scripts/validate-cilium-policies.sh
VALIDATE_KYVERNO_POLICIES_SCRIPT ?= scripts/validate-kyverno-policies.sh
# The linters `make lint` runs, in order. This is the single source of truth:
# the composite recipe is generated from it, so a linter cannot be dropped by
# deleting one line and leaving the rest green. tests/lint-wiring.bats holds it
# to the lint-* targets below and to the scripts/lint-*.sh files on disk.
LINTERS := yaml markdown python bash32 shell shellcheck cilium kyverno
# lint-*-live run the same validators in --mode live against a running cluster,
# so they cannot be part of a composite that has to work on a laptop with
# nothing up. Named here so the wiring gate can tell a deliberate exclusion from
# a linter that quietly fell out of LINTERS.
LINTERS_NOT_IN_COMPOSITE := cilium-live kyverno-live
FMT_MARKDOWN_SCRIPT ?= scripts/fmt-markdown.sh
FMT_HCL_SCRIPT ?= scripts/fmt-hcl.sh
CHECK_VERSION_SCRIPT ?= scripts/check-repo-version.sh
UPDATE_VERSIONS_SCRIPT ?= scripts/update-versions.sh
RELEASE_SCRIPT ?= scripts/release.sh
SONAR_SCAN_SCRIPT ?= scripts/sonar-scan.sh
SONAR_SCAN_REPO ?= $(CURDIR)
RELEASE_TAG_SCRIPT ?= scripts/release_tag.sh
PLATFORM_STATUS_SCRIPT ?= scripts/platform-status.sh
BATS_BIN ?= bats
PLATFORM_TUI_GO_BIN ?= go
PLATFORM_TUI_CMD ?= cd tools/platform-tui && $(PLATFORM_TUI_GO_BIN) run ./cmd/platform-tui --repo-root ../..
PLATFORM_TUI_BUILD_CMD ?= $(MAKE) --no-print-directory -C tools/platform-tui build
PLATFORM_WORKFLOW_UI_SCRIPT ?= scripts/platform-workflow-ui.sh
RESET_LOCAL_STATE_SCRIPT ?= scripts/reset-local-state.sh
INIT_ENV_SCRIPT ?= scripts/init-env.sh
INSTALL_GIT_HOOKS_SCRIPT ?= scripts/hooks/install-lefthook-hooks.sh
STATUS_FORMAT ?= text
WORKFLOW_UI_HOST ?= console.127.0.0.1.sslip.io
WORKFLOW_UI_PORT ?= 8443
WORKFLOW_UI_HTTP ?= h2
CI_UV_CACHE_DIR ?= $(CURDIR)/.run/uv-cache
CHECK_WORKTREE_UNCHANGED ?= scripts/check-worktree-unchanged.sh
CI_RECEIPT_SCRIPT ?= scripts/ci-receipt.sh
RUN_CI_LINUX_SCRIPT ?= scripts/run-ci-linux.sh
RUN_BATS_SUITE ?= scripts/run-bats-suite.sh
# Serial by default, on the evidence rather than by preference.
#
# Three defects were fixed to make parallel viable: a concurrency test asserting
# a wall-clock band while writing to a fixed /tmp path, a retry test with ~1s of
# margin between a 1s timeout and a 2s sleep, and a sort assertion of ours that
# did not expect the run to be split into two batches. Five files that mutate
# state shared with the real repo run in a serial phase in run-bats-suite.sh.
#
# That got it from "six failures, never the same six" to 5 clean runs out of 6.
# The sixth failed two tests in tests/apps-makefile.bats -- a file already in the
# serial phase, which passes alone, and which does not fail when run beside
# either its serial neighbours or the three files added just before it. So the
# residual is load-related and not yet understood.
#
# One flake in six is why this stays off. The whole argument for the serial phase
# was that a gate reporting different failures each run is worth less than a slow
# one that does not; defaulting to auto on 5/6 would contradict it.
#
# Opt in with `make test-ci BATS_JOBS=auto` -- roughly 180-420s against 715s
# serial, varying with what else is on the box. Diagnosing the apps-makefile
# residual is what would let this flip.
BATS_JOBS ?= off
CI_WORKTREE_SNAPSHOT ?= $(CURDIR)/.run/worktree-status
# Tests that depend only on the host toolchain: no cluster, no Docker, no
# network. This is the subset that must also pass on macOS, where the stock awk
# is BSD rather than gawk and the stock bash is 3.2. Everything here either
# stubs its external commands or exercises pure functions.
HOST_PORTABLE_BATS_TESTS := \
	kubernetes/kind/tests/check-policy-drift.bats \
	kubernetes/kind/tests/dependency-audit.bats \
	kubernetes/kind/tests/ensure-node-host-alias.bats \
	kubernetes/kind/tests/install-host-alias-timer.bats \
	tests/check-bash32-compat.bats \
	tests/check-worktree-unchanged.bats \
	tests/locale-independence.bats \
	tests/update-versions.bats

LIST_CI_BATS_TESTS ?= scripts/list-ci-bats-tests.sh
# Discovered from git ls-files '*.bats' minus tests/ci-gate-backlog.txt.
# A new tracked suite is gated automatically; name it in the backlog to keep it out.
CI_BATS_TESTS := $(shell "$(LIST_CI_BATS_TESTS)" --execute)

.DEFAULT_GOAL := default

include mk/common.mk

.PHONY: default help prereqs init-env test test-ci test-ci-linux test-host-portable status tui build-tui workflow-ui clean-local-state docker-safe-clean hooks lint fmt lint-yaml lint-markdown lint-python lint-bash32 lint-shell lint-shellcheck lint-cilium lint-cilium-live lint-kyverno lint-kyverno-live fmt-markdown fmt-hcl check-version update-versions release release-dry-run release-preview release-tag release-tag-dry-run makefiles apps kubernetes docker sonar-scan

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
		'make update-versions\tReport eligible version bumps across tools, charts, packages, providers, and image locks' \
		'make clean-local-state [DRY_RUN=1] [INCLUDE_HOST_CACHES=1] [INCLUDE_KUBECONFIGS=1] [INCLUDE_DOCKER=1]\tPreview or clear repo-generated local state plus optional host caches' \
		'make docker\tShow the Docker/Compose Makefiles' \
		'make docker-safe-clean [AUTO_APPROVE=1]\tPreview or run conservative Docker cleanup that preserves the current kind cluster' \
		'make fmt\tApply repo-level auto-formatters' \
		'make hooks\tInstall lefthook-managed repo hooks' \
		'make init-env\tCreate .env from .env.example and generate any empty local credentials' \
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
		'make status [STATUS_FORMAT=text|json]\tShow root local-runtime status across kind/Lima' \
		'make test\tShow the focused test entrypoints' \
		'make test-ci\tRun the PR-safe hermetic Bats subset' \
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
	@$(APP_ENTRYPOINT_DIRS_CMD) | sed 's#^#  make -C #' | sed 's#$$# prereqs#'
	@echo "  make -C docker/compose prereqs"
	@echo "  make -C sites/docs prereqs"
	@echo "  make -C kubernetes/kind prereqs"
	@echo "  make -C kubernetes/lima prereqs"
	@echo ""
	@echo "Optional root tools:"
	@echo "  go (only for make tui / make build-tui)"

test:
	@echo "Root test is informational."
	@echo ""
	@echo "Run one of:"
	@$(APP_ENTRYPOINT_DIRS_CMD) | sed 's#^#  make -C #' | sed 's#$$# test#'
	@echo "  make -C docker/compose test"
	@echo "  make -C sites/docs test"
	@echo "  make -C kubernetes/kind test"
	@echo "  make -C kubernetes/lima test"

test-host-portable:
	@BATS_BIN="$(BATS_BIN)" BATS_JOBS="$(BATS_JOBS)" "$(RUN_BATS_SUITE)" --execute -- $(HOST_PORTABLE_BATS_TESTS)

test-ci:
	@mkdir -p "$(CI_UV_CACHE_DIR)"
	@"$(CHECK_WORKTREE_UNCHANGED)" --execute --snapshot "$(CI_WORKTREE_SNAPSHOT)"
	@set -euo pipefail; \
	rc=0; \
	UV_CACHE_DIR="$(CI_UV_CACHE_DIR)" BATS_BIN="$(BATS_BIN)" BATS_JOBS="$(BATS_JOBS)" \
		"$(RUN_BATS_SUITE)" --execute -- $(CI_BATS_TESTS) || rc=$$?; \
	if ! "$(CHECK_WORKTREE_UNCHANGED)" --execute --verify "$(CI_WORKTREE_SNAPSHOT)"; then rc=1; fi; \
	if [ "$$rc" -eq 0 ]; then "$(CI_RECEIPT_SCRIPT)" --execute --action stamp; fi; \
	exit $$rc

# The same suite again, in the devcontainer, recorded as "linux" on the same
# receipt. A macOS host cannot see Bash 3.2 vs 5 or BSD vs GNU divergence, and
# GitHub no longer runs on pull_request. Slow, so it is not part of test-ci;
# run it before pushing anything shell- or platform-sensitive, or set
# PLATFORM_GATE_ENVIRONMENTS=host,linux to make pre-push insist on it.
test-ci-linux:
	@"$(RUN_CI_LINUX_SCRIPT)" --execute

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

docker-safe-clean:
	@$(MAKE) --no-print-directory -C kubernetes/kind docker-safe-clean

hooks:
	@"$(INSTALL_GIT_HOOKS_SCRIPT)" --execute
	@echo "Installed lefthook hooks from lefthook.yml"
	@echo "Skip one git command with: LEFTHOOK=0 git <command> or --no-verify"

lint:
	@$(foreach linter,$(LINTERS),$(MAKE) --no-print-directory lint-$(linter) &&) :

fmt:
	@$(MAKE) --no-print-directory fmt-markdown
	@$(MAKE) --no-print-directory lint-yaml
	@$(MAKE) --no-print-directory fmt-hcl

lint-yaml:
	@"$(LINT_YAML_SCRIPT)" --execute

lint-markdown:
	@"$(LINT_MARKDOWN_SCRIPT)" --execute

lint-python:
	@"$(LINT_PYTHON_SCRIPT)" --execute

lint-bash32:
	@/bin/bash "$(LINT_BASH32_SCRIPT)" --execute

lint-shell:
	@"$(AUDIT_SHELL_SCRIPTS_SCRIPT)" --execute

# lint-shell audits conventions; this is the one that runs shellcheck. They
# were the same target in name only until 2026-08-16.
lint-shellcheck:
	@"$(LINT_SHELLCHECK_SCRIPT)" --execute

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

init-env:
	@"$(INIT_ENV_SCRIPT)" --execute

update-versions:
	@"$(UPDATE_VERSIONS_SCRIPT)" --execute

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
