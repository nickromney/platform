.DEFAULT_GOAL := help
SHELL := /bin/bash

TG ?= terragrunt
TG_LOG_SHOW_ABS_PATHS ?= true
TG_INIT_FLAGS ?= -reconfigure
STACK_DIR := ../../terraform/kubernetes
STATE_FILE ?= ../../terraform/.run/kubernetes-slicer/terraform.tfstate
TG_STATE_PATH ?= $(abspath $(STATE_FILE))
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(MAKEFILE_DIR)../..)
MAKE_SUGGEST_SCRIPT := $(MAKEFILE_DIR)../../scripts/suggest-make-goal.sh
RUN_DIR := $(MAKEFILE_DIR).run
PROFILE_LIB := $(STACK_DIR)/scripts/profile-lib.sh
SCRIPTS_DIR := $(MAKEFILE_DIR)scripts
CHECK_STAGE_MONOTONICITY := $(SCRIPTS_DIR)/check-stage-monotonicity.sh
CHECK_KIND_STOPPED := $(MAKEFILE_DIR)../scripts/check-kind-stopped.sh
CHECK_LIMA_STOPPED := $(MAKEFILE_DIR)../scripts/check-lima-stopped.sh
STOP_PLATFORM_RUNTIMES := $(MAKEFILE_DIR)../scripts/stop-platform-runtimes.sh
CHECK_HOST_PORTS := $(SCRIPTS_DIR)/check-slicer-host-ports.sh
HOST_GATEWAY_PROXY := $(SCRIPTS_DIR)/host-gateway-proxy.sh
START_DAEMON := $(SCRIPTS_DIR)/start-daemon.sh
STOP_DAEMON := $(SCRIPTS_DIR)/stop-daemon.sh
ENSURE_SBOX_VM := $(SCRIPTS_DIR)/ensure-sbox-vm.sh
DELETE_SLICER_VM := $(SCRIPTS_DIR)/delete-vm-best-effort.sh
BOOTSTRAP_K3S := $(SCRIPTS_DIR)/bootstrap-k3s-slicer.sh
WAIT_FOR_KUBECTL := $(SCRIPTS_DIR)/wait-for-kubectl.sh
HOST_FORWARDS := $(SCRIPTS_DIR)/ensure-host-forwards.sh
ENSURE_IMAGE_CACHE := $(SCRIPTS_DIR)/ensure-image-cache.sh
CONFIGURE_K3S_APISERVER_OIDC := $(SCRIPTS_DIR)/configure-k3s-apiserver-oidc.sh
RESOLVE_TFVAR_VALUE := $(MAKEFILE_DIR)../scripts/resolve-tfvar-value.sh
BUILD_LOCAL_PLATFORM_IMAGES := $(MAKEFILE_DIR)../kind/scripts/build-local-platform-images.sh
KUBECONFIG_HELPER := $(STACK_DIR)/scripts/manage-kubeconfig.sh
AUTO_APPROVE ?= 0
DRY_RUN ?= 0
STAGE ?= 100
DEFAULT_KUBECONFIG_PATH ?= $(HOME)/.kube/config
MERGE_KUBECONFIG_TO_DEFAULT ?= 0
SLICER_SYSTEM_SOCKET ?= $(HOME)/slicer-mac/slicer.sock
SLICER_SOCKET ?= $(SLICER_SYSTEM_SOCKET)
SLICER_CONFIG ?= $(HOME)/slicer-mac/slicer-mac.yaml
SLICER_URL_OVERRIDE := $(strip $(filter-out $(SLICER_SYSTEM_SOCKET),$(SLICER_URL)))
SLICER_SOCKET_OVERRIDE := $(strip $(filter-out $(SLICER_SYSTEM_SOCKET),$(SLICER_SOCKET)))
SLICER_ACTIVE_URL := $(if $(SLICER_URL_OVERRIDE),$(SLICER_URL_OVERRIDE),$(if $(SLICER_SOCKET_OVERRIDE),$(SLICER_SOCKET_OVERRIDE),$(SLICER_SYSTEM_SOCKET)))
SLICER_ENDPOINT_SOURCE := $(if $(SLICER_URL_OVERRIDE),SLICER_URL,$(if $(SLICER_SOCKET_OVERRIDE),SLICER_SOCKET,SLICER_SYSTEM_SOCKET))
SLICER_USE_LOCAL_MAC := $(if $(filter SLICER_SYSTEM_SOCKET,$(SLICER_ENDPOINT_SOURCE)),1,0)
SLICER_SYSTEM_SOCKET_WAIT_SECONDS ?= 240
SLICER_NETWORK_PROFILE ?= cilium
SLICER_VM_GROUP ?= slicer
SLICER_VM_NAME ?= $(SLICER_VM_GROUP)-1
SLICER_VM_USER ?= ubuntu
SLICER_VM_READY_TIMEOUT ?= 300s
SLICER_GATEWAY_HTTPS_GUEST_PORT ?= 30070
SLICER_GATEWAY_HTTPS_FORWARD_PORT ?= 8443
SLICER_VM_CPUS ?=
SLICER_VM_RAM_GB ?=
SLICER_VM_MIN_DISK_GB ?= 25
SLICER_SWAP_SIZE ?= 4G
SLICER_ALLOW_EXISTING_K3S ?= 0
SLICER_HOST_FORWARDS_MODE ?= auto
K3SUP_CONTEXT ?= slicer-k3s
KUBECONFIG_PATH ?= $(HOME)/.kube/$(K3SUP_CONTEXT).yaml
KUBECONFIG_CONTEXT ?= $(K3SUP_CONTEXT)
KUBECTL_REACHABILITY_ATTEMPTS ?= 10
KUBECTL_REACHABILITY_DELAY_SECONDS ?= 3
K3S_VERSION ?= v1.35.1+k3s1
K3S_CHANNEL ?= stable
K3S_SERVER_EXTRA_ARGS_CILIUM := --flannel-backend=none --disable-network-policy --disable=traefik --disable=servicelb
K3S_SERVER_EXTRA_ARGS_DEFAULT := --disable-network-policy --disable=traefik --disable=servicelb
K3S_SERVER_EXTRA_ARGS ?= $(if $(filter default,$(SLICER_NETWORK_PROFILE)),$(K3S_SERVER_EXTRA_ARGS_DEFAULT),$(K3S_SERVER_EXTRA_ARGS_CILIUM))
LOCAL_IMAGE_CACHE_HOST ?= 192.168.64.1:5002
LOCAL_IMAGE_CACHE_PUSH_HOST ?= 127.0.0.1:5002
LOCAL_IMAGE_CACHE_SCHEME ?= http
LOCAL_IMAGE_CACHE_OPTIONAL ?= 1
LOCAL_IMAGE_CACHE_CONTAINER ?= slicer-image-cache
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
WORKLOAD_IMAGE_NAMESPACE ?= platform
WORKLOAD_IMAGE_TAG ?= latest
EXPECT_SENTIMENT_REPO ?= 0
EXPECT_SUBNETCALC_REPO ?= 0
EXPECT_ACTIONS_RUNS ?= 0
EXPECT_NAMESPACE_SSO ?= 0
EXPECT_NAMESPACE_OBSERVABILITY ?= 0
EXPECT_NAMESPACE_PLATFORM_GATEWAY ?= 0
FORWARD_PID_FILE ?= $(RUN_DIR)/slicer-host-forwards.pid
SLICER_CHECK_LIMA_INSTANCE_PREFIX ?= k3s-node
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
PLATFORM_ADMIN_PASSWORD ?=
PLATFORM_DEMO_PASSWORD ?=
PLATFORM_REQUIRED_ENV_VARS := PLATFORM_ADMIN_PASSWORD PLATFORM_DEMO_PASSWORD
ifneq ($(strip $(wildcard $(PLATFORM_ENV_FILE))),)
include $(PLATFORM_ENV_FILE)
endif

