.DEFAULT_GOAL := help
SHELL := /bin/bash

TG ?= terragrunt
TG_LOG_SHOW_ABS_PATHS ?= true
TG_INIT_FLAGS ?= -reconfigure
STACK_DIR := ../../terraform/kubernetes
STATE_FILE ?= ../../terraform/.run/kubernetes-slicer/terraform.tfstate
TG_STATE_PATH ?= $(abspath $(STATE_FILE))
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
MAKE_SUGGEST_SCRIPT := $(MAKEFILE_DIR)../../scripts/suggest-make-goal.sh
RUN_DIR := $(MAKEFILE_DIR).run
SCRIPTS_DIR := $(MAKEFILE_DIR)scripts
CHECK_STAGE_MONOTONICITY := $(SCRIPTS_DIR)/check-stage-monotonicity.sh
CHECK_KIND_STOPPED := $(MAKEFILE_DIR)../scripts/check-kind-stopped.sh
CHECK_LIMA_STOPPED := $(MAKEFILE_DIR)../scripts/check-lima-stopped.sh
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
RESOLVE_TFVAR_VALUE := $(SCRIPTS_DIR)/resolve-tfvar-value.sh
KUBECONFIG_HELPER := $(STACK_DIR)/scripts/manage-kubeconfig.sh
AUTO_APPROVE ?= 0
DRY_RUN ?= 0
STAGE ?= 100
DEFAULT_KUBECONFIG_PATH ?= $(HOME)/.kube/config
SLICER_SYSTEM_SOCKET ?= $(HOME)/slicer-mac/slicer.sock
SLICER_SOCKET ?= $(SLICER_SYSTEM_SOCKET)
SLICER_CONFIG ?= $(HOME)/slicer-mac/slicer-mac.yaml
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
SLICER_SWAP_SIZE ?= 4G
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
PLATFORM_LOCAL_IMAGE_CACHE_MODE ?= auto
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

VALID_STAGES := 100 200 300 400 500 600 700 800 900
VALID_ACTIONS := plan apply
VALID_SLICER_NETWORK_PROFILES := cilium default
VALID_HELPER_MODES := auto on off
STAGE_FROM_GOALS := $(firstword $(filter $(VALID_STAGES),$(MAKECMDGOALS)))
ACTION_FROM_GOALS := $(firstword $(filter $(VALID_ACTIONS),$(MAKECMDGOALS)))
ACTION_COUNT := $(words $(filter $(VALID_ACTIONS),$(MAKECMDGOALS)))
STAGE_COUNT := $(words $(filter $(VALID_STAGES),$(MAKECMDGOALS)))
MAKE_KNOWN_GOALS := help prepare-state check-stage-monotonicity check-kind-stopped check-lima-stopped check-conflicting-clusters-stopped check-kubeconfig check-host-ports prereqs daemon-up daemon-down slicer-vm-up bootstrap-k3s ensure-host-forwards stop-host-forwards host-forward-status ensure-image-cache sync-image-cache build-workload-images status stop-slicer stop check-vm-health configure-k3s-apiserver-oidc init plan apply check-health check-security check-gateway-stack check-cluster check-gateway-urls check-app check-sso check-sso-e2e gitea-sync launchpad-render show-urls reset env test test-shell test-bats test-unit check-version check-provider-version $(VALID_ACTIONS) $(VALID_STAGES)
UNKNOWN_WORKFLOW_GOALS := $(filter-out $(MAKE_KNOWN_GOALS),$(MAKECMDGOALS))

include ../../mk/common.mk

ifneq ($(STAGE_FROM_GOALS),)
ifneq ($(origin STAGE),command line)
override STAGE := $(STAGE_FROM_GOALS)
endif
endif

STAGE_SPECIFIED := 0
ifneq ($(STAGE_FROM_GOALS),)
STAGE_SPECIFIED := 1
endif
ifeq ($(origin STAGE),command line)
STAGE_SPECIFIED := 1
endif

export KUBECONFIG_PATH
export KUBECONFIG_CONTEXT
export DEFAULT_KUBECONFIG_PATH

