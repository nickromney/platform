MAKE_KNOWN_GOALS := help makefiles apps kubernetes sdwan
MAKE_SUGGEST_SCRIPT := scripts/suggest-make-goal.sh
MAKEFILE_PATHS_CMD := rg --files -g 'Makefile' | LC_ALL=C sort

include mk/common.mk

.PHONY: help makefiles apps kubernetes sdwan

help:
	@echo "Platform workspace Makefile guide"
	@echo ""
	@echo "This root Makefile is informational only."
	@echo "Use the focused Makefiles directly with make -C <dir> ..."
	@echo ""
	@echo "Focused Makefiles:"
	@$(MAKE) --no-print-directory makefiles | sed '1d;/^  Makefile$$/d'
	@echo ""
	@echo "Root shortcuts:"
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