VALID_STAGES := 100 200 300 400 500 600 700 800 900
VALID_ACTIONS := plan apply
VALID_STAGE_HELPERS := check-health check-security
VALID_SLICER_NETWORK_PROFILES := cilium default
VALID_HELPER_MODES := auto on off
MAKE_KNOWN_GOALS := help prepare-state check-stage-monotonicity check-docker-daemon check-kind-stopped check-lima-stopped check-conflicting-clusters-stopped check-kubeconfig check-host-ports check-platform-env-file prereqs daemon-up daemon-down slicer-vm-up start bootstrap-k3s merge-default-kubeconfig ensure-host-forwards stop-host-forwards host-forward-status ensure-image-cache sync-image-cache build-workload-images status stop-slicer stop check-vm-health configure-k3s-apiserver-oidc init plan apply check-health check-security check-gateway-stack check-cluster check-gateway-urls check-app check-sso check-sso-e2e gitea-sync launchpad-render show-urls reset env test test-shell test-bats test-unit check-version check-provider-version $(VALID_ACTIONS) $(VALID_STAGES)

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

ifeq ($(filter $(SLICER_NETWORK_PROFILE),$(VALID_SLICER_NETWORK_PROFILES)),)
$(error Invalid SLICER_NETWORK_PROFILE="$(SLICER_NETWORK_PROFILE)". Expected one of: $(VALID_SLICER_NETWORK_PROFILES))
endif
ifeq ($(filter $(MERGE_KUBECONFIG_TO_DEFAULT),0 1),)
$(error Invalid MERGE_KUBECONFIG_TO_DEFAULT="$(MERGE_KUBECONFIG_TO_DEFAULT)". Expected one of: 0 1)
endif
ifeq ($(filter $(SLICER_HOST_FORWARDS_MODE),$(VALID_HELPER_MODES)),)
$(error Invalid SLICER_HOST_FORWARDS_MODE="$(SLICER_HOST_FORWARDS_MODE)". Expected one of: $(VALID_HELPER_MODES))
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

STAGES_DIR := stages
ifeq ($(SLICER_NETWORK_PROFILE),default)
STAGES_DIR := stages/default-cni
endif

STAGE_FILE_100 := $(STAGES_DIR)/100-cluster.tfvars
STAGE_FILE_200 := $(STAGES_DIR)/200-cilium.tfvars
STAGE_FILE_300 := $(STAGES_DIR)/300-hubble.tfvars
STAGE_FILE_400 := $(STAGES_DIR)/400-argocd.tfvars
STAGE_FILE_500 := $(STAGES_DIR)/500-gitea.tfvars
STAGE_FILE_600 := $(STAGES_DIR)/600-policies.tfvars
STAGE_FILE_700 := $(STAGES_DIR)/700-app-repos.tfvars
STAGE_FILE_800 := $(STAGES_DIR)/800-gateway-tls.tfvars
STAGE_FILE_900 := $(STAGES_DIR)/900-sso.tfvars

stage_file = $(STAGE_FILE_$(STAGE))
target_profile_file = targets/slicer.tfvars
stage_var_file = $(abspath $(stage_file))
target_var_file = $(abspath $(target_profile_file))
preload_images_file = $(abspath $(MAKEFILE_DIR)preload-images.txt)
stage_dir_abs = $(abspath $(MAKEFILE_DIR)$(STAGES_DIR))

RESOLVE_SOCKET = printf '%s\n' "$(SLICER_ACTIVE_URL)"

