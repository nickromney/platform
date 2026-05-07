MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

.DEFAULT_GOAL ?= help
SHELL ?= /bin/bash

MAKE_HELP_WIDTH ?= 24
MAKE_KNOWN_GOALS ?=
MAKE_SUGGEST_SCRIPT ?=

ifeq ($(USE_COMMON_HELP),1)
.PHONY: help
help:
	@tab=$$(printf '\t'); \
	awk 'BEGIN { FS = ":.*## "; section = "Targets"; count = 0; } \
	function remember_section(name) { \
		if (!(name in seen_section)) { \
			seen_section[name] = ++count; \
		} \
	} \
	/^##@/ { \
		section = substr($$0, 5); \
		remember_section(section); \
		next; \
	} \
	/^[A-Za-z0-9][A-Za-z0-9_.-]*:.*## / { \
		remember_section(section); \
		printf "%s\t%s\t%s\t%s\n", seen_section[section], section, $$1, $$2; \
	}' $(MAKEFILE_LIST) \
	| LC_ALL=C sort -t "$$tab" -k1,1n -k3,3 \
	| awk -F "$$tab" 'BEGIN { width = $(MAKE_HELP_WIDTH); current = "" } \
	{ \
		if ($$2 != current) { \
			if (current != "") { \
				printf "\n"; \
			} \
			current = $$2; \
			print current ":"; \
		} \
		printf "  %-" width "s %s\n", $$3, $$4; \
	}'
endif

.PHONY: check-platform-env-file
check-platform-env-file:
	@set -euo pipefail; \
	env_file="$(strip $(PLATFORM_ENV_FILE))"; \
	template_file="$(strip $(PLATFORM_ENV_TEMPLATE))"; \
	if [ -z "$$env_file" ]; then \
		echo "PLATFORM_ENV_FILE is not set" >&2; \
		exit 1; \
	fi; \
	if [ ! -f "$$env_file" ]; then \
		echo "Missing platform env file: $$env_file" >&2; \
		if [ -n "$$template_file" ] && [ -f "$$template_file" ]; then \
			echo "Copy $$template_file to $$env_file and fill in the required values." >&2; \
		else \
			echo "Create $$env_file before running this target." >&2; \
		fi; \
		exit 1; \
	fi

.PHONY: check-platform-env
check-platform-env: check-platform-env-file
	@set -euo pipefail; \
	required_vars="$(strip $(PLATFORM_REQUIRED_ENV_VARS))"; \
	env_file="$(strip $(PLATFORM_ENV_FILE))"; \
	template_file="$(strip $(PLATFORM_ENV_TEMPLATE))"; \
	if [ -z "$$required_vars" ]; then \
		exit 0; \
	fi; \
	missing=(); \
	for name in $$required_vars; do \
		value="$${!name-}"; \
		if [ -z "$$value" ]; then \
			missing+=("$$name"); \
		fi; \
	done; \
	if [ $${#missing[@]} -gt 0 ]; then \
		echo "Missing required platform secrets in $$env_file: $${missing[*]}" >&2; \
		if [ -n "$$template_file" ] && [ -f "$$template_file" ]; then \
			echo "Use $$template_file as the template." >&2; \
		fi; \
		exit 1; \
	fi

VARIANT_CONTRACT_ID ?= $(STACK_RUNTIME_SCOPE)
VARIANT_CONTRACT_PATH ?= kubernetes/$(VARIANT_CONTRACT_ID)
VARIANT_CONTRACT_REGISTRY_RUNTIME_HOST ?= $(if $(KIND_LOCAL_IMAGE_CACHE_HOST),$(KIND_LOCAL_IMAGE_CACHE_HOST),$(LOCAL_IMAGE_CACHE_HOST))
VARIANT_CONTRACT_REGISTRY_PUSH_HOST ?= $(if $(KIND_LOCAL_IMAGE_CACHE_PUSH_HOST),$(KIND_LOCAL_IMAGE_CACHE_PUSH_HOST),$(LOCAL_IMAGE_CACHE_PUSH_HOST))
VARIANT_CONTRACT_REGISTRY_SCHEME ?= $(if $(LOCAL_IMAGE_CACHE_SCHEME),$(LOCAL_IMAGE_CACHE_SCHEME),http)

.PHONY: variant-contract-print
variant-contract-print:
	@jq -n \
		--arg id "$(VARIANT_CONTRACT_ID)" \
		--arg path "$(VARIANT_CONTRACT_PATH)" \
		--arg state_file "$(abspath $(STATE_FILE))" \
		--arg state_lock_file "$(abspath $(STATE_LOCK_FILE))" \
		--arg kubeconfig_path "$(KUBECONFIG_PATH)" \
		--arg kubeconfig_context "$(KUBECONFIG_CONTEXT)" \
		--arg registry_runtime_host "$(VARIANT_CONTRACT_REGISTRY_RUNTIME_HOST)" \
		--arg registry_push_host "$(VARIANT_CONTRACT_REGISTRY_PUSH_HOST)" \
		--arg registry_scheme "$(VARIANT_CONTRACT_REGISTRY_SCHEME)" \
		'{id: $$id, path: $$path, state: {state_file: $$state_file, state_lock_file: $$state_lock_file}, cluster_access: {kubeconfig_path: $$kubeconfig_path, kubeconfig_context: $$kubeconfig_context}, registry: {runtime_host: $$registry_runtime_host, push_host: $$registry_push_host, scheme: $$registry_scheme}}'

.DEFAULT:
	@set -euo pipefail; \
	echo "Unknown make goal '$@'." >&2; \
	if [ -n "$(strip $(MAKE_SUGGEST_SCRIPT))" ] && [ -x "$(MAKE_SUGGEST_SCRIPT)" ] && [ -n "$(strip $(MAKE_KNOWN_GOALS))" ]; then \
		suggestion="$$( "$(MAKE_SUGGEST_SCRIPT)" --goal "$@" $(foreach goal,$(MAKE_KNOWN_GOALS),--candidate "$(goal)") --execute )"; \
		if [ -n "$$suggestion" ]; then \
			echo "$$suggestion" >&2; \
		fi; \
	fi; \
	echo "Run 'make help' for valid targets." >&2; \
	exit 2
