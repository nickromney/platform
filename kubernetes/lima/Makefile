.DEFAULT_GOAL := help
SHELL := /bin/bash

TG ?= terragrunt
TG_LOG_SHOW_ABS_PATHS ?= true
TG_INIT_FLAGS ?= -reconfigure
STACK_DIR := ../../terraform/kubernetes
STATE_FILE ?= ../../terraform/.run/kubernetes-lima/terraform.tfstate
TG_STATE_PATH ?= $(abspath $(STATE_FILE))
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(MAKEFILE_DIR)../..)
PROFILE_LIB := $(STACK_DIR)/scripts/profile-lib.sh
MAKE_SUGGEST_SCRIPT := $(MAKEFILE_DIR)../../scripts/suggest-make-goal.sh
SCRIPTS_DIR := $(MAKEFILE_DIR)scripts
CHECK_STAGE_MONOTONICITY := $(SCRIPTS_DIR)/check-stage-monotonicity.sh
CHECK_KIND_STOPPED := $(MAKEFILE_DIR)../scripts/check-kind-stopped.sh
CHECK_SLICER_STOPPED := $(MAKEFILE_DIR)../scripts/check-slicer-stopped.sh
STOP_PLATFORM_RUNTIMES := $(MAKEFILE_DIR)../scripts/stop-platform-runtimes.sh
RESOLVE_TFVAR_VALUE := $(MAKEFILE_DIR)../scripts/resolve-tfvar-value.sh
BUILD_LOCAL_PLATFORM_IMAGES := $(MAKEFILE_DIR)../kind/scripts/build-local-platform-images.sh
HOST_GATEWAY_PROXY := $(SCRIPTS_DIR)/host-gateway-proxy.sh
CONFIGURE_K3S_APISERVER_OIDC := $(SCRIPTS_DIR)/configure-k3s-apiserver-oidc.sh
KUBECONFIG_HELPER := $(STACK_DIR)/scripts/manage-kubeconfig.sh
AUTO_APPROVE ?= 0
DRY_RUN ?= 0
STAGE ?= 100
DEFAULT_KUBECONFIG_PATH ?= $(HOME)/.kube/config
MERGE_KUBECONFIG_TO_DEFAULT ?= 0
DESIRED_NODES ?= 1
LIMA_INSTANCE_PREFIX ?= k3s-node
LIMA_VM_USER ?= $(USER)
LIMA_CONFIG ?= $(MAKEFILE_DIR)config/lima-k3s-node.yaml
LIMA_HOST_GATEWAY_PROXY_MODE ?= auto
K3SUP_CONTEXT ?= limavm-k3s
KUBECONFIG_PATH ?= $(HOME)/.kube/$(K3SUP_CONTEXT).yaml
KUBECONFIG_CONTEXT ?= $(K3SUP_CONTEXT)
K3S_VERSION ?= v1.35.1+k3s1
K3S_CHANNEL ?= stable
K3S_SERVER_EXTRA_ARGS ?= --flannel-backend=none --disable-network-policy --disable=traefik --disable=servicelb
K3S_AGENT_EXTRA_ARGS ?=
LOCAL_IMAGE_CACHE_HOST ?= host.lima.internal:5002
LOCAL_IMAGE_CACHE_PUSH_HOST ?= 127.0.0.1:5002
LOCAL_IMAGE_CACHE_SCHEME ?= http
LOCAL_IMAGE_CACHE_OPTIONAL ?= 1
PLATFORM_PROFILE_MODE ?= off
PLATFORM_PROFILE_DIR ?= $(REPO_ROOT)/.run/profiles
PLATFORM_PROFILE_RUN_ID ?=
PLATFORM_PROFILE_CAPTURE_DOCKER ?= auto
PLATFORM_PROFILE_CAPTURE_KUBECTL ?= auto
PLATFORM_PROFILE_KEEP_SUCCESS ?= 1
PLATFORM_PROFILE_ENABLE_PLUGIN_CACHE ?= 0
PLATFORM_PROFILE_PLUGIN_CACHE_DIR ?= $(REPO_ROOT)/.run/tofu-plugin-cache
PLATFORM_LOCAL_IMAGE_CACHE_MODE ?= auto
PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE ?= auto
PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE ?= auto
GITEA_REGISTRY_HOST ?= localhost:30090
GITEA_REGISTRY_SCHEME ?= http
LIMA_CHECK_SLICER_VM_NAME ?= slicer-1
LIMA_CHECK_SLICER_SOCKET ?= $(HOME)/slicer-mac/slicer.sock
WORKLOAD_IMAGE_NAMESPACE ?= platform
WORKLOAD_IMAGE_TAG ?= latest
EXPECT_SENTIMENT_REPO ?= 0
EXPECT_SUBNETCALC_REPO ?= 0
EXPECT_ACTIONS_RUNS ?= 0
EXPECT_NAMESPACE_SSO ?= 0
EXPECT_NAMESPACE_OBSERVABILITY ?= 0
EXPECT_NAMESPACE_PLATFORM_GATEWAY ?= 0
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
PLATFORM_ADMIN_PASSWORD ?=
PLATFORM_DEMO_PASSWORD ?=
PLATFORM_REQUIRED_ENV_VARS := PLATFORM_ADMIN_PASSWORD PLATFORM_DEMO_PASSWORD
DISPLAY_DEFAULT_KUBECONFIG_PATH := $(patsubst $(HOME)/%,~/%,$(DEFAULT_KUBECONFIG_PATH))
DISPLAY_KUBECONFIG_PATH := $(patsubst $(HOME)/%,~/%,$(KUBECONFIG_PATH))
DISPLAY_PLATFORM_PROFILE_DIR := $(patsubst $(HOME)/%,~/%,$(patsubst $(REPO_ROOT)/%,<repo>/%,$(PLATFORM_PROFILE_DIR)))
ifneq ($(strip $(wildcard $(PLATFORM_ENV_FILE))),)
include $(PLATFORM_ENV_FILE)
endif

VALID_STAGES := 100 200 300 400 500 600 700 800 900
VALID_ACTIONS := plan apply
VALID_STAGE_HELPERS := check-health check-security
VALID_HELPER_MODES := auto on off
MAKE_KNOWN_GOALS := help prepare-state check-stage-monotonicity check-docker-daemon check-kubeconfig check-kind-stopped check-slicer-stopped check-conflicting-clusters-stopped check-platform-env-file prereqs lima-vms-up start bootstrap-k3s merge-default-kubeconfig sync-image-cache build-workload-images status stop-lima stop ensure-host-gateway-proxy stop-host-gateway-proxy proxy-status configure-k3s-apiserver-oidc init plan apply check-health check-security check-gateway-stack check-cluster check-gateway-urls check-app check-sso check-sso-e2e gitea-sync launchpad-render show-urls reset env test test-shell test-bats test-unit check-version check-provider-version $(VALID_ACTIONS) $(VALID_STAGES)

include ../../mk/common.mk
include ../../mk/stage-workflow.mk