.PHONY: help
help:
	@echo "slicer demo (Slicer microVM + k3s + shared Terraform platform stack)"
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
	@echo "  make check-app    APP=signoz [APP_PATH=/metrics-explorer/summary] [EXTENDED=1]"
	@echo "  make check-cluster"
	@echo "  make check-gateway-stack"
	@echo "  make check-gateway-urls"
	@echo "  make check-health"
	@echo "  make check-host-ports"
	@echo "  make check-kind-stopped"
	@echo "  make check-lima-stopped"
	@echo "  make check-provider-version"
	@echo "  make check-security"
	@echo "  make check-sso"
	@echo "  make check-sso-e2e"
	@echo "  make check-stage-monotonicity"
	@echo "  make check-version"
	@echo "  make check-vm-health"
	@echo "  make configure-k3s-apiserver-oidc"
	@echo "  make daemon-down"
	@echo "  make daemon-up"
	@echo "  make env"
	@echo "  make ensure-host-forwards"
	@echo "  make ensure-image-cache"
	@echo "  make gitea-sync"
	@echo "  make launchpad-render"
	@echo "  make merge-default-kubeconfig"
	@echo "  make plan         100|200|300|...|900"
	@echo "  make prereqs"
	@echo "  make reset        [AUTO_APPROVE=1]"
	@echo "  make show-urls"
	@echo "  make start        Alias for slicer-vm-up"
	@echo "  make slicer-vm-up"
	@echo "  make status"
	@echo "  make stop"
	@echo "  make stop-host-forwards"
	@echo "  make sync-image-cache"
	@echo "  make test"
	@echo "  make build-local-platform-images"
	@echo ""
	@echo "Stages:"
	@echo "  100 - bootstrap k3s on Slicer"
	@echo "  200 - cilium (or default-CNI no-op placeholder)"
	@echo "  300 - hubble (or default-CNI no-op placeholder)"
	@echo "  400 - argocd core"
	@echo "  500 - gitea"
	@echo "  600 - policies (or default-CNI no-op placeholder)"
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
	@echo "  slicer -> $(KUBECONFIG_PATH) (split by default; merge explicitly into $(DEFAULT_KUBECONFIG_PATH) if needed)"
	@echo ""
	@echo "Networking profiles:"
	@echo "  SLICER_NETWORK_PROFILE=cilium  -> k3s with flannel disabled, then stages 200/300 add Cilium/Hubble"
	@echo "  SLICER_NETWORK_PROFILE=default -> keep k3s default CNI; stages 200/300 become no-op placeholders"
	@echo "  Switching profiles requires a fresh VM reset; bootstrap refuses in-place flannel/Cilium flips."
	@echo ""
	@echo "Slicer endpoint:"
	@echo "  default (macOS)         -> $(SLICER_SYSTEM_SOCKET)"
	@echo "  override                -> SLICER_URL=<socket|http://...> or SLICER_SOCKET=/path/to.sock"
	@echo "  Docker-only hosts       -> use ../kind (Slicer is optional, not the teaching path)"
	@echo ""
	@echo "Local helper modes:"
	@echo "  MERGE_KUBECONFIG_TO_DEFAULT=1                        -> also merge $(KUBECONFIG_PATH) into $(DEFAULT_KUBECONFIG_PATH) (default: 0)"
	@echo "  SLICER_HOST_FORWARDS_MODE=auto|on|off                -> manage localhost forwards for stable localhost URLs/checks (default: auto)"
	@echo "  SLICER_ALLOW_EXISTING_K3S=1                          -> let stage 100 reuse an existing k3s install and only refresh kubeconfig"
	@echo "  PLATFORM_LOCAL_IMAGE_CACHE_MODE=auto|on|off          -> manage/sync the host registry cache (default: auto, stage>=700)"
	@echo "  PLATFORM_BUILD_LOCAL_PLATFORM_IMAGES_MODE=auto|on|off -> build/push platform shortcut images to the cache (default: auto, stage>=800 when enabled)"
	@echo "  PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=auto|on|off -> build/push app workload images to the cache (default: auto, stage>=700)"
	@echo "  PLATFORM_PROFILE_MODE=off|on|trace                   -> capture apply/plan timings and logs under $(REPO_ROOT)/.run/profiles"

.PHONY: check-stage-monotonicity
check-stage-monotonicity:
	@"$(CHECK_STAGE_MONOTONICITY)"

.PHONY: check-kind-stopped
check-kind-stopped:
	@"$(CHECK_KIND_STOPPED)"

.PHONY: check-lima-stopped
check-lima-stopped:
	@LIMA_INSTANCE_PREFIX="$(SLICER_CHECK_LIMA_INSTANCE_PREFIX)" "$(CHECK_LIMA_STOPPED)"

.PHONY: check-conflicting-clusters-stopped
check-conflicting-clusters-stopped:
	@$(MAKE) check-kind-stopped
	@$(MAKE) check-lima-stopped

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
	target_count=$$("$(KUBECONFIG_HELPER)" count-contexts "$(KUBECONFIG_PATH)"); \
	target_current=$$(kubectl --kubeconfig "$(KUBECONFIG_PATH)" config current-context 2>/dev/null || true); \
	[ -n "$$target_current" ] || target_current="<none>"; \
	echo "OK   slicer kubeconfig: $(KUBECONFIG_PATH) ($$target_count context(s), current=$$target_current)"; \
	kubie_lint_output="$$("$(KUBECONFIG_HELPER)" lint || true)"; \
	if [ -n "$$kubie_lint_output" ]; then \
		echo "WARN kubie lint:"; \
		printf '%s\n' "$$kubie_lint_output" | sed 's/^/  /'; \
	elif command -v kubie >/dev/null 2>&1; then \
		echo "OK   kubie lint"; \
	fi

.PHONY: check-host-ports
check-host-ports:
	@set -euo pipefail; \
	args=(--var-file "$(stage_var_file)" --var-file "$(target_var_file)"); \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		args+=(--var-file "$${PLATFORM_BASE_TFVARS}"); \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		args+=(--var-file "$${PLATFORM_TFVARS}"); \
	fi; \
	"$(CHECK_HOST_PORTS)" "$${args[@]}"