ifeq ($(filter $(SLICER_NETWORK_PROFILE),$(VALID_SLICER_NETWORK_PROFILES)),)
$(error Invalid SLICER_NETWORK_PROFILE="$(SLICER_NETWORK_PROFILE)". Expected one of: $(VALID_SLICER_NETWORK_PROFILES))
endif
ifeq ($(filter $(SLICER_HOST_FORWARDS_MODE),$(VALID_HELPER_MODES)),)
$(error Invalid SLICER_HOST_FORWARDS_MODE="$(SLICER_HOST_FORWARDS_MODE)". Expected one of: $(VALID_HELPER_MODES))
endif
ifeq ($(filter $(PLATFORM_LOCAL_IMAGE_CACHE_MODE),$(VALID_HELPER_MODES)),)
$(error Invalid PLATFORM_LOCAL_IMAGE_CACHE_MODE="$(PLATFORM_LOCAL_IMAGE_CACHE_MODE)". Expected one of: $(VALID_HELPER_MODES))
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

RESOLVE_SOCKET = echo "$(SLICER_SYSTEM_SOCKET)"

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
	@echo "  make plan         100|200|300|...|900"
	@echo "  make prereqs"
	@echo "  make reset        [AUTO_APPROVE=1]"
	@echo "  make show-urls"
	@echo "  make slicer-vm-up"
	@echo "  make status"
	@echo "  make stop"
	@echo "  make stop-host-forwards"
	@echo "  make sync-image-cache"
	@echo "  make test"
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
	@echo "Default kubeconfigs:"
	@echo "  slicer -> $(KUBECONFIG_PATH) (merged into $(DEFAULT_KUBECONFIG_PATH) for kubectx)"
	@echo ""
	@echo "Networking profiles:"
	@echo "  SLICER_NETWORK_PROFILE=cilium  -> k3s with flannel disabled, then stages 200/300 add Cilium/Hubble"
	@echo "  SLICER_NETWORK_PROFILE=default -> keep k3s default CNI; stages 200/300 become no-op placeholders"
	@echo "  Switching profiles requires a fresh VM reset; bootstrap refuses in-place flannel/Cilium flips."
	@echo ""
	@echo "Daemon requirement:"
	@echo "  on-device socket        -> $(SLICER_SYSTEM_SOCKET)"
	@echo "  slicer config           -> $(SLICER_CONFIG)"
	@echo "  start manually from     -> ~/slicer-mac"
	@echo ""
	@echo "Local helper modes:"
	@echo "  SLICER_HOST_FORWARDS_MODE=auto|on|off                -> manage localhost forwards for stable localhost URLs/checks (default: auto)"
	@echo "  PLATFORM_LOCAL_IMAGE_CACHE_MODE=auto|on|off          -> manage/sync the host registry cache (default: auto, stage>=700)"
	@echo "  PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE=auto|on|off -> build/push app workload images to the cache (default: auto, stage>=700)"

.PHONY: workflow-validate
workflow-validate:
	@set -euo pipefail; \
	if [ "$(ACTION_COUNT)" -gt 1 ]; then \
		echo "Specify only one workflow action: $(VALID_ACTIONS)" >&2; \
		exit 2; \
	fi; \
	if [ "$(STAGE_COUNT)" -gt 1 ]; then \
		echo "Specify only one stage: $(VALID_STAGES)" >&2; \
		exit 2; \
	fi; \
	if [ -n "$(UNKNOWN_WORKFLOW_GOALS)" ]; then \
		echo "Unknown workflow goal '$(firstword $(UNKNOWN_WORKFLOW_GOALS))'." >&2; \
		suggestion="$$( "$(MAKE_SUGGEST_SCRIPT)" "$(firstword $(UNKNOWN_WORKFLOW_GOALS))" $(VALID_ACTIONS) $(VALID_STAGES) )"; \
		if [ -n "$$suggestion" ]; then \
			echo "$$suggestion" >&2; \
		fi; \
		echo "Use: make <stage> <plan|apply> [AUTO_APPROVE=1]" >&2; \
		exit 2; \
	fi