export KUBECONFIG_PATH
export KUBECONFIG_CONTEXT
export DEFAULT_KUBECONFIG_PATH
export MERGE_KUBECONFIG_TO_DEFAULT
export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE
export PLATFORM_ADMIN_PASSWORD
export PLATFORM_DEMO_PASSWORD
export PLATFORM_PROFILE_MODE
export PLATFORM_PROFILE_DIR
export PLATFORM_PROFILE_RUN_ID
export PLATFORM_PROFILE_CAPTURE_DOCKER
export PLATFORM_PROFILE_CAPTURE_KUBECTL
export PLATFORM_PROFILE_KEEP_SUCCESS
export PLATFORM_PROFILE_ENABLE_PLUGIN_CACHE
export PLATFORM_PROFILE_PLUGIN_CACHE_DIR
export TF_VAR_gitea_admin_pwd ?= $(PLATFORM_ADMIN_PASSWORD)
export TF_VAR_gitea_member_user_pwd ?= $(PLATFORM_DEMO_PASSWORD)

ifeq ($(filter $(LIMA_HOST_GATEWAY_PROXY_MODE),$(VALID_HELPER_MODES)),)
$(error Invalid LIMA_HOST_GATEWAY_PROXY_MODE="$(LIMA_HOST_GATEWAY_PROXY_MODE)". Expected one of: $(VALID_HELPER_MODES))
endif
ifeq ($(filter $(MERGE_KUBECONFIG_TO_DEFAULT),0 1),)
$(error Invalid MERGE_KUBECONFIG_TO_DEFAULT="$(MERGE_KUBECONFIG_TO_DEFAULT)". Expected one of: 0 1)
endif
ifeq ($(filter $(PLATFORM_LOCAL_IMAGE_CACHE_MODE),$(VALID_HELPER_MODES)),)
$(error Invalid PLATFORM_LOCAL_IMAGE_CACHE_MODE="$(PLATFORM_LOCAL_IMAGE_CACHE_MODE)". Expected one of: $(VALID_HELPER_MODES))
endif
ifeq ($(filter $(PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE),$(VALID_HELPER_MODES)),)
$(error Invalid PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE="$(PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE)". Expected one of: $(VALID_HELPER_MODES))
endif
ifeq ($(filter $(PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE),$(VALID_HELPER_MODES)),)
$(error Invalid PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE="$(PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE)". Expected one of: $(VALID_HELPER_MODES))
endif

STAGE_FILE_100 := stages/100-cluster.tfvars
STAGE_FILE_200 := stages/200-cilium.tfvars
STAGE_FILE_300 := stages/300-hubble.tfvars
STAGE_FILE_400 := stages/400-argocd.tfvars
STAGE_FILE_500 := stages/500-gitea.tfvars
STAGE_FILE_600 := stages/600-policies.tfvars
STAGE_FILE_700 := stages/700-app-repos.tfvars
STAGE_FILE_800 := stages/800-gateway-tls.tfvars
STAGE_FILE_900 := stages/900-sso.tfvars

stage_file = $(STAGE_FILE_$(STAGE))
target_profile_file = targets/lima.tfvars
stage_var_file = $(abspath $(stage_file))
target_var_file = $(abspath $(target_profile_file))
preload_images_file = $(abspath $(MAKEFILE_DIR)preload-images.txt)

.PHONY: help
help:
	@echo "lima demo (Lima VM + k3s + shared Terraform platform stack)"
	@echo ""
	@echo "Workflow syntax:"
	@echo "  make 100 apply"
	@echo "  make 900 plan"
	@echo "  make 900 apply AUTO_APPROVE=1"
	@echo ""
	@echo "Accepted variants:"
	@echo "  make apply 100"
	@echo "  make 900 check-security"
	@echo ""
	@echo "Targets:"
	@echo "  make apply        100|200|300|...|900 [AUTO_APPROVE=1]"
	@echo "  make bootstrap-k3s"
	@echo "  make build-workload-images"
	@echo "  make build-local-platform-images"
	@echo "  make check-app    APP=signoz [APP_PATH=/metrics-explorer/summary] [EXTENDED=1]"
	@echo "  make check-cluster"
	@echo "  make check-gateway-stack"
	@echo "  make check-gateway-urls"
	@echo "  make check-health"
	@echo "  make check-kind-stopped"
	@echo "  make check-slicer-stopped"
	@echo "  make check-provider-version"
	@echo "  make check-security"
	@echo "  make check-sso"
	@echo "  make check-sso-e2e"
	@echo "  make check-stage-monotonicity"
	@echo "  make check-version"
	@echo "  make configure-k3s-apiserver-oidc"
	@echo "  make ensure-host-gateway-proxy"
	@echo "  make env"
	@echo "  make gitea-sync                               Sync apps/ + cluster-policies/ into the Gitea policies repo"
	@echo "  make init"
	@echo "  make launchpad-render                         Regenerate Grafana launchpad dashboard from inventory"
	@echo "  make lima-vms-up"
	@echo "  make merge-default-kubeconfig"
	@echo "  make plan         100|200|300|...|900"
	@echo "  make prereqs"
	@echo "  make proxy-status"
	@echo "  make reset        [AUTO_APPROVE=1]"
	@echo "  make show-urls"
	@echo "  make status"
	@echo "  make stop                                    Alias for stop-lima"
	@echo "  make stop-lima"
	@echo "  make stop-host-gateway-proxy"
	@echo "  make sync-image-cache"
	@echo "  make test"
	@echo ""
	@echo "Stages:"
	@echo "  100 - bootstrap k3s on Lima"
	@echo "  200 - cilium"
	@echo "  300 - hubble"
	@echo "  400 - argocd core"
	@echo "  500 - gitea"
	@echo "  600 - policies"
	@echo "  700 - app workloads from local images"
	@echo "  800 - gateway tls + observability"
	@echo "  900 - sso"
	@echo ""
	@echo "Stage examples:"
	@echo "  make 100 plan"
	@echo "  make 900 apply AUTO_APPROVE=1"
	@echo "  make 900 check-security"
	@echo ""
	@echo "Default kubeconfigs:"
	@echo "  lima -> $(DISPLAY_KUBECONFIG_PATH) (split by default; merge explicitly into $(DISPLAY_DEFAULT_KUBECONFIG_PATH) if needed)"
	@echo ""
	@echo "Aliases:"
	@echo "  make start                                   Alias for lima-vms-up"
	@echo ""
	@echo "Local helper modes:"
	@echo "  LIMA_HOST_GATEWAY_PROXY_MODE=auto|on|off             -> manage host gateway proxies for localhost-backed flows (default: auto)"
	@echo "  MERGE_KUBECONFIG_TO_DEFAULT=1                        -> also merge $(DISPLAY_KUBECONFIG_PATH) into $(DISPLAY_DEFAULT_KUBECONFIG_PATH) (default: 0)"
	@echo "  PLATFORM_LOCAL_IMAGE_CACHE_MODE=auto|on|off          -> manage/sync the host registry cache (default: auto, stage>=700)"
	@echo "  PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE=auto|on|off -> build/push platform shortcut images to the cache (default: auto, stage>=800 when enabled)"
	@echo "  PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=auto|on|off -> build/push app workload images to the cache (default: auto, stage>=700)"
	@echo "  PLATFORM_PROFILE_MODE=off|on|trace                   -> capture apply/plan timings and logs under $(DISPLAY_PLATFORM_PROFILE_DIR)"

