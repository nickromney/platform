MAKE_KNOWN_GOALS := help makefiles apps kubernetes sdwan
MAKE_SUGGEST_SCRIPT := scripts/suggest-make-goal.sh

include mk/common.mk

.PHONY: help makefiles apps kubernetes sdwan

help:
	@echo "Platform workspace Makefile guide"
	@echo ""
	@echo "This root Makefile is informational only."
	@echo "Use the focused Makefiles directly with make -C <dir> ..."
	@echo ""
	@echo "Recommended entry points:"
	@echo "  make kubernetes   Show the staged Kubernetes workflows"
	@echo "  make apps         Show the app/frontend entry points"
	@echo "  make sdwan        Show the SD-WAN lab entry points"
	@echo "  make makefiles    List every Makefile in the repo"

makefiles:
	@echo "Makefiles in this repo:"
	@rg --files -g 'Makefile' | sort | sed 's/^/  /'

apps:
	@echo "App Makefiles:"
	@echo "  apps/Makefile"
	@echo "    make -C apps help"
	@echo "    make -C apps trivy-scan"
	@echo "    make -C apps trivy-scan-all"
	@echo "  apps/subnet-calculator/Makefile"
	@echo "    make -C apps/subnet-calculator help"
	@echo "  apps/subnet-calculator/frontend-html-static/Makefile"
	@echo "    make -C apps/subnet-calculator/frontend-html-static help"
	@echo "  apps/subnet-calculator/frontend-python-flask/Makefile"
	@echo "    make -C apps/subnet-calculator/frontend-python-flask help"
	@echo "  apps/subnet-calculator/frontend-react/Makefile"
	@echo "    make -C apps/subnet-calculator/frontend-react help"
	@echo "  apps/subnet-calculator/frontend-typescript-vite/Makefile"
	@echo "    make -C apps/subnet-calculator/frontend-typescript-vite help"

kubernetes:
	@echo "Kubernetes workflows:"
	@echo "  kind"
	@echo "    make -C kubernetes/kind prereqs"
	@echo "    make -C kubernetes/kind 100 apply"
	@echo "    make -C kubernetes/kind 900 apply AUTO_APPROVE=1"
	@echo "  lima"
	@echo "    make -C kubernetes/lima prereqs"
	@echo "    make -C kubernetes/lima 100 apply"
	@echo "    make -C kubernetes/lima 900 apply AUTO_APPROVE=1"
	@echo "  slicer"
	@echo "    make -C kubernetes/slicer prereqs"
	@echo "    make -C kubernetes/slicer 100 apply"
	@echo "    make -C kubernetes/slicer 900 apply AUTO_APPROVE=1"

sdwan:
	@echo "SD-WAN lab workflow:"
	@echo "  make -C sd-wan/lima prereqs"
	@echo "  make -C sd-wan/lima up"
	@echo "  make -C sd-wan/lima show-urls"
	@echo "  make -C sd-wan/lima test"