.PHONY: $(VALID_STAGES)
$(VALID_STAGES): workflow-validate
	@set -euo pipefail; \
	if [ -z "$(ACTION_FROM_GOALS)" ]; then \
		echo "Stage $@ requires an action." >&2; \
		echo "Try: make $@ plan" >&2; \
		echo "  or: make $@ apply AUTO_APPROVE=1" >&2; \
		exit 2; \
	fi

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
	echo "OK   slicer kubeconfig: $(KUBECONFIG_PATH) ($$target_count context(s), current=$$target_current)"

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
	required=(curl docker git jq kubectl slicer slicer-mac ssh-keygen tofu terragrunt); \
	optional=(helm bats kubectx mkcert node npm shellcheck); \
	missing_required=(); \
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
		fi; \
	}; \
	for b in "$${required[@]}"; do check_bin "$$b" 1; done; \
	for b in "$${optional[@]}"; do check_bin "$$b" 0; done; \
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
		exit 1; \
	fi; \
	echo ""; \
	echo "Docker daemon:"; \
	if ! docker info >/dev/null 2>&1; then \
		echo "FAIL docker daemon not reachable (is Docker Desktop running?)"; \
		exit 1; \
	fi; \
	echo "OK   Docker context: $$(docker context show)"; \
	echo ""; \
	$(MAKE) check-conflicting-clusters-stopped; \
	echo ""; \
	echo "Slicer daemon:"; \
	SLICER_URL="$(SLICER_SYSTEM_SOCKET)" slicer info || exit 1; \
	echo ""; \
	echo "Versions:"; \
	docker version --format 'client={{.Client.Version}} server={{.Server.Version}}' 2>/dev/null || true; \
	tofu -version 2>/dev/null | head -n 1 || true; \
	terragrunt --version 2>/dev/null || true; \
	if command -v k3sup >/dev/null 2>&1; then k3sup version 2>/dev/null || true; fi; \
	if command -v k3sup-pro >/dev/null 2>&1; then k3sup-pro version 2>/dev/null || true; fi; \
	echo ""; \
	$(MAKE) check-kubeconfig

.PHONY: daemon-up
daemon-up:
	@mkdir -p "$(RUN_DIR)"; \
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
	"$(ENSURE_SBOX_VM)"

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
	K3S_VERSION="$(K3S_VERSION)" \
	K3S_CHANNEL="$(K3S_CHANNEL)" \
	K3S_SERVER_EXTRA_ARGS="$(K3S_SERVER_EXTRA_ARGS)" \
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

.PHONY: sync-image-cache
sync-image-cache:
	@IMAGE_LIST_FILE="$(preload_images_file)" \
	CACHE_PUSH_HOST="$(LOCAL_IMAGE_CACHE_PUSH_HOST)" \
	OPTIONAL="$(LOCAL_IMAGE_CACHE_OPTIONAL)" \
	LOCAL_IMAGE_CACHE_HOST="$(LOCAL_IMAGE_CACHE_HOST)" \
	"$(SCRIPTS_DIR)/sync-local-image-cache.sh"

.PHONY: build-workload-images
build-workload-images:
	@CACHE_PUSH_HOST="$(LOCAL_IMAGE_CACHE_PUSH_HOST)" \
	IMAGE_NAMESPACE="$(WORKLOAD_IMAGE_NAMESPACE)" \
	TAG="$(WORKLOAD_IMAGE_TAG)" \
	"$(SCRIPTS_DIR)/build-local-workload-images.sh"