.PHONY: check-stage-monotonicity
check-stage-monotonicity:
	@"$(CHECK_STAGE_MONOTONICITY)"

.PHONY: prepare-state
prepare-state:
	@mkdir -p "$(dir $(STATE_FILE))"

.PHONY: check-kubeconfig
check-kubeconfig:
	@set -euo pipefail; \
	default_kubeconfig="$(DEFAULT_KUBECONFIG_PATH)"; \
	"$(KUBECONFIG_HELPER)" ensure-valid "$$default_kubeconfig"; \
	default_count=$$("$(KUBECONFIG_HELPER)" count-contexts "$$default_kubeconfig"); \
	default_current=$$(kubectl --kubeconfig "$$default_kubeconfig" config current-context 2>/dev/null || true); \
	[ -n "$$default_current" ] || default_current="<none>"; \
	echo "OK   default kubeconfig: $$default_kubeconfig ($$default_count context(s), current=$$default_current)"; \
	"$(KUBECONFIG_HELPER)" ensure-valid "$(KUBECONFIG_PATH)"; \
	lima_count=$$("$(KUBECONFIG_HELPER)" count-contexts "$(KUBECONFIG_PATH)"); \
	lima_current=$$(kubectl --kubeconfig "$(KUBECONFIG_PATH)" config current-context 2>/dev/null || true); \
	[ -n "$$lima_current" ] || lima_current="<none>"; \
	echo "OK   lima kubeconfig: $(KUBECONFIG_PATH) ($$lima_count context(s), current=$$lima_current)"; \
	kubie_lint_output="$$("$(KUBECONFIG_HELPER)" lint || true)"; \
	if [ -n "$$kubie_lint_output" ]; then \
		echo "WARN kubie lint:"; \
		printf '%s\n' "$$kubie_lint_output" | sed 's/^/  /'; \
	elif command -v kubie >/dev/null 2>&1; then \
		echo "OK   kubie lint"; \
	fi

.PHONY: check-kind-stopped
check-kind-stopped:
	@"$(CHECK_KIND_STOPPED)"

.PHONY: check-slicer-stopped
check-slicer-stopped:
	@SLICER_URL="$(LIMA_CHECK_SLICER_SOCKET)" SLICER_SOCKET="$(LIMA_CHECK_SLICER_SOCKET)" SLICER_VM_NAME="$(LIMA_CHECK_SLICER_VM_NAME)" "$(CHECK_SLICER_STOPPED)"

.PHONY: check-conflicting-clusters-stopped
check-conflicting-clusters-stopped:
	@$(MAKE) check-kind-stopped
	@$(MAKE) check-slicer-stopped

