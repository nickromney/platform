SHELL := /bin/bash
USE_COMMON_HELP := 1
MAKE_HELP_WIDTH := 16
MAKE_KNOWN_GOALS := help prereqs build run up exec check-version check-toolchain-surface
MAKE_SUGGEST_SCRIPT := ../scripts/suggest-make-goal.sh

REPO_ROOT := $(abspath $(CURDIR)/..)
DEVCONTAINER_CONFIG := $(REPO_ROOT)/.devcontainer/devcontainer.json
DEVCONTAINER_CLI ?= devcontainer
DOCKER_BIN ?= docker
VSCODE_BIN ?= code
VSCODE_DEVCONTAINERS_EXTENSION ?= ms-vscode-remote.remote-containers
HOST_HOME ?= $(HOME)
HOST_KUBECONFIG_DIR := $(HOST_HOME)/.kube
HOST_PLATFORM_CONFIG_DIR := $(HOST_HOME)/.config/platform-devcontainer
HOST_MKCERT_STAGING_DIR := $(HOST_PLATFORM_CONFIG_DIR)/mkcert
CONTAINER_MARKER_FILE ?= /.dockerenv
CONTAINER_SHELL ?= zsh -l

include ../mk/common.mk

.PHONY: prereqs build run up exec check-version check-toolchain-surface

##@ Setup
prereqs: ## Check Docker, devcontainer CLI, VS Code extension state, and host mount dirs
	@set -euo pipefail; \
	if [ "$${PLATFORM_DEVCONTAINER:-}" = "1" ] && [ -f "$(CONTAINER_MARKER_FILE)" ]; then \
		echo "Already inside the devcontainer; skipping host-side devcontainer prerequisites."; \
		exit 0; \
	fi; \
	ok=1; \
	for tool in "$(DOCKER_BIN)" "$(DEVCONTAINER_CLI)"; do \
		if ! command -v "$$tool" >/dev/null 2>&1; then \
			echo "Missing required tool in PATH: $$tool" >&2; \
			ok=0; \
		fi; \
	done; \
	if ! "$(DOCKER_BIN)" info >/dev/null 2>&1; then \
		echo "Docker daemon is not reachable. Start Docker Desktop or another Docker-compatible daemon." >&2; \
		ok=0; \
	fi; \
	if command -v "$(VSCODE_BIN)" >/dev/null 2>&1; then \
		if ! "$(VSCODE_BIN)" --list-extensions 2>/dev/null | grep -Fxq "$(VSCODE_DEVCONTAINERS_EXTENSION)"; then \
			echo "WARN missing VS Code extension: $(VSCODE_DEVCONTAINERS_EXTENSION)" >&2; \
			echo "WARN install it in VS Code if you want the UI-based Reopen in Container flow." >&2; \
		fi; \
	else \
		echo "WARN $(VSCODE_BIN) not found; skipping the VS Code extension check" >&2; \
	fi; \
	mkdir -p "$(HOST_KUBECONFIG_DIR)" "$(HOST_MKCERT_STAGING_DIR)"; \
	if command -v mkcert >/dev/null 2>&1; then \
		caroot="$$(mkcert -CAROOT 2>/dev/null || true)"; \
		if [ -n "$$caroot" ] && [ -d "$$caroot" ]; then \
			find "$(HOST_MKCERT_STAGING_DIR)" -mindepth 1 -maxdepth 1 -exec rm -rf {} +; \
			cp -R "$$caroot"/. "$(HOST_MKCERT_STAGING_DIR)"/; \
			echo "Synced mkcert CA from $$caroot to $(HOST_MKCERT_STAGING_DIR)"; \
		else \
			echo "WARN mkcert found but CAROOT could not be resolved; leaving $(HOST_MKCERT_STAGING_DIR) as-is" >&2; \
		fi; \
	else \
		echo "WARN mkcert not found; leaving $(HOST_MKCERT_STAGING_DIR) empty" >&2; \
	fi; \
	if [ "$$ok" -ne 1 ]; then \
		exit 1; \
	fi; \
	echo "Devcontainer prerequisites look ready for $(REPO_ROOT)"

##@ Lifecycle
build: prereqs ## Build the devcontainer image with the devcontainer CLI
	@"$(REPO_ROOT)/.devcontainer/host-lifecycle.sh" --action build --execute

run: prereqs ## Create or start the devcontainer without attaching a shell
	@"$(REPO_ROOT)/.devcontainer/host-lifecycle.sh" --action run --execute

up: exec ## Ensure the devcontainer is running, then attach a shell

exec: prereqs ## Ensure the devcontainer is running, then attach a shell
	@"$(REPO_ROOT)/.devcontainer/host-lifecycle.sh" --action exec --execute

check-version: ## Inspect devcontainer tool versions and flag stale workspace images
	@"$(REPO_ROOT)/.devcontainer/check-devcontainer-version.sh" --execute

check-toolchain-surface: ## Validate the devcontainer toolchain surface without loading the workspace image
	@"$(REPO_ROOT)/.devcontainer/check-toolchain-surface.sh" --execute