.PHONY: prereqs
prereqs:
	@set -euo pipefail; \
	stage_num=$$((10#$(STAGE))); \
	endpoint="$(SLICER_ACTIVE_URL)"; \
	endpoint_source="$(SLICER_ENDPOINT_SOURCE)"; \
	use_local_slicer_mac="$(SLICER_USE_LOCAL_MAC)"; \
	if [ "$$use_local_slicer_mac" = "1" ] && [ "$$(uname -s)" != "Darwin" ]; then \
		echo "FAIL kubernetes/slicer defaults to the local slicer-mac socket ($(SLICER_SYSTEM_SOCKET))."; \
		echo "Set SLICER_URL or SLICER_SOCKET to a real Slicer endpoint if you want this personal target."; \
		echo "For a teaching or Docker-only Linux host, use kubernetes/kind instead."; \
		exit 1; \
	fi; \
	required=(curl docker git jq kubectl slicer ssh-keygen terragrunt tofu yq); \
	if [ "$$use_local_slicer_mac" = "1" ]; then \
		required+=(slicer-mac); \
	fi; \
	optional=(bats bun cilium helm kubectx kubie kyverno mkcert node npm npx shellcheck yamllint); \
	recommended_test_tools=(bun node npm npx); \
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
	bootstrap_client=""; \
	for candidate in "$${K3SUP_PRO_BIN:-}" "$$(command -v k3sup-pro 2>/dev/null || true)" "$${K3SUP_BIN:-}" "$$(command -v k3sup 2>/dev/null || true)" "$$HOME/.arkade/bin/k3sup"; do \
		[ -n "$$candidate" ] || continue; \
		[ -x "$$candidate" ] || continue; \
		bootstrap_client="$$candidate"; \
		break; \
	done; \
	if [ -n "$$bootstrap_client" ]; then \
		echo "OK   bootstrap client: $$(basename "$$bootstrap_client")"; \
	else \
		echo "FAIL bootstrap client (neither k3sup-pro nor k3sup found)"; \
		missing_required+=("k3sup-pro|k3sup"); \
	fi; \
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
		echo "Recommended browser/E2E test tools missing: $${missing_recommended[*]}"; \
		echo ""; \
		echo "Install hints:"; \
		"$(REPO_ROOT)/scripts/install-tool-hints.sh" --plain "$${missing_recommended[@]}" | sed 's/^/  /'; \
	fi; \
	echo ""; \
	echo "Docker daemon verification:"; \
	if ! docker info >/dev/null 2>&1; then \
		if [ "$$(uname -s)" = "Darwin" ]; then \
			echo "FAIL docker daemon not reachable (is Docker Desktop running?)"; \
		else \
			echo "FAIL docker daemon not reachable"; \
		fi; \
		exit 1; \
	fi; \
	echo "OK   Docker context: $$(docker context show)"; \
	echo ""; \
	$(MAKE) check-conflicting-clusters-stopped; \
	echo ""; \
	echo "Slicer daemon:"; \
	echo "OK   active endpoint ($$endpoint_source): $$endpoint"; \
	if ! SLICER_URL="$$endpoint" slicer info; then \
		echo ""; \
		echo "FAIL slicer daemon not reachable at $$endpoint"; \
		if [ "$$use_local_slicer_mac" = "1" ]; then \
			echo "Start the on-device slicer-mac daemon or point SLICER_URL/SLICER_SOCKET at another Slicer endpoint."; \
		else \
			echo "Verify SLICER_URL/SLICER_SOCKET (and SLICER_TOKEN_FILE/SLICER_TOKEN if required), or use kubernetes/kind on Docker-only hosts."; \
		fi; \
		exit 1; \
	fi; \
	echo ""; \
	echo "Versions:"; \
	docker version --format 'client={{.Client.Version}} server={{.Server.Version}}' 2>/dev/null || true; \
	tofu -version 2>/dev/null | head -n 1 || true; \
	terragrunt --version 2>/dev/null || true; \
	if command -v k3sup >/dev/null 2>&1; then k3sup version 2>/dev/null || true; fi; \
	if command -v k3sup-pro >/dev/null 2>&1; then k3sup-pro version 2>/dev/null || true; fi; \
	echo ""; \
	if [ "$$stage_num" -ge 500 ]; then \
		$(MAKE) check-platform-env; \
		echo ""; \
	fi; \
	$(MAKE) check-kubeconfig

.PHONY: daemon-up
daemon-up:
	@mkdir -p "$(RUN_DIR)"; \
	SLICER_URL="$(SLICER_URL)" \
	SLICER_SOCKET="$(SLICER_SOCKET)" \
	SLICER_SYSTEM_SOCKET="$(SLICER_SYSTEM_SOCKET)" \
	RUN_DIR="$(RUN_DIR)" \
	SLICER_SYSTEM_SOCKET_WAIT_SECONDS="$(SLICER_SYSTEM_SOCKET_WAIT_SECONDS)" \
	"$(START_DAEMON)"

.PHONY: daemon-down
daemon-down:
	@RUN_DIR="$(RUN_DIR)" "$(STOP_DAEMON)"

.PHONY: slicer-vm-up
slicer-vm-up:
	@$(MAKE) check-conflicting-clusters-stopped
	@$(MAKE) daemon-up
	@socket="$$($(RESOLVE_SOCKET))"; \
	SLICER_URL="$$socket" \
	SLICER_VM_NAME="$(SLICER_VM_NAME)" \
	SLICER_VM_GROUP="$(SLICER_VM_GROUP)" \
	SLICER_VM_READY_TIMEOUT="$(SLICER_VM_READY_TIMEOUT)" \
	SLICER_VM_CPUS="$(SLICER_VM_CPUS)" \
	SLICER_VM_RAM_GB="$(SLICER_VM_RAM_GB)" \
	SLICER_VM_MIN_DISK_GB="$(SLICER_VM_MIN_DISK_GB)" \
	SLICER_USE_LOCAL_MAC="$(SLICER_USE_LOCAL_MAC)" \
	SLICER_CONFIG="$(SLICER_CONFIG)" \
	"$(ENSURE_SBOX_VM)"

.PHONY: start
start: slicer-vm-up

.PHONY: bootstrap-k3s
bootstrap-k3s:
	@socket="$$($(RESOLVE_SOCKET))"; \
	SLICER_URL="$$socket" \
	SLICER_VM_NAME="$(SLICER_VM_NAME)" \
	SLICER_VM_USER="$(SLICER_VM_USER)" \
	RUN_DIR="$(RUN_DIR)" \
	K3SUP_CONTEXT="$(K3SUP_CONTEXT)" \
	KUBECONFIG_PATH="$(KUBECONFIG_PATH)" \
	DEFAULT_KUBECONFIG_PATH="$(DEFAULT_KUBECONFIG_PATH)" \
	SLICER_ALLOW_EXISTING_K3S="$(SLICER_ALLOW_EXISTING_K3S)" \
	K3S_VERSION="$(K3S_VERSION)" \
	K3S_CHANNEL="$(K3S_CHANNEL)" \
	K3S_SERVER_EXTRA_ARGS="$(K3S_SERVER_EXTRA_ARGS)" \
	KUBECONFIG_HELPER="$(KUBECONFIG_HELPER)" \
	MERGE_KUBECONFIG_TO_DEFAULT="$(MERGE_KUBECONFIG_TO_DEFAULT)" \
	SLICER_SWAP_SIZE="$(SLICER_SWAP_SIZE)" \
	IMAGE_LIST_FILE="$(preload_images_file)" \
	LOCAL_IMAGE_CACHE_HOST="$(LOCAL_IMAGE_CACHE_HOST)" \
	LOCAL_IMAGE_CACHE_SCHEME="$(LOCAL_IMAGE_CACHE_SCHEME)" \
	"$(BOOTSTRAP_K3S)"

.PHONY: ensure-host-forwards stop-host-forwards host-forward-status
ensure-host-forwards:
	@set -euo pipefail; \
	socket="$$($(RESOLVE_SOCKET))"; \
	proxy_name="slicer-platform-gateway-443"; \
	proxy_image="platform/slicer-gateway-proxy:dev"; \
	llm_proxy_name="slicer-platform-llm-12434"; \
	llm_proxy_image="platform/slicer-llm-proxy:dev"; \
	tfvar_files=(); \
	if [ -f "$(stage_var_file)" ]; then tfvar_files+=("$(stage_var_file)"); fi; \
	if [ -f "$(target_var_file)" ]; then tfvar_files+=("$(target_var_file)"); fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_BASE_TFVARS}"); fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_TFVARS}"); fi; \
	gateway_public_port="$$( "$(RESOLVE_TFVAR_VALUE)" gateway_https_host_port 443 "$${tfvar_files[@]}" )"; \
	gateway_forward_port="$(SLICER_GATEWAY_HTTPS_FORWARD_PORT)"; \
	llm_gateway_mode="$$( "$(RESOLVE_TFVAR_VALUE)" llm_gateway_mode direct "$${tfvar_files[@]}" )"; \
	SLICER_URL="$$socket" \
	RUN_DIR="$(RUN_DIR)" \
	SLICER_VM_NAME="$(SLICER_VM_NAME)" \
	ARGOCD_NODE_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" argocd_server_node_port 30080 "$${tfvar_files[@]}" )" \
	HUBBLE_NODE_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" hubble_ui_node_port 31235 "$${tfvar_files[@]}" )" \
	GITEA_HTTP_NODE_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" gitea_http_node_port 30090 "$${tfvar_files[@]}" )" \
	GITEA_SSH_NODE_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" gitea_ssh_node_port 30022 "$${tfvar_files[@]}" )" \
	SIGNOZ_LOCAL_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" signoz_ui_host_port 3301 "$${tfvar_files[@]}" )" \
	SIGNOZ_NODE_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" signoz_ui_node_port 30301 "$${tfvar_files[@]}" )" \
	GRAFANA_LOCAL_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" grafana_ui_host_port 3302 "$${tfvar_files[@]}" )" \
	GRAFANA_NODE_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" grafana_ui_node_port 30302 "$${tfvar_files[@]}" )" \
	GATEWAY_HTTPS_FORWARD_PORT="$$gateway_forward_port" \
	GATEWAY_HTTPS_GUEST_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" gateway_https_node_port $(SLICER_GATEWAY_HTTPS_GUEST_PORT) "$${tfvar_files[@]}" )" \
	"$(HOST_FORWARDS)" ensure; \
	if [ "$$gateway_public_port" != "$$gateway_forward_port" ]; then \
		CONTAINER_NAME="$$proxy_name" IMAGE_TAG="$$proxy_image" LISTEN_PORT="$$gateway_public_port" UPSTREAM_PORT="$$gateway_forward_port" "$(HOST_GATEWAY_PROXY)" ensure; \
	else \
		CONTAINER_NAME="$$proxy_name" IMAGE_TAG="$$proxy_image" LISTEN_PORT="$$gateway_public_port" UPSTREAM_PORT="$$gateway_forward_port" "$(HOST_GATEWAY_PROXY)" stop >/dev/null 2>&1 || true; \
	fi; \
	if [ "$$llm_gateway_mode" = "direct" ]; then \
		CONTAINER_NAME="$$llm_proxy_name" IMAGE_TAG="$$llm_proxy_image" LISTEN_PORT="12434" UPSTREAM_PORT="12434" "$(HOST_GATEWAY_PROXY)" ensure; \
	else \
		CONTAINER_NAME="$$llm_proxy_name" IMAGE_TAG="$$llm_proxy_image" LISTEN_PORT="12434" UPSTREAM_PORT="12434" "$(HOST_GATEWAY_PROXY)" stop >/dev/null 2>&1 || true; \
	fi