.PHONY: prereqs
prereqs:
	@set -euo pipefail; \
	stage_num=$$((10#$(STAGE))); \
	required=(curl docker git jq k3sup kubectl limactl terragrunt tofu yq); \
	optional=(bats bun cilium helm k3sup-pro kubectx kubie kyverno mkcert node npm npx shellcheck yamllint); \
	recommended_test_tools=(bun node npm npx); \
	if [ "$$stage_num" -ge 900 ]; then \
		required+=("$${recommended_test_tools[@]}"); \
	fi; \
	missing_required=(); \
	missing_recommended=(); \
	is_required() { \
		local target="$$1"; \
		local req=""; \
		for req in "$${required[@]}"; do \
			if [ "$$req" = "$$target" ]; then \
				return 0; \
			fi; \
		done; \
		return 1; \
	}; \
	is_recommended() { \
		local target="$$1"; \
		local recommended=""; \
		for recommended in "$${recommended_test_tools[@]}"; do \
			if [ "$$recommended" = "$$target" ]; then \
				return 0; \
			fi; \
		done; \
		return 1; \
	}; \
	echo "Tool installation verification:"; \
	check_bin() { \
		local bin="$$1"; local required_flag="$$2"; \
		if command -v "$$bin" >/dev/null 2>&1; then \
			echo "OK   $$bin"; \
			return 0; \
		fi; \
		if [ "$$required_flag" = "1" ]; then \
			echo "FAIL $$bin (missing)"; \
			missing_required+=("$$bin"); \
		else \
			echo "WARN $$bin (missing, optional)"; \
			if is_recommended "$$bin"; then \
				missing_recommended+=("$$bin"); \
			fi; \
		fi; \
	}; \
	sorted_tools=($$(printf '%s\n' "$${required[@]}" "$${optional[@]}" | LC_ALL=C sort -u)); \
	for b in "$${sorted_tools[@]}"; do \
		if is_required "$$b"; then \
			check_bin "$$b" 1; \
		else \
			check_bin "$$b" 0; \
		fi; \
	done; \
	if [ $${#missing_required[@]} -gt 0 ]; then \
		echo ""; \
		echo "Missing required tools: $${missing_required[*]}"; \
		echo ""; \
		echo "Install hints:"; \
		"$(REPO_ROOT)/scripts/install-tool-hints.sh" --plain "$${missing_required[@]}" | sed 's/^/  /'; \
		exit 1; \
	fi; \
	if [ $${#missing_recommended[@]} -gt 0 ]; then \
		echo ""; \
		echo "Recommended browser/E2E test tools missing for stages below 900: $${missing_recommended[*]}"; \
		echo ""; \
		echo "Install hints:"; \
		"$(REPO_ROOT)/scripts/install-tool-hints.sh" --plain "$${missing_recommended[@]}" | sed 's/^/  /'; \
	fi; \
	echo ""; \
	echo "Docker daemon verification:"; \
	if ! docker info >/dev/null 2>&1; then \
		echo "FAIL docker daemon not reachable (is Docker Desktop running?)"; \
		exit 1; \
	fi; \
	echo "OK   Docker context: $$(docker context show)"; \
	echo ""; \
	$(MAKE) check-conflicting-clusters-stopped; \
	echo ""; \
	echo "Versions:"; \
	docker version --format 'client={{.Client.Version}} server={{.Server.Version}}' 2>/dev/null || true; \
	limactl --version 2>/dev/null || true; \
	k3sup version 2>/dev/null || true; \
	kubectl version --client --output=yaml 2>/dev/null | sed -n '1,12p' || true; \
	tofu -version 2>/dev/null | head -n 1 || true; \
	terragrunt --version 2>/dev/null || true; \
	if command -v k3sup-pro >/dev/null 2>&1; then \
		k3sup-pro version 2>/dev/null || true; \
	fi; \
	echo ""; \
	if [ "$$stage_num" -ge 500 ]; then \
		$(MAKE) check-platform-env; \
		echo ""; \
	fi; \
	$(MAKE) check-kubeconfig

.PHONY: lima-vms-up
lima-vms-up:
	@$(MAKE) check-conflicting-clusters-stopped
	@LIMA_INSTANCE_PREFIX="$(LIMA_INSTANCE_PREFIX)" \
	DESIRED_NODES="$(DESIRED_NODES)" \
	LIMA_CONFIG="$(LIMA_CONFIG)" \
	"$(SCRIPTS_DIR)/ensure-k3s-lima-vms.sh"

.PHONY: bootstrap-k3s
bootstrap-k3s:
	@LIMA_INSTANCE_PREFIX="$(LIMA_INSTANCE_PREFIX)" \
	DESIRED_NODES="$(DESIRED_NODES)" \
	LIMA_VM_USER="$(LIMA_VM_USER)" \
	K3SUP_CONTEXT="$(K3SUP_CONTEXT)" \
	KUBECONFIG_PATH="$(KUBECONFIG_PATH)" \
	DEFAULT_KUBECONFIG_PATH="$(DEFAULT_KUBECONFIG_PATH)" \
	K3S_VERSION="$(K3S_VERSION)" \
	K3S_CHANNEL="$(K3S_CHANNEL)" \
	K3S_SERVER_EXTRA_ARGS="$(K3S_SERVER_EXTRA_ARGS)" \
	K3S_AGENT_EXTRA_ARGS="$(K3S_AGENT_EXTRA_ARGS)" \
	KUBECONFIG_HELPER="$(KUBECONFIG_HELPER)" \
	MERGE_KUBECONFIG_TO_DEFAULT="$(MERGE_KUBECONFIG_TO_DEFAULT)" \
	IMAGE_LIST_FILE="$(preload_images_file)" \
	LOCAL_IMAGE_CACHE_HOST="$(LOCAL_IMAGE_CACHE_HOST)" \
	LOCAL_IMAGE_CACHE_SCHEME="$(LOCAL_IMAGE_CACHE_SCHEME)" \
	GITEA_REGISTRY_HOST="$(GITEA_REGISTRY_HOST)" \
	GITEA_REGISTRY_SCHEME="$(GITEA_REGISTRY_SCHEME)" \
	"$(SCRIPTS_DIR)/bootstrap-k3s-lima.sh"

.PHONY: merge-default-kubeconfig
merge-default-kubeconfig:
	@set -euo pipefail; \
	"$(KUBECONFIG_HELPER)" ensure-valid "$(KUBECONFIG_PATH)"; \
	"$(KUBECONFIG_HELPER)" ensure-valid "$(DEFAULT_KUBECONFIG_PATH)"; \
	"$(KUBECONFIG_HELPER)" merge "$(KUBECONFIG_PATH)" "$(DEFAULT_KUBECONFIG_PATH)" "$(K3SUP_CONTEXT)"; \
	echo "OK   merged $(K3SUP_CONTEXT) into $(DEFAULT_KUBECONFIG_PATH)"

.PHONY: sync-image-cache
sync-image-cache:
	@set -euo pipefail; \
	tfvar_files=(); \
	if [ -f "$(stage_var_file)" ]; then tfvar_files+=("$(stage_var_file)"); fi; \
	if [ -f "$(target_var_file)" ]; then tfvar_files+=("$(target_var_file)"); fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_BASE_TFVARS}"); fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_TFVARS}"); fi; \
	IMAGE_LIST_FILE="$(preload_images_file)" \
	CACHE_PUSH_HOST="$(LOCAL_IMAGE_CACHE_PUSH_HOST)" \
	OPTIONAL="$(LOCAL_IMAGE_CACHE_OPTIONAL)" \
	LOCAL_IMAGE_CACHE_HOST="$(LOCAL_IMAGE_CACHE_HOST)" \
	PRELOAD_ENABLE_SIGNOZ="$$( "$(RESOLVE_TFVAR_VALUE)" enable_signoz false "$${tfvar_files[@]}" )" \
	PRELOAD_ENABLE_PROMETHEUS="$$( "$(RESOLVE_TFVAR_VALUE)" enable_prometheus false "$${tfvar_files[@]}" )" \
	PRELOAD_ENABLE_GRAFANA="$$( "$(RESOLVE_TFVAR_VALUE)" enable_grafana false "$${tfvar_files[@]}" )" \
	PRELOAD_ENABLE_LOKI="$$( "$(RESOLVE_TFVAR_VALUE)" enable_loki false "$${tfvar_files[@]}" )" \
	PRELOAD_ENABLE_VICTORIA_LOGS="$$( "$(RESOLVE_TFVAR_VALUE)" enable_victoria_logs false "$${tfvar_files[@]}" )" \
	PRELOAD_ENABLE_TEMPO="$$( "$(RESOLVE_TFVAR_VALUE)" enable_tempo false "$${tfvar_files[@]}" )" \
	PRELOAD_ENABLE_HEADLAMP="$$( "$(RESOLVE_TFVAR_VALUE)" enable_headlamp false "$${tfvar_files[@]}" )" \
	PRELOAD_ENABLE_SSO="$$( "$(RESOLVE_TFVAR_VALUE)" enable_sso false "$${tfvar_files[@]}" )" \
	PRELOAD_ENABLE_ACTIONS_RUNNER="$$( "$(RESOLVE_TFVAR_VALUE)" enable_actions_runner false "$${tfvar_files[@]}" )" \
	"$(SCRIPTS_DIR)/sync-local-image-cache.sh"

.PHONY: check-docker-daemon
check-docker-daemon:
	@set -euo pipefail; \
	command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH"; exit 1; }; \
	if ! docker info >/dev/null 2>&1; then \
		echo "docker daemon not reachable (is Docker Desktop running?)"; \
		exit 1; \
	fi

.PHONY: build-workload-images
build-workload-images:
	@CACHE_PUSH_HOST="$(LOCAL_IMAGE_CACHE_PUSH_HOST)" \
	IMAGE_NAMESPACE="$(WORKLOAD_IMAGE_NAMESPACE)" \
	TAG="$(WORKLOAD_IMAGE_TAG)" \
	"$(SCRIPTS_DIR)/build-local-workload-images.sh"

.PHONY: build-local-platform-images
build-local-platform-images:
	@CACHE_PUSH_HOST="$(LOCAL_IMAGE_CACHE_PUSH_HOST)" \
	"$(BUILD_LOCAL_PLATFORM_IMAGES)"

.PHONY: status
status:
	@set -euo pipefail; \
	echo "=== Lima VM status ==="; \
	if command -v limactl >/dev/null 2>&1; then \
		limactl list 2>/dev/null | awk -v prefix="$(LIMA_INSTANCE_PREFIX)-" 'NR==1 || index($$1, prefix) == 1 { print }'; \
	else \
		echo "limactl not found in PATH"; \
	fi; \
	if [ -f "$(KUBECONFIG_PATH)" ]; then \
		echo ""; \
		echo "=== k3s nodes ==="; \
		KUBECONFIG="$(KUBECONFIG_PATH)" kubectl get nodes -o wide 2>/dev/null || true; \
	fi; \
	if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		echo ""; \
		echo "=== Host gateway proxies ==="; \
		"$(HOST_GATEWAY_PROXY)" status || true; \
	fi
	@echo ""
	@echo "=== Helper modes ==="
	@echo "Host gateway proxy: $(LIMA_HOST_GATEWAY_PROXY_MODE)"
	@echo "Local image cache: $(PLATFORM_LOCAL_IMAGE_CACHE_MODE)"
	@echo "Build workload images: $(PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE)"

.PHONY: stop-lima
stop-lima:
	@set -euo pipefail; \
	command -v limactl >/dev/null 2>&1 || { echo "limactl not found in PATH"; exit 1; }; \
	echo "Stopping host gateway proxy containers (best-effort)..."; \
	$(MAKE) stop-host-gateway-proxy >/dev/null 2>&1 || true; \
	echo "OK   proxies stopped"; \
	vm_names="$$(limactl list -q 2>/dev/null | grep -E '^$(LIMA_INSTANCE_PREFIX)-[0-9]+$$' || true)"; \
	if [ -z "$$vm_names" ]; then \
		echo "No Lima VMs matching $(LIMA_INSTANCE_PREFIX)-* found."; \
		exit 0; \
	fi; \
	stopped=0; \
	while IFS= read -r vm; do \
		[ -n "$$vm" ] || continue; \
		status="$$(limactl list 2>/dev/null | awk -v name="$$vm" '$$1 == name { print $$2; exit }')"; \
		if [ "$$status" = "Running" ]; then \
			echo "Stopping $$vm..."; \
			limactl stop "$$vm" >/dev/null; \
			stopped=$$((stopped + 1)); \
		else \
			echo "Skipping $$vm ($${status:-unknown})"; \
		fi; \
	done <<< "$$vm_names"; \
	if [ "$$stopped" -eq 0 ]; then \
		echo "No running Lima VMs matching $(LIMA_INSTANCE_PREFIX)-*."; \
	else \
		echo "Stopped $$stopped Lima VM(s)."; \
	fi

.PHONY: stop
stop:
	@$(MAKE) stop-lima

.PHONY: start
start:
	@$(MAKE) lima-vms-up

.PHONY: ensure-host-gateway-proxy stop-host-gateway-proxy proxy-status
ensure-host-gateway-proxy:
	@$(MAKE) check-conflicting-clusters-stopped
	@"$(HOST_GATEWAY_PROXY)" ensure

stop-host-gateway-proxy:
	@"$(HOST_GATEWAY_PROXY)" stop

proxy-status:
	@"$(HOST_GATEWAY_PROXY)" status

.PHONY: configure-k3s-apiserver-oidc
configure-k3s-apiserver-oidc:
	@set -euo pipefail; \
	tfvar_files=(); \
	if [ -f "$(stage_var_file)" ]; then tfvar_files+=("$(stage_var_file)"); fi; \
	if [ -f "$(target_var_file)" ]; then tfvar_files+=("$(target_var_file)"); fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_BASE_TFVARS}"); fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_TFVARS}"); fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" \
	LIMA_NODE_NAME="$(LIMA_INSTANCE_PREFIX)-1" \
	PLATFORM_BASE_DOMAIN="$$( "$(RESOLVE_TFVAR_VALUE)" platform_base_domain 127.0.0.1.sslip.io "$${tfvar_files[@]}" )" \
	PLATFORM_ADMIN_BASE_DOMAIN="$$( "$(RESOLVE_TFVAR_VALUE)" platform_admin_base_domain "" "$${tfvar_files[@]}" )" \
	"$(CONFIGURE_K3S_APISERVER_OIDC)"

.PHONY: init
init:
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Missing $(target_profile_file)"; exit 1; fi
	@if [ -n "$(stage_file)" ] && [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE). Expected one of: $(VALID_STAGES)"; exit 1; fi
	@cd "$(STACK_DIR)" && TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) init $(TG_INIT_FLAGS)

.PHONY: plan
plan: workflow-validate
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Missing $(target_profile_file)"; exit 1; fi
	@if [ -z "$(stage_file)" ] || [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE). Expected one of: $(VALID_STAGES)"; exit 1; fi
	@$(MAKE) check-stage-monotonicity
	@set -euo pipefail; \
	. "$(PROFILE_LIB)"; \
	profile_setup_session "lima" "$(STAGE)" "plan" "$(KUBECONFIG_PATH)" "$(KUBECONFIG_CONTEXT)"; \
	profile_enabled=0; \
	if profile_is_enabled; then \
		profile_enabled=1; \
		trap 'rc=$$?; profile_finish_session "$$rc"' EXIT; \
	fi; \
	run_step() { \
		local step="$$1"; shift; \
		if [ "$$profile_enabled" = "1" ]; then \
			profile_run_step "$$step" "$$@"; \
		else \
			"$$@"; \
		fi; \
	}; \
	stage_num=$$((10#$(STAGE))); \
	if [ "$$stage_num" -eq 100 ]; then \
		echo "Stage 100 plan:"; \
		echo "  - ensure Kind and Slicer are stopped"; \
		echo "  - ensure $(DESIRED_NODES) Lima VM(s) named $(LIMA_INSTANCE_PREFIX)-* are running"; \
		echo "  - bootstrap or refresh the $(K3SUP_CONTEXT) kubeconfig at $(KUBECONFIG_PATH)"; \
		echo ""; \
		$(MAKE) status || true; \
		exit 0; \
	fi; \
	if [ "$$stage_num" -ge 500 ]; then \
		$(MAKE) check-platform-env; \
	fi; \
	$(MAKE) check-conflicting-clusters-stopped; \
	$(MAKE) check-kubeconfig >/dev/null; \
	if ! KUBECONFIG="$(KUBECONFIG_PATH)" kubectl get nodes >/dev/null 2>&1; then \
		echo "$(KUBECONFIG_CONTEXT) not reachable. Run: make 100 apply"; \
		exit 1; \
	fi; \
	plan_args="-var-file=$(stage_var_file) -var-file=$(target_var_file)"; \
	if [ -n "$${KUBECONFIG_PATH:-}" ]; then plan_args="$$plan_args -var kubeconfig_path=$${KUBECONFIG_PATH}"; fi; \
	if [ -n "$${KUBECONFIG_CONTEXT:-}" ]; then plan_args="$$plan_args -var kubeconfig_context=$${KUBECONFIG_CONTEXT}"; fi; \
	if [ -n "$${TARGET_CLUSTER_NAME:-}" ]; then plan_args="$$plan_args -var cluster_name=$${TARGET_CLUSTER_NAME}"; fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then plan_args="$$plan_args -var-file=$${PLATFORM_BASE_TFVARS}"; fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then plan_args="$$plan_args -var-file=$${PLATFORM_TFVARS}"; fi; \
	tg_init() { \
		cd "$(STACK_DIR)" && \
		TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) init $(TG_INIT_FLAGS); \
	}; \
	tg_plan() { \
		cd "$(STACK_DIR)" && \
		TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) plan $$plan_args; \
	}; \
	run_step "terragrunt-init" tg_init; \
	run_step "terragrunt-plan" tg_plan

.PHONY: apply
apply: workflow-validate
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Missing $(target_profile_file)"; exit 1; fi
	@if [ -z "$(stage_file)" ] || [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE). Expected one of: $(VALID_STAGES)"; exit 1; fi
	@$(MAKE) check-stage-monotonicity
	@$(MAKE) check-platform-env-file
	@set -euo pipefail; \
	mode_enabled() { \
		local mode="$$1"; local auto_threshold="$$2"; local stage_num_local="$$3"; \
		case "$$mode" in \
			on) return 0 ;; \
			off) return 1 ;; \
			auto) [ "$$stage_num_local" -ge "$$auto_threshold" ] ;; \
			*) echo "Invalid helper mode: $$mode" >&2; exit 1 ;; \
		esac; \
	}; \
	. "$(PROFILE_LIB)"; \
	profile_setup_session "lima" "$(STAGE)" "apply" "$(KUBECONFIG_PATH)" "$(KUBECONFIG_CONTEXT)"; \
	profile_enabled=0; \
	if profile_is_enabled; then \
		profile_enabled=1; \
		trap 'rc=$$?; profile_finish_session "$$rc"' EXIT; \
	fi; \
	run_step() { \
		local step="$$1"; shift; \
		if [ "$$profile_enabled" = "1" ]; then \
			profile_run_step "$$step" "$$@"; \
		else \
			"$$@"; \
		fi; \
	}; \
	local_cache_available() { \
		curl -fsS "http://$(LOCAL_IMAGE_CACHE_PUSH_HOST)/v2/" >/dev/null 2>&1; \
	}; \
	tfvar_files=(); \
	if [ -f "$(stage_var_file)" ]; then tfvar_files+=("$(stage_var_file)"); fi; \
	if [ -f "$(target_var_file)" ]; then tfvar_files+=("$(target_var_file)"); fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_BASE_TFVARS}"); fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_TFVARS}"); fi; \
	prefer_external_platform_images="$$( "$(RESOLVE_TFVAR_VALUE)" prefer_external_platform_images false "$${tfvar_files[@]}" )"; \
	enable_gateway_tls="$$( "$(RESOLVE_TFVAR_VALUE)" enable_gateway_tls false "$${tfvar_files[@]}" )"; \
	enable_headlamp="$$( "$(RESOLVE_TFVAR_VALUE)" enable_headlamp false "$${tfvar_files[@]}" )"; \
	enable_sso="$$( "$(RESOLVE_TFVAR_VALUE)" enable_sso false "$${tfvar_files[@]}" )"; \
	stage_num=$$((10#$(STAGE))); \
	if [ "$$stage_num" -ge 500 ]; then \
		$(MAKE) check-docker-daemon; \
		$(MAKE) check-platform-env; \
	fi; \
	if [ "$$stage_num" -eq 100 ]; then \
		$(MAKE) prereqs; \
		$(MAKE) check-conflicting-clusters-stopped; \
		run_step "lima-vms-up" $(MAKE) lima-vms-up; \
		run_step "bootstrap-k3s" $(MAKE) bootstrap-k3s; \
		run_step "check-kubeconfig" $(MAKE) check-kubeconfig; \
		exit 0; \
	fi; \
	$(MAKE) check-conflicting-clusters-stopped; \
	$(MAKE) check-kubeconfig >/dev/null; \
	if ! KUBECONFIG="$(KUBECONFIG_PATH)" kubectl get nodes >/dev/null 2>&1; then \
		echo "$(KUBECONFIG_CONTEXT) not reachable; bootstrapping via STAGE=100"; \
		$(MAKE) apply STAGE=100 AUTO_APPROVE=1; \
	fi; \
	case "$(LIMA_HOST_GATEWAY_PROXY_MODE)" in \
		on) run_step "ensure-host-gateway-proxy" $(MAKE) ensure-host-gateway-proxy >/dev/null ;; \
		auto) if [ "$$stage_num" -ge 500 ]; then run_step "ensure-host-gateway-proxy" $(MAKE) ensure-host-gateway-proxy >/dev/null; fi ;; \
		off) ;; \
		*) echo "Invalid helper mode: $(LIMA_HOST_GATEWAY_PROXY_MODE)" >&2; exit 1 ;; \
	esac; \
	if mode_enabled "$(PLATFORM_LOCAL_IMAGE_CACHE_MODE)" 700 "$$stage_num"; then \
		run_step "sync-image-cache" $(MAKE) sync-image-cache; \
	elif [ "$$stage_num" -ge 700 ] && ! local_cache_available; then \
		echo "Stage $(STAGE) expects workload images from $(LOCAL_IMAGE_CACHE_HOST), but PLATFORM_LOCAL_IMAGE_CACHE_MODE=off and no registry is reachable at http://$(LOCAL_IMAGE_CACHE_PUSH_HOST)/v2/."; \
		echo "Set PLATFORM_LOCAL_IMAGE_CACHE_MODE=on or start a compatible cache manually."; \
		exit 1; \
	fi; \
	if [ "$$stage_num" -ge 800 ] && [ "$$prefer_external_platform_images" = "true" ] && mode_enabled "$(PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE)" 800 "$$stage_num"; then \
		run_step "build-local-platform-images" $(MAKE) build-local-platform-images; \
	elif [ "$$stage_num" -ge 800 ] && [ "$$prefer_external_platform_images" = "true" ]; then \
		echo "Skipping platform image build (PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE=$(PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE))"; \
	fi; \
	if [ "$$stage_num" -ge 700 ] && mode_enabled "$(PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE)" 700 "$$stage_num"; then \
		run_step "build-workload-images" $(MAKE) build-workload-images; \
	elif [ "$$stage_num" -ge 700 ]; then \
		echo "Skipping workload image build (PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=$(PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE))"; \
	fi; \
	apply_args="-var-file=$(stage_var_file) -var-file=$(target_var_file)"; \
	if [ -n "$${KUBECONFIG_PATH:-}" ]; then apply_args="$$apply_args -var kubeconfig_path=$${KUBECONFIG_PATH}"; fi; \
	if [ -n "$${KUBECONFIG_CONTEXT:-}" ]; then apply_args="$$apply_args -var kubeconfig_context=$${KUBECONFIG_CONTEXT}"; fi; \
	if [ -n "$${TARGET_CLUSTER_NAME:-}" ]; then apply_args="$$apply_args -var cluster_name=$${TARGET_CLUSTER_NAME}"; fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then apply_args="$$apply_args -var-file=$${PLATFORM_BASE_TFVARS}"; fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then apply_args="$$apply_args -var-file=$${PLATFORM_TFVARS}"; fi; \
	if [ "$(AUTO_APPROVE)" = "1" ]; then \
		apply_args="$$apply_args -auto-approve"; \
	fi; \
	tg_init() { \
		cd "$(STACK_DIR)" && \
		TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) init $(TG_INIT_FLAGS); \
	}; \
	tg_apply() { \
		cd "$(STACK_DIR)" && \
		TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) apply $$apply_args; \
	}; \
	run_step "terragrunt-init" tg_init; \
	run_step "terragrunt-apply" tg_apply; \
	if [ "$$stage_num" -ge 900 ] && [ "$$enable_gateway_tls" = "true" ] && [ "$$enable_headlamp" = "true" ] && [ "$$enable_sso" = "true" ]; then \
		run_step "configure-k3s-apiserver-oidc" $(MAKE) -C "$(MAKEFILE_DIR)" configure-k3s-apiserver-oidc; \
		run_step "check-health" $(MAKE) -C "$(MAKEFILE_DIR)" check-health STAGE="$(STAGE)"; \
		run_step "check-sso-e2e" $(MAKE) -C "$(MAKEFILE_DIR)" check-sso-e2e STAGE="$(STAGE)"; \
	fi

