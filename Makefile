MAKE_KNOWN_GOALS := help prereqs test lint fmt lint-yaml lint-markdown lint-cilium lint-cilium-live lint-kyverno lint-kyverno-live fmt-markdown makefiles apps kubernetes sdwan
MAKE_SUGGEST_SCRIPT := scripts/suggest-make-goal.sh
MAKEFILE_PATHS_CMD := rg --files -g 'Makefile' | LC_ALL=C sort
LINT_YAML_SCRIPT ?= scripts/lint-yaml.sh
LINT_MARKDOWN_SCRIPT ?= scripts/lint-markdown.sh
VALIDATE_CILIUM_POLICIES_SCRIPT ?= scripts/validate-cilium-policies.sh
VALIDATE_KYVERNO_POLICIES_SCRIPT ?= scripts/validate-kyverno-policies.sh
FMT_MARKDOWN_SCRIPT ?= scripts/fmt-markdown.sh

.DEFAULT_GOAL := help

include mk/common.mk

.PHONY: help prereqs test lint fmt lint-yaml lint-markdown lint-cilium lint-cilium-live lint-kyverno lint-kyverno-live fmt-markdown makefiles apps kubernetes sdwan

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
	@echo "  make lint         Run repo-level reporting checks"
	@echo "  make fmt          Apply repo-level auto-formatters"
	@echo "  make lint-cilium-live  Validate deployed Cilium policies via the current kubeconfig"
	@echo "  make lint-kyverno-live  Validate deployed Kyverno policy matches via the current kubeconfig"
	@echo "  make prereqs      Show the focused prerequisite entrypoints"
	@echo "  make test         Show the focused test entrypoints"
	@echo "  make apps         Show the app/frontend Makefiles"
	@echo "  make kubernetes   Show the staged Kubernetes Makefiles"
	@echo "  make makefiles    List every Makefile in the repo"
	@echo "  make sdwan        Show the SD-WAN Makefiles"

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

sdwan:
	@echo "SD-WAN Makefiles:"
	@$(MAKE) --no-print-directory makefiles | sed '1d;/^  sd-wan\//!d'
	@echo ""
	@echo "Common workflow:"
	@echo "  make -C sd-wan/<stack> prereqs"
	@echo "  make -C sd-wan/<stack> up"
	@echo "  make -C sd-wan/<stack> show-urls"
	@echo "  make -C sd-wan/<stack> test"

prereqs:
	@echo "Root prereqs is informational."
	@echo ""
	@echo "Run one of:"
	@echo "  make -C apps prereqs"
	@echo "  make -C apps/sentiment prereqs"
	@echo "  make -C apps/subnet-calculator prereqs"
	@echo "  make -C kubernetes/kind prereqs"
	@echo "  make -C kubernetes/lima prereqs"
	@echo "  make -C kubernetes/slicer prereqs"
	@echo "  make -C sd-wan/lima prereqs"

test:
	@echo "Root test is informational."
	@echo ""
	@echo "Run one of:"
	@echo "  make -C apps test"
	@echo "  make -C apps/sentiment test"
	@echo "  make -C apps/subnet-calculator test"
	@echo "  make -C kubernetes/kind test"
	@echo "  make -C kubernetes/lima test"
	@echo "  make -C kubernetes/slicer test"
	@echo "  make -C sd-wan/lima test"

lint:
	@$(MAKE) --no-print-directory lint-yaml
	@$(MAKE) --no-print-directory lint-markdown
	@$(MAKE) --no-print-directory lint-cilium
	@$(MAKE) --no-print-directory lint-kyverno

fmt:
	@$(MAKE) --no-print-directory fmt-markdown

lint-yaml:
	@"$(LINT_YAML_SCRIPT)"

lint-markdown:
	@"$(LINT_MARKDOWN_SCRIPT)"

lint-cilium:
	@"$(VALIDATE_CILIUM_POLICIES_SCRIPT)" static

lint-cilium-live:
	@"$(VALIDATE_CILIUM_POLICIES_SCRIPT)" live

lint-kyverno:
	@"$(VALIDATE_KYVERNO_POLICIES_SCRIPT)" static

lint-kyverno-live:
	@"$(VALIDATE_KYVERNO_POLICIES_SCRIPT)" live

fmt-markdown:
	@"$(FMT_MARKDOWN_SCRIPT)"