.PHONY: merge-default-kubeconfig
merge-default-kubeconfig:
	@set -euo pipefail; \
	"$(KUBECONFIG_HELPER)" ensure-valid "$(KUBECONFIG_PATH)"; \
	"$(KUBECONFIG_HELPER)" ensure-valid "$(DEFAULT_KUBECONFIG_PATH)"; \
	"$(KUBECONFIG_HELPER)" merge "$(KUBECONFIG_PATH)" "$(DEFAULT_KUBECONFIG_PATH)" "$(KUBECONFIG_CONTEXT)"; \
	echo "OK   merged $(KUBECONFIG_CONTEXT) into $(DEFAULT_KUBECONFIG_PATH)"

stop-host-forwards:
	@set -euo pipefail; \
	socket="$$($(RESOLVE_SOCKET))"; \
	proxy_name="slicer-platform-gateway-443"; \
	proxy_image="platform/slicer-gateway-proxy:dev"; \
	llm_proxy_name="slicer-platform-llm-12434"; \
	llm_proxy_image="platform/slicer-llm-proxy:dev"; \
	CONTAINER_NAME="$$proxy_name" IMAGE_TAG="$$proxy_image" "$(HOST_GATEWAY_PROXY)" stop >/dev/null 2>&1 || true; \
	CONTAINER_NAME="$$llm_proxy_name" IMAGE_TAG="$$llm_proxy_image" "$(HOST_GATEWAY_PROXY)" stop >/dev/null 2>&1 || true; \
	SLICER_URL="$$socket" RUN_DIR="$(RUN_DIR)" SLICER_VM_NAME="$(SLICER_VM_NAME)" "$(HOST_FORWARDS)" stop