.PHONY: check-health
check-health:
	@case "$(LIMA_HOST_GATEWAY_PROXY_MODE)" in \
		on|auto) $(MAKE) ensure-host-gateway-proxy >/dev/null ;; \
		off) ;; \
		*) echo "Invalid helper mode: $(LIMA_HOST_GATEWAY_PROXY_MODE)" >&2; exit 1 ;; \
	esac
	@$(MAKE) check-kubeconfig >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-cluster-health.sh" $$vf

.PHONY: check-security
check-security:
	@$(MAKE) check-kubeconfig >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-security.sh" $$vf

.PHONY: check-gateway-stack
check-gateway-stack:
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-gateway-stack.sh"

.PHONY: check-cluster
check-cluster:
	@$(MAKE) check-platform-env
	@KUBECONFIG="$(KUBECONFIG_PATH)" \
		GITEA_USER="gitea-admin" \
		GITEA_PWD="$${GITEA_PWD:-$${PLATFORM_ADMIN_PASSWORD}}" \
		REGISTRY_HOST="$(LOCAL_IMAGE_CACHE_PUSH_HOST)" \
		EXPECT_SENTIMENT_REPO="$(EXPECT_SENTIMENT_REPO)" \
		EXPECT_SUBNETCALC_REPO="$(EXPECT_SUBNETCALC_REPO)" \
		EXPECT_ACTIONS_RUNS="$(EXPECT_ACTIONS_RUNS)" \
		EXPECT_NAMESPACE_SSO="$(EXPECT_NAMESPACE_SSO)" \
		EXPECT_NAMESPACE_OBSERVABILITY="$(EXPECT_NAMESPACE_OBSERVABILITY)" \
		EXPECT_NAMESPACE_PLATFORM_GATEWAY="$(EXPECT_NAMESPACE_PLATFORM_GATEWAY)" \
		"$(STACK_DIR)/scripts/check-cluster.sh"