.PHONY: status
status:
	@set -euo pipefail; \
	socket="$$($(RESOLVE_SOCKET))"; \
	echo "=== Slicer daemon ==="; \
	echo "Active socket: $$socket"; \
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
	if [ -S "$$socket" ] && SLICER_URL="$$socket" slicer vm list >/dev/null 2>&1; then \
		status="$$(SLICER_URL="$$socket" slicer vm list --json 2>/dev/null | jq -r --arg vm "$(SLICER_VM_NAME)" '.[] | select(.hostname == $$vm) | .status' | head -n 1 || true)"; \
		if [ "$$status" = "Running" ]; then \
			echo "Requesting shutdown for $(SLICER_VM_NAME)..."; \
			SLICER_URL="$$socket" slicer vm shutdown "$(SLICER_VM_NAME)" >/dev/null 2>&1 || true; \
			for _ in $$(seq 1 30); do \
				status="$$(SLICER_URL="$$socket" slicer vm list --json 2>/dev/null | jq -r --arg vm "$(SLICER_VM_NAME)" '.[] | select(.hostname == $$vm) | .status' | head -n 1 || true)"; \
				if [ "$$status" != "Running" ]; then \
					echo "OK   $(SLICER_VM_NAME) is $${status:-absent}"; \
					break; \
				fi; \
				sleep 1; \
			done; \
			if [ "$$status" = "Running" ]; then \
				echo "WARN $(SLICER_VM_NAME) is still Running after shutdown request"; \
			fi; \
		else \
			echo "OK   $(SLICER_VM_NAME) is $${status:-absent}"; \
		fi; \
	else \
		echo "OK   slicer daemon not reachable at $$socket"; \
	fi; \
	echo "Cleaning any stale repo-managed slicer daemon state (best-effort)..."; \
	RUN_DIR="$(RUN_DIR)" "$(STOP_DAEMON)" >/dev/null 2>&1 || true; \
	echo "OK   stale repo-managed daemon state cleaned"; \
	$(MAKE) check-conflicting-clusters-stopped

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
	stage_num=$$((10#$(STAGE))); \
		if [ "$$stage_num" -eq 100 ]; then \
			echo "Stage 100 plan:"; \
			echo "  - ensure Kind and Lima are stopped"; \
			echo "  - preflight target host ports"; \
			echo "  - require the on-device slicer-mac daemon at $(SLICER_SYSTEM_SOCKET)"; \
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
	cd "$(STACK_DIR)" && \
	TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) init $(TG_INIT_FLAGS) && \
	TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) plan $$plan_args

.PHONY: apply
apply: workflow-validate
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Missing $(target_profile_file)"; exit 1; fi
	@if [ -z "$(stage_file)" ] || [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE). Expected one of: $(VALID_STAGES)"; exit 1; fi
	@$(MAKE) check-stage-monotonicity
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
	prepare_host_forwards() { \
		local mode="$$1"; local stage_num_local="$$2"; local tmp_log=""; \
		if ! mode_enabled "$$mode" 500 "$$stage_num_local"; then \
			return 0; \
		fi; \
		if [ "$$mode" = "auto" ]; then \
			tmp_log=$$(mktemp); \
			if $(MAKE) check-host-ports >"$$tmp_log" 2>&1; then \
				rm -f "$$tmp_log"; \
				$(MAKE) ensure-host-forwards; \
			else \
				cat "$$tmp_log"; \
				rm -f "$$tmp_log"; \
				echo "WARN slicer host forwards unavailable; continuing without localhost forwards because another target already owns those ports."; \
			fi; \
			return 0; \
		fi; \
		$(MAKE) check-host-ports; \
		$(MAKE) ensure-host-forwards; \
	}; \
	local_cache_available() { \
		curl -fsS "http://$(LOCAL_IMAGE_CACHE_PUSH_HOST)/v2/" >/dev/null 2>&1; \
	}; \
	stage_num=$$((10#$(STAGE))); \
	if [ "$$stage_num" -eq 100 ]; then \
		$(MAKE) prereqs; \
		if [ "$(SLICER_HOST_FORWARDS_MODE)" = "on" ]; then \
			$(MAKE) check-host-ports; \
		fi; \
		$(MAKE) slicer-vm-up; \
		$(MAKE) bootstrap-k3s; \
			$(MAKE) check-kubeconfig; \
			exit 0; \
		fi; \
	$(MAKE) check-conflicting-clusters-stopped; \
	$(MAKE) check-kubeconfig >/dev/null; \
	if ! KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null; then \
		echo "$(KUBECONFIG_CONTEXT) not reachable; bootstrapping via STAGE=100"; \
		$(MAKE) apply STAGE=100 AUTO_APPROVE=1; \
	fi; \
	prepare_host_forwards "$(SLICER_HOST_FORWARDS_MODE)" "$$stage_num"; \
	if mode_enabled "$(PLATFORM_LOCAL_IMAGE_CACHE_MODE)" 700 "$$stage_num"; then \
		$(MAKE) ensure-image-cache; \
		$(MAKE) sync-image-cache; \
	elif [ "$$stage_num" -ge 700 ] && ! local_cache_available; then \
		echo "Stage $(STAGE) expects workload images from $(LOCAL_IMAGE_CACHE_HOST), but PLATFORM_LOCAL_IMAGE_CACHE_MODE=off and no registry is reachable at http://$(LOCAL_IMAGE_CACHE_PUSH_HOST)/v2/."; \
		echo "Set PLATFORM_LOCAL_IMAGE_CACHE_MODE=on or start a compatible cache manually."; \
		exit 1; \
	fi; \
	if [ "$$stage_num" -ge 700 ] && mode_enabled "$(PLATFORM_BUILD_LOCAL_WORKLOAD_IMAGES_MODE)" 700 "$$stage_num"; then \
		$(MAKE) build-workload-images; \
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
	cd "$(STACK_DIR)" && \
	TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) init $(TG_INIT_FLAGS) && \
	TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) apply $$apply_args

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
	@$(MAKE) ensure-host-forwards >/dev/null
	@$(MAKE) check-kubeconfig >/dev/null
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" KUBECTL_REACHABILITY_ATTEMPTS="$(KUBECTL_REACHABILITY_ATTEMPTS)" KUBECTL_REACHABILITY_DELAY_SECONDS="$(KUBECTL_REACHABILITY_DELAY_SECONDS)" "$(WAIT_FOR_KUBECTL)" >/dev/null
	@KUBECONFIG="$(KUBECONFIG_PATH)" \
		GITEA_USER="gitea-admin" \
		GITEA_PWD="ChangeMe123!" \
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
	$(MAKE) configure-k3s-apiserver-oidc; \
	stage_tfvars="$(abspath $(STAGE_FILE_900))"; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		stage_tfvars="$(stage_var_file)"; \
	fi; \
	STAGE_TFVARS="$$stage_tfvars" "$(MAKEFILE_DIR)/../../tests/kubernetes/sso/run.sh"