host-forward-status:
	@set -euo pipefail; \
	socket="$$($(RESOLVE_SOCKET))"; \
	proxy_name="slicer-platform-gateway-443"; \
	proxy_image="platform/slicer-gateway-proxy:dev"; \
	llm_proxy_name="slicer-platform-llm-12434"; \
	llm_proxy_image="platform/slicer-llm-proxy:dev"; \
	tfvar_files=(); \
	if [ -f "$(stage_var_file)" ]; then tfvar_files+=("$(stage_var_file)"); fi; \
	if [ -f "$(target_var_file)" ]; then tfvar_files+=("$(target_var_file)"); fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_BASE_TFVARS}"); fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_TFVARS}"); fi; \
	gateway_public_port="$$( "$(RESOLVE_TFVAR_VALUE)" gateway_https_host_port 443 "$${tfvar_files[@]}" )"; \
	gateway_forward_port="$(SLICER_GATEWAY_HTTPS_FORWARD_PORT)"; \
	llm_gateway_mode="$$( "$(RESOLVE_TFVAR_VALUE)" llm_gateway_mode direct "$${tfvar_files[@]}" )"; \
	SLICER_URL="$$socket" RUN_DIR="$(RUN_DIR)" SLICER_VM_NAME="$(SLICER_VM_NAME)" GATEWAY_HTTPS_FORWARD_PORT="$$gateway_forward_port" "$(HOST_FORWARDS)" status; \
	if [ "$$gateway_public_port" != "$$gateway_forward_port" ]; then \
		CONTAINER_NAME="$$proxy_name" IMAGE_TAG="$$proxy_image" LISTEN_PORT="$$gateway_public_port" UPSTREAM_PORT="$$gateway_forward_port" "$(HOST_GATEWAY_PROXY)" status; \
	fi; \
	if [ "$$llm_gateway_mode" = "direct" ]; then \
		CONTAINER_NAME="$$llm_proxy_name" IMAGE_TAG="$$llm_proxy_image" LISTEN_PORT="12434" UPSTREAM_PORT="12434" "$(HOST_GATEWAY_PROXY)" status; \
	fi

.PHONY: ensure-image-cache
ensure-image-cache:
	@CACHE_PUSH_HOST="$(LOCAL_IMAGE_CACHE_PUSH_HOST)" CACHE_CONTAINER_NAME="$(LOCAL_IMAGE_CACHE_CONTAINER)" "$(ENSURE_IMAGE_CACHE)"

.PHONY: check-docker-daemon
check-docker-daemon:
	@set -euo pipefail; \
	command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH"; exit 1; }; \
	if ! docker info >/dev/null 2>&1; then \
		echo "docker daemon not reachable (is Docker Desktop running?)"; \
		exit 1; \
	fi

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
	PRELOAD_LLM_GATEWAY_MODE="$$( "$(RESOLVE_TFVAR_VALUE)" llm_gateway_mode disabled "$${tfvar_files[@]}" )" \
	"$(SCRIPTS_DIR)/sync-local-image-cache.sh"

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
	socket="$$($(RESOLVE_SOCKET))"; \
	echo "=== Slicer daemon ==="; \
	echo "Active endpoint: $$socket"; \
	SLICER_URL="$$socket" slicer info || true; \
	echo ""; \
	echo "=== Slicer VMs ==="; \
	SLICER_URL="$$socket" slicer vm list 2>/dev/null | awk -v vm="$(SLICER_VM_NAME)" 'NR==1 || $$1 == vm || $$1 == "slicer-1" { print }'; \
	if [ -f "$(KUBECONFIG_PATH)" ]; then \
		echo ""; \
		echo "=== k3s nodes ==="; \
		KUBECONFIG="$(KUBECONFIG_PATH)" kubectl get nodes -o wide 2>/dev/null || true; \
	fi; \
	if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then \
		echo ""; \
		echo "=== Local image cache ==="; \
		curl -fsS "http://$(LOCAL_IMAGE_CACHE_PUSH_HOST)/v2/" >/dev/null 2>&1 && echo "OK   registry cache available at http://$(LOCAL_IMAGE_CACHE_PUSH_HOST)/v2/" || echo "WARN registry cache unavailable at http://$(LOCAL_IMAGE_CACHE_PUSH_HOST)/v2/"; \
	fi; \
	echo ""; \
	echo "=== Helper modes ==="; \
	echo "Host forwards: $(SLICER_HOST_FORWARDS_MODE)"; \
	echo "Local image cache: $(PLATFORM_LOCAL_IMAGE_CACHE_MODE)"; \
	echo "Build workload images: $(PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE)"; \
	echo ""; \
	echo "=== Host forwards ==="; \
	$(MAKE) host-forward-status || true

.PHONY: stop-slicer
stop-slicer:
	@set -euo pipefail; \
	socket="$$($(RESOLVE_SOCKET))"; \
	echo "Stopping host forwards (best-effort)..."; \
	$(MAKE) stop-host-forwards >/dev/null 2>&1 || true; \
	echo "OK   host forwards stopped"; \
	if SLICER_URL="$$socket" slicer vm list >/dev/null 2>&1; then \
		status="$$(SLICER_URL="$$socket" slicer vm list --json 2>/dev/null | jq -r --arg vm "$(SLICER_VM_NAME)" '.[] | select(.hostname == $$vm) | .status' | head -n 1 || true)"; \
		if [ "$$status" = "Running" ]; then \
			echo "Requesting pause for $(SLICER_VM_NAME)..."; \
			SLICER_URL="$$socket" slicer vm pause "$(SLICER_VM_NAME)" >/dev/null 2>&1 || true; \
			for _ in $$(seq 1 30); do \
				status="$$(SLICER_URL="$$socket" slicer vm list --json 2>/dev/null | jq -r --arg vm "$(SLICER_VM_NAME)" '.[] | select(.hostname == $$vm) | .status' | head -n 1 || true)"; \
				if [ "$$status" = "Paused" ] || [ "$$status" = "Stopped" ] || [ -z "$$status" ]; then \
					echo "OK   $(SLICER_VM_NAME) is $${status:-absent}"; \
					break; \
				fi; \
				sleep 1; \
			done; \
			if [ "$$status" = "Running" ]; then \
				echo "WARN $(SLICER_VM_NAME) is still Running after pause request"; \
			fi; \
		else \
			echo "OK   $(SLICER_VM_NAME) is $${status:-absent}"; \
		fi; \
	else \
		echo "OK   slicer daemon not reachable at $$socket"; \
	fi; \
	echo "Cleaning any stale repo-managed slicer daemon state (best-effort)..."; \
	RUN_DIR="$(RUN_DIR)" "$(STOP_DAEMON)" >/dev/null 2>&1 || true; \
	echo "OK   stale repo-managed daemon state cleaned"