.PHONY: check-gateway-urls
check-gateway-urls:
	@case "$(LIMA_HOST_GATEWAY_PROXY_MODE)" in \
		on|auto) $(MAKE) ensure-host-gateway-proxy >/dev/null ;; \
		off) ;; \
		*) echo "Invalid helper mode: $(LIMA_HOST_GATEWAY_PROXY_MODE)" >&2; exit 1 ;; \
	esac
	@$(MAKE) check-kubeconfig >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-gateway-urls.sh" $$vf

.PHONY: check-app
check-app:
	@case "$(LIMA_HOST_GATEWAY_PROXY_MODE)" in \
		on|auto) $(MAKE) ensure-host-gateway-proxy >/dev/null ;; \
		off) ;; \
		*) echo "Invalid helper mode: $(LIMA_HOST_GATEWAY_PROXY_MODE)" >&2; exit 1 ;; \
	esac
	@$(MAKE) check-kubeconfig >/dev/null
	@set -euo pipefail; \
	if [ -z "$${APP:-}" ]; then echo "Missing APP=... (e.g., APP=signoz)"; exit 1; fi; \
	vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	path_flag=""; \
	if [ -n "$${APP_PATH:-}" ]; then path_flag="--path $${APP_PATH}"; fi; \
	host_flag=""; \
	if [ -n "$${HOST:-}" ]; then host_flag="--host $${HOST}"; fi; \
	ext_flag=""; \
	if [ "$${EXTENDED:-0}" = "1" ]; then ext_flag="--extended"; fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-app.sh" $$vf --app "$${APP}" $$host_flag $$path_flag $$ext_flag