.PHONY: gitea-sync
gitea-sync:
	@set -euo pipefail; \
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
	GITEA_PASSWORD="$${GITEA_PASSWORD:-ChangeMe123!}" \
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
	echo "  - Delete Slicer VM $(SLICER_VM_NAME) if present"; \
	echo "  - Stop host forwards"; \
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
	echo "Stopping host forwards (best-effort)..."; \
	$(MAKE) stop-host-forwards >/dev/null 2>&1 || true; \
	echo "OK   host forwards stopped"; \
	echo ""; \
	echo "Cleaning kubeconfig (best-effort)..."; \
	if [ -n "$$ctx" ]; then \
		if [ -e "$(KUBECONFIG_PATH)" ]; then \
			"$(KUBECONFIG_HELPER)" ensure-valid "$(KUBECONFIG_PATH)"; \
			"$(KUBECONFIG_HELPER)" delete-context "$(KUBECONFIG_PATH)" "$$ctx" "$$ctx" "$$ctx" 1; \
			echo "OK   cleaned $$ctx from $(KUBECONFIG_PATH)"; \
		else \
			echo "OK   no kubeconfig file at $(KUBECONFIG_PATH)"; \
		fi; \
		if [ -e "$(DEFAULT_KUBECONFIG_PATH)" ]; then \
			"$(KUBECONFIG_HELPER)" ensure-valid "$(DEFAULT_KUBECONFIG_PATH)"; \
			"$(KUBECONFIG_HELPER)" delete-context "$(DEFAULT_KUBECONFIG_PATH)" "$$ctx" "$$ctx" "$$ctx" 0; \
			echo "OK   cleaned $$ctx from $(DEFAULT_KUBECONFIG_PATH)"; \
		else \
			echo "OK   no kubeconfig file at $(DEFAULT_KUBECONFIG_PATH)"; \
		fi; \
	fi; \
	echo ""; \
	echo "Deleting Slicer VM (best-effort)..."; \
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
		echo "WARN reset completed with manual Slicer VM recycle still required." >&2; \
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