.PHONY: stop
stop:
	@$(MAKE) stop-slicer

.PHONY: check-vm-health
check-vm-health:
	@socket="$$($(RESOLVE_SOCKET))"; \
	SLICER_URL="$$socket" \
	SLICER_VM_NAME="$(SLICER_VM_NAME)" \
	"$(SCRIPTS_DIR)/check-vm-health.sh"

.PHONY: configure-k3s-apiserver-oidc
configure-k3s-apiserver-oidc:
	@set -euo pipefail; \
	socket="$$($(RESOLVE_SOCKET))"; \
	tfvar_files=(); \
	if [ -f "$(stage_var_file)" ]; then tfvar_files+=("$(stage_var_file)"); fi; \
	if [ -f "$(target_var_file)" ]; then tfvar_files+=("$(target_var_file)"); fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_BASE_TFVARS}"); fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then tfvar_files+=("$${PLATFORM_TFVARS}"); fi; \
	SLICER_URL="$$socket" \
	SLICER_VM_NAME="$(SLICER_VM_NAME)" \
	GATEWAY_HTTPS_HOST_PORT="$$( "$(RESOLVE_TFVAR_VALUE)" gateway_https_host_port 443 "$${tfvar_files[@]}" )" \
	KUBECONFIG="$(KUBECONFIG_PATH)" \
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
	profile_setup_session "slicer" "$(STAGE)" "plan" "$(KUBECONFIG_PATH)" "$(KUBECONFIG_CONTEXT)"; \
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
	if [ "$$stage_num" -ge 500 ]; then \
		$(MAKE) check-platform-env; \
	fi; \
		if [ "$$stage_num" -eq 100 ]; then \
			echo "Stage 100 plan:"; \
			echo "  - ensure Kind and Lima are stopped"; \
			echo "  - preflight target host ports"; \
			echo "  - require a reachable Slicer daemon at $(SLICER_ACTIVE_URL)"; \
			echo "  - ensure $(SLICER_VM_NAME) exists in host group $(SLICER_VM_GROUP)"; \
			echo "  - use networking profile: $(SLICER_NETWORK_PROFILE)"; \
		echo "  - bootstrap or refresh the $(K3SUP_CONTEXT) kubeconfig at $(KUBECONFIG_PATH)"; \
		echo ""; \
			$(MAKE) status || true; \
			exit 0; \
		fi; \
	$(MAKE) check-conflicting-clusters-stopped; \
	$(MAKE) check-kubeconfig >/dev/null; \
	if ! KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null; then \
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
	profile_setup_session "slicer" "$(STAGE)" "apply" "$(KUBECONFIG_PATH)" "$(KUBECONFIG_CONTEXT)"; \
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
	prepare_host_forwards() { \
		local mode="$$1"; local stage_num_local="$$2"; local tmp_log=""; \
		if ! mode_enabled "$$mode" 500 "$$stage_num_local"; then \
			return 0; \
		fi; \
		if [ "$$mode" = "auto" ]; then \
			tmp_log=$$(mktemp); \
			if $(MAKE) check-host-ports >"$$tmp_log" 2>&1; then \
				rm -f "$$tmp_log"; \
				run_step "ensure-host-forwards" $(MAKE) ensure-host-forwards; \
			else \
				cat "$$tmp_log"; \
				rm -f "$$tmp_log"; \
				echo "WARN slicer host forwards unavailable; continuing without localhost forwards because another target already owns those ports."; \
			fi; \
			return 0; \
		fi; \
		run_step "check-host-ports" $(MAKE) check-host-ports; \
		run_step "ensure-host-forwards" $(MAKE) ensure-host-forwards; \
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
		if [ "$(SLICER_HOST_FORWARDS_MODE)" = "on" ]; then \
			run_step "check-host-ports" $(MAKE) check-host-ports; \
		fi; \
		run_step "slicer-vm-up" $(MAKE) slicer-vm-up; \
		run_step "bootstrap-k3s" $(MAKE) bootstrap-k3s; \
		run_step "check-kubeconfig" $(MAKE) check-kubeconfig; \
		exit 0; \
	fi; \
	$(MAKE) check-conflicting-clusters-stopped; \
	$(MAKE) check-kubeconfig >/dev/null; \
	if ! KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null; then \
		echo "$(KUBECONFIG_CONTEXT) not reachable; bootstrapping via STAGE=100"; \
		$(MAKE) apply STAGE=100 AUTO_APPROVE=1 SLICER_ALLOW_EXISTING_K3S=1; \
	fi; \
	prepare_host_forwards "$(SLICER_HOST_FORWARDS_MODE)" "$$stage_num"; \
	if mode_enabled "$(PLATFORM_LOCAL_IMAGE_CACHE_MODE)" 700 "$$stage_num"; then \
		run_step "ensure-image-cache" $(MAKE) ensure-image-cache; \
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
	@set -euo pipefail; \
	mode="$(SLICER_HOST_FORWARDS_MODE)"; \
	stage_num=$$((10#$(STAGE))); \
	case "$$mode" in \
		on) $(MAKE) ensure-host-forwards >/dev/null ;; \
		auto) if [ "$$stage_num" -ge 500 ]; then $(MAKE) ensure-host-forwards >/dev/null; fi ;; \
		off) ;; \
		*) echo "Invalid helper mode: $$mode" >&2; exit 1 ;; \
	esac
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_BASE_TFVARS}"; \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_TFVARS}"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-cluster-health.sh" $$vf

.PHONY: check-security
check-security:
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_BASE_TFVARS}"; \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_TFVARS}"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-security.sh" $$vf

.PHONY: check-gateway-stack
check-gateway-stack:
	@$(MAKE) ensure-host-forwards >/dev/null
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
	@KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-gateway-stack.sh"