.PHONY: check-sso
check-sso:
	@case "$(LIMA_HOST_GATEWAY_PROXY_MODE)" in \
		on|auto) $(MAKE) ensure-host-gateway-proxy >/dev/null ;; \
		off) ;; \
		*) echo "Invalid helper mode: $(LIMA_HOST_GATEWAY_PROXY_MODE)" >&2; exit 1 ;; \
	esac
	@$(MAKE) check-kubeconfig >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" "$(STACK_DIR)/scripts/check-sso.sh" $$vf

.PHONY: check-sso-e2e
check-sso-e2e:
	@set -euo pipefail; \
	$(MAKE) check-kubeconfig >/dev/null; \
	case "$(LIMA_HOST_GATEWAY_PROXY_MODE)" in \
		on|auto) $(MAKE) ensure-host-gateway-proxy ;; \
		off) echo "check-sso-e2e requires host gateway proxies or an equivalent manual setup. Set LIMA_HOST_GATEWAY_PROXY_MODE=on to let the Makefile manage them."; exit 1 ;; \
		*) echo "Invalid helper mode: $(LIMA_HOST_GATEWAY_PROXY_MODE)" >&2; exit 1 ;; \
	esac; \
	stage_tfvars="$(abspath $(STAGE_FILE_900))"; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		stage_tfvars="$(stage_var_file)"; \
	fi; \
	STAGE_TFVARS="$$stage_tfvars" "$(MAKEFILE_DIR)/../../tests/kubernetes/sso/run.sh"

.PHONY: gitea-sync
gitea-sync:
	@set -euo pipefail; \
	$(MAKE) check-platform-env; \
	stack_path="$(abspath $(STACK_DIR))"; \
	script="$$stack_path/scripts/sync-gitea.sh"; \
	if [ ! -x "$$script" ]; then echo "Missing $$script"; exit 1; fi; \
	dry_flag=""; \
	sync_stage_file="$(abspath $(STAGE_FILE_900))"; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then sync_stage_file="$(stage_var_file)"; fi; \
	if [ "$(DRY_RUN)" = "1" ]; then dry_flag="--dry-run"; fi; \
	GITEA_POLICIES_REMOTE="$${GITEA_POLICIES_REMOTE:-http://127.0.0.1:30090/platform/policies.git}" \
	GITEA_BRANCH="$${GITEA_BRANCH:-main}" \
	GITEA_USER="$${GITEA_USER:-gitea-admin}" \
	GITEA_PASSWORD="$${GITEA_PASSWORD:-$${PLATFORM_ADMIN_PASSWORD}}" \
	GITEA_LOCAL_ACCESS_MODE="$${GITEA_LOCAL_ACCESS_MODE:-port-forward}" \
	GITEA_SYNC_TFVARS_FILE="$$sync_stage_file" \
	STACK_DIR="$$stack_path" \
	KUBECONFIG="$(KUBECONFIG_PATH)" \
	KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" \
	"$$script" $${dry_flag}