.PHONY: check-cluster
check-cluster:
	@$(MAKE) check-platform-env
	@$(MAKE) ensure-host-forwards >/dev/null
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
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
	@$(MAKE) ensure-host-forwards >/dev/null
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_BASE_TFVARS}"; \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_TFVARS}"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-gateway-urls.sh" $$vf

.PHONY: check-app
check-app:
	@$(MAKE) ensure-host-forwards >/dev/null
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
	@set -euo pipefail; \
	if [ -z "$${APP:-}" ]; then echo "Missing APP=... (e.g., APP=signoz)"; exit 1; fi; \
	vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_BASE_TFVARS}"; \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_TFVARS}"; \
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
	@$(MAKE) ensure-host-forwards >/dev/null
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_BASE_TFVARS}"; \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_TFVARS}"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" "$(STACK_DIR)/scripts/check-sso.sh" $$vf

.PHONY: check-sso-e2e
check-sso-e2e:
	@set -euo pipefail; \
	$(MAKE) ensure-host-forwards >/dev/null; \
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
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_BASE_TFVARS}"; \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		vf="$$vf --var-file $${PLATFORM_TFVARS}"; \
	fi; \
	KUBECONFIG="$(KUBECONFIG_PATH)" "$(STACK_DIR)/scripts/check-cluster-health.sh" --show-urls $$vf

.PHONY: reset
reset:
	@set -euo pipefail; \
	socket="$$($(RESOLVE_SOCKET))"; \
	ctx="$${KUBECONFIG_CONTEXT:-$(KUBECONFIG_CONTEXT)}"; \
	state_dir="$(dir $(STATE_FILE))"; \
	reset_incomplete=0; \
	echo "This will:"; \
	if [ "$$socket" = "$(SLICER_SYSTEM_SOCKET)" ]; then \
		echo "  - Stop slicer-mac and remove on-device disk images for $(SLICER_VM_NAME)"; \
	else \
		echo "  - Delete Slicer VM $(SLICER_VM_NAME) if present"; \
	fi; \
	echo "  - Stop conflicting kind/Lima runtimes (best-effort)"; \
	echo "  - Stop host forwards and Docker proxy helpers (best-effort)"; \
	echo "  - Clean any stale repo-managed slicer daemon state from older revisions"; \
	echo "  - Remove kubeconfig context/cluster/user: $$ctx"; \
	echo "  - Remove local terragrunt state: $$state_dir"; \
	echo "  - Clean stack caches (.terraform/.terragrunt-cache)"; \
	echo ""; \
	if [ "$(AUTO_APPROVE)" != "1" ]; then \
		printf "Proceed with Slicer cleanup and local state cleanup? [y/N] "; read -r confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then \
			echo "ABORTED: reset cancelled by user."; \
			exit 0; \
		fi; \
	fi; \
	echo ""; \
	echo "Stopping conflicting platform runtimes (best-effort)..."; \
	"$(STOP_PLATFORM_RUNTIMES)" --exclude slicer; \
	echo "OK   conflicting platform runtimes stopped"; \
	echo ""; \
	echo "Stopping host forwards (best-effort)..."; \
	$(MAKE) stop-host-forwards >/dev/null 2>&1 || true; \
	echo "OK   host forwards stopped"; \
	if command -v docker >/dev/null 2>&1 && ! docker info >/dev/null 2>&1; then \
		echo "WARN Docker is not reachable, so existing Slicer proxy containers, if any, could not be removed."; \
		echo "WARN When Docker is back, rerun: make -C kubernetes/slicer stop-host-forwards"; \
	fi; \
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
	if [ "$$socket" = "$(SLICER_SYSTEM_SOCKET)" ]; then \
		echo "Stopping slicer-mac and pruning on-device disk images (best-effort)..."; \
	else \
		echo "Deleting Slicer VM (best-effort)..."; \
	fi; \
	if ! SLICER_URL="$$socket" SLICER_VM_NAME="$(SLICER_VM_NAME)" "$(DELETE_SLICER_VM)"; then \
		reset_incomplete=1; \
	fi; \
	echo ""; \
	echo "Cleaning any stale repo-managed daemon state (best-effort)..."; \
	RUN_DIR="$(RUN_DIR)" "$(STOP_DAEMON)" >/dev/null 2>&1 || true; \
	echo "OK   stale repo-managed daemon state cleaned"; \
	echo ""; \
	echo "Cleaning local state/caches..."; \
	rm -rf "$(RUN_DIR)" 2>/dev/null || true; \
	rm -rf "$$state_dir" 2>/dev/null || true; \
	rm -rf "$(STACK_DIR)/.terraform" "$(STACK_DIR)/.terragrunt-cache" 2>/dev/null || true; \
	rm -rf "$(STACK_DIR)/.run" 2>/dev/null || true; \
	rm -f "$(STACK_DIR)/backend.tf" 2>/dev/null || true; \
	echo "OK   done"; \
	if [ "$$reset_incomplete" = "1" ]; then \
		echo "WARN reset completed with manual Slicer cleanup still required." >&2; \
		exit 1; \
	fi

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
	@"$(REPO_ROOT)/scripts/audit-shell-scripts.sh"
	@shellcheck \
		"$(MAKEFILE_DIR)scripts/"*.sh \
		"$(STACK_DIR)/scripts/check-cluster-health.sh" \
		"$(STACK_DIR)/scripts/check-version.sh" \
		"$(STACK_DIR)/scripts/check-gateway-urls.sh" \
		"$(STACK_DIR)/scripts/check-sso.sh"

.PHONY: test-bats test-unit
test-bats:
	@bats "$(MAKEFILE_DIR)tests"

test-unit: test-bats

.PHONY: check-version
check-version:
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
	@KUBECONFIG="$(KUBECONFIG_PATH)" STAGES_DIR="$(stage_dir_abs)" TARGET_TFVARS="$(target_var_file)" PRELOAD_IMAGES_FILE="$(preload_images_file)" "$(STACK_DIR)/scripts/check-version.sh"
	@echo ""
	@"$(STACK_DIR)/scripts/check-provider-version.sh"

.PHONY: check-provider-version
check-provider-version:
	@"$(STACK_DIR)/scripts/check-provider-version.sh"