.PHONY: launchpad-render
launchpad-render:
	@set -euo pipefail; \
	stack_path="$(abspath $(STACK_DIR))"; \
	script="$$stack_path/scripts/render-platform-launchpad.sh"; \
	if [ ! -x "$$script" ]; then echo "Missing $$script"; exit 1; fi; \
	STACK_DIR="$$stack_path" "$$script"

.PHONY: show-urls
show-urls:
	@case "$(LIMA_HOST_GATEWAY_PROXY_MODE)" in \
		on|auto) $(MAKE) ensure-host-gateway-proxy >/dev/null ;; \
		off) ;; \
		*) echo "Invalid helper mode: $(LIMA_HOST_GATEWAY_PROXY_MODE)" >&2; exit 1 ;; \
	esac
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-cluster-health.sh" --show-urls $$vf

.PHONY: reset
reset:
	@set -euo pipefail; \
	ctx="$${KUBECONFIG_CONTEXT:-$(KUBECONFIG_CONTEXT)}"; \
	state_dir="$(dir $(STATE_FILE))"; \
	vm_names="$$(limactl list -q 2>/dev/null | grep -E '^$(LIMA_INSTANCE_PREFIX)-[0-9]+$$' || true)"; \
	echo "This will:"; \
	echo "  - Delete Lima VMs matching $(LIMA_INSTANCE_PREFIX)-*"; \
	echo "  - Stop conflicting kind/Slicer runtimes (best-effort)"; \
	echo "  - Remove kubeconfig context/cluster/user: $$ctx"; \
	echo "  - Stop host gateway proxy containers"; \
	echo "  - Remove local terragrunt state: $$state_dir"; \
	echo "  - Clean stack caches (.terraform/.terragrunt-cache)"; \
	echo ""; \
	if [ "$(AUTO_APPROVE)" != "1" ]; then \
		printf "Proceed with Lima VM deletion, kubeconfig cleanup, and local state cleanup? [y/N] "; read -r confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "ABORTED: reset cancelled by user."; \
			exit 0; \
		fi; \
	fi; \
	echo ""; \
	echo "Stopping conflicting platform runtimes (best-effort)..."; \
	"$(STOP_PLATFORM_RUNTIMES)" --exclude lima; \
	echo "OK   conflicting platform runtimes stopped"; \
	echo ""; \
	echo "Stopping host gateway proxy containers (best-effort)..."; \
	$(MAKE) stop-host-gateway-proxy >/dev/null 2>&1 || true; \
	echo "OK   proxies stopped"; \
	echo ""; \
	echo "Cleaning kubeconfig (best-effort)..."; \
	if [ -n "$$ctx" ]; then \
		if [ -e "$(KUBECONFIG_PATH)" ]; then \
			KUBECONFIG_RESET_AUTO_APPROVE="$(AUTO_APPROVE)" "$(KUBECONFIG_HELPER)" prepare-for-reset "$(KUBECONFIG_PATH)"; \
			"$(KUBECONFIG_HELPER)" delete-context "$(KUBECONFIG_PATH)" "$$ctx" "$$ctx" "$$ctx" 1; \
			echo "OK   cleaned $$ctx from $(KUBECONFIG_PATH)"; \
		else \
			echo "OK   no kubeconfig file at $(KUBECONFIG_PATH)"; \
		fi; \
		if [ -e "$(DEFAULT_KUBECONFIG_PATH)" ]; then \
			KUBECONFIG_RESET_AUTO_APPROVE="$(AUTO_APPROVE)" "$(KUBECONFIG_HELPER)" prepare-for-reset "$(DEFAULT_KUBECONFIG_PATH)"; \
			"$(KUBECONFIG_HELPER)" delete-context "$(DEFAULT_KUBECONFIG_PATH)" "$$ctx" "$$ctx" "$$ctx" 0; \
			echo "OK   cleaned $$ctx from $(DEFAULT_KUBECONFIG_PATH)"; \
		else \
			echo "OK   no kubeconfig file at $(DEFAULT_KUBECONFIG_PATH)"; \
		fi; \
	fi; \
	echo ""; \
	echo "Deleting Lima VMs (best-effort)..."; \
	if [ -n "$$vm_names" ]; then \
		limactl delete --yes --force $$vm_names; \
		echo "OK   deleted: $$vm_names"; \
	else \
		echo "OK   no Lima VMs matching $(LIMA_INSTANCE_PREFIX)-*"; \
	fi; \
	echo ""; \
	echo "Cleaning local state/caches..."; \
	rm -rf "$$state_dir" 2>/dev/null || true; \
	rm -rf "$(STACK_DIR)/.terraform" "$(STACK_DIR)/.terragrunt-cache" 2>/dev/null || true; \
	rm -rf "$(STACK_DIR)/.run" 2>/dev/null || true; \
	rm -f "$(STACK_DIR)/backend.tf" 2>/dev/null || true; \
	echo "OK   done"

.PHONY: env
env:
	@$(MAKE) prereqs

.PHONY: test
test:
	@$(MAKE) check-stage-monotonicity
	@$(MAKE) test-shell
	@$(MAKE) test-bats
	@$(MAKE) prepare-state
	@cd "$(STACK_DIR)" && tofu init -backend=false -input=false && tofu test

.PHONY: test-shell
test-shell:
	@/bin/bash "$(REPO_ROOT)/scripts/check-bash32-compat.sh"
	@"$(REPO_ROOT)/scripts/audit-shell-scripts.sh"
	@shellcheck \
		"$(MAKEFILE_DIR)scripts/"*.sh \
		"$(STACK_DIR)/scripts/check-cluster-health.sh" \
		"$(STACK_DIR)/scripts/check-version.sh"

.PHONY: test-bats test-unit
test-bats:
	@bats "$(MAKEFILE_DIR)tests"

test-unit: test-bats

.PHONY: check-version
check-version:
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG="$(KUBECONFIG_PATH)" STAGES_DIR="$(abspath $(MAKEFILE_DIR)stages)" TARGET_TFVARS="$(target_var_file)" PRELOAD_IMAGES_FILE="$(preload_images_file)" "$(STACK_DIR)/scripts/check-version.sh"
	@echo ""
	@"$(STACK_DIR)/scripts/check-provider-version.sh"

.PHONY: check-provider-version
check-provider-version:
	@"$(STACK_DIR)/scripts/check-provider-version.sh"
