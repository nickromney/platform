.DEFAULT_GOAL := help
SHELL := /bin/bash

TG ?= terragrunt
TG_LOG_SHOW_ABS_PATHS ?= true
TG_INIT_FLAGS ?= -reconfigure
STACK_DIR := ../../terraform/kubernetes
STATE_FILE ?= ../../terraform/.run/kubernetes/terraform.tfstate
LEGACY_STATE_FILE ?= ../../terraform/.run/platform/terraform.tfstate
TG_STATE_PATH ?= $(abspath $(STATE_FILE))
MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
MAKE_SUGGEST_SCRIPT := $(MAKEFILE_DIR)../../scripts/suggest-make-goal.sh
CHECK_STAGE_MONOTONICITY := $(MAKEFILE_DIR)scripts/check-stage-monotonicity.sh
CHECK_KIND_HOST_PORTS := $(MAKEFILE_DIR)scripts/check-kind-host-ports.sh
CHECK_LIMA_STOPPED := $(MAKEFILE_DIR)../scripts/check-lima-stopped.sh
CHECK_SLICER_STOPPED := $(MAKEFILE_DIR)../scripts/check-slicer-stopped.sh
CHECK_HOST_LLM := $(MAKEFILE_DIR)scripts/check-host-llm.sh
ENSURE_KIND_KUBECONFIG := $(MAKEFILE_DIR)scripts/ensure-kind-kubeconfig.sh
KUBECONFIG_HELPER := $(STACK_DIR)/scripts/manage-kubeconfig.sh
AUTO_APPROVE ?= 0
DRY_RUN ?= 0
STAGE ?= 100
DEFAULT_KUBECONFIG_PATH ?= $(HOME)/.kube/config
KIND_KUBECONFIG_CONTEXT ?= kind-kind-local
KIND_KUBECONFIG_PATH ?= $(HOME)/.kube/$(KIND_KUBECONFIG_CONTEXT).yaml
KIND_PRELOAD_IMAGES_MODE ?= off
KIND_API_READY_ATTEMPTS ?= 30
KIND_API_READY_DELAY_SECONDS ?= 2
KIND_CHECK_LIMA_INSTANCE_PREFIX ?= k3s-node
KIND_CHECK_SLICER_VM_NAME ?= slicer-1
KIND_CHECK_SLICER_SOCKET ?= $(HOME)/slicer-mac/slicer.sock

VALID_TARGETS := kind
TARGET_FROM_GOALS := $(firstword $(filter $(VALID_TARGETS),$(MAKECMDGOALS)))
VALID_STAGES := 100 200 300 400 500 600 700 800 900
VALID_ACTIONS := plan apply
VALID_HELPER_MODES := auto on off
STAGE_FROM_GOALS := $(firstword $(filter $(VALID_STAGES),$(MAKECMDGOALS)))
ACTION_FROM_GOALS := $(firstword $(filter $(VALID_ACTIONS),$(MAKECMDGOALS)))
ACTION_COUNT := $(words $(filter $(VALID_ACTIONS),$(MAKECMDGOALS)))
STAGE_COUNT := $(words $(filter $(VALID_STAGES),$(MAKECMDGOALS)))
HAS_PLATFORM_GOAL := $(if $(TARGET_FROM_GOALS),1,)
MAKE_KNOWN_GOALS := help init prepare-state check-stage-monotonicity check-docker-daemon check-kind-state ensure-kind-running check-kubeconfig check-kind-host-ports check-lima-stopped check-slicer-stopped check-conflicting-clusters-stopped kind plan apply check-health check-security check-gateway-stack check-cluster check-gateway-urls check-app check-sso check-sso-e2e gitea-sync launchpad-render show-urls status docker-health stop-kind stop start-kind start prereqs preload-images preload-images-pull-only discover-images reset env test test-shell test-bats check-version check-provider-version ensure-kind-kubeconfig audit-bootstrap $(VALID_TARGETS) $(VALID_ACTIONS) $(VALID_STAGES)
UNKNOWN_WORKFLOW_GOALS := $(filter-out $(MAKE_KNOWN_GOALS),$(MAKECMDGOALS))

KIND_DISPATCH_TARGET := $(if $(filter apply,$(ACTION_FROM_GOALS)),apply,plan)

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

KUBECONFIG_PATH ?= $(KIND_KUBECONFIG_PATH)
KUBECONFIG_CONTEXT ?= $(KIND_KUBECONFIG_CONTEXT)

export KUBECONFIG_PATH
export KUBECONFIG_CONTEXT
export DEFAULT_KUBECONFIG_PATH

ifeq ($(filter $(KIND_PRELOAD_IMAGES_MODE),$(VALID_HELPER_MODES)),)
$(error Invalid KIND_PRELOAD_IMAGES_MODE="$(KIND_PRELOAD_IMAGES_MODE)". Expected one of: $(VALID_HELPER_MODES))
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
target_profile_file = targets/kind.tfvars
stage_var_file = $(abspath $(stage_file))
target_var_file = $(abspath $(target_profile_file))
preload_images_file = $(abspath $(MAKEFILE_DIR)preload-images.txt)
prereq_llm_stage_file = $(abspath $(if $(filter 1,$(STAGE_SPECIFIED)),$(stage_file),$(STAGE_FILE_900)))

.PHONY: help
help:
	@echo "kind demo (Docker Desktop + kind + Cilium + Argo CD + Gitea + Grafana/Prometheus/Loki)"
	@echo ""
	@echo "Workflow syntax:"
	@echo "  make 100 apply"
	@echo "  make 900 plan"
	@echo "  make 900 apply AUTO_APPROVE=1"
	@echo ""
	@echo "Accepted variants:"
	@echo "  make apply 100"
	@echo "  make kind 100 apply"
	@echo ""
	@echo "Targets (workflow syntax above is preferred):"
	@echo "  make apply        900 [AUTO_APPROVE=1]"
	@echo "  make audit-bootstrap                         Post-bootstrap audit: apps, pods, events, restarts, previous logs"
	@echo "  make check-app  APP=signoz [APP_PATH=/metrics-explorer/summary] [EXTENDED=1]"
	@echo "  make check-gateway-stack                      Gateway CRDs, controller, routes, and control-plane signals"
	@echo "  make check-gateway-urls"
	@echo "  make check-health"
	@echo "  make check-lima-stopped"
	@echo "  make check-provider-version"
	@echo "  make check-security                           WireGuard, TLS 1.3, policy enforcement, negative tests"
	@echo "  make check-slicer-stopped"
	@echo "  make check-sso"
	@echo "  make check-sso-e2e                            Browser-based SSO end-to-end app checks (Playwright)"
	@echo "  make check-stage-monotonicity"
	@echo "  make check-version"
	@echo "  make discover-images                          Dump images from running cluster"
	@echo "  make docker-health"
	@echo "  make env                                     Show local tool versions + Docker daemon status"
	@echo "  make gitea-sync                               Sync apps/ + cluster-policies/ into the Gitea policies repo"
	@echo "  make init"
	@echo "  make launchpad-render                         Regenerate Grafana launchpad dashboard from inventory"
	@echo "  make plan         900"
	@echo "  make preload-images                           Pull + load images into kind"
	@echo "  make preload-images-pull-only                 Warm Docker cache only"
	@echo "  make prereqs"
	@echo "  make reset        [AUTO_APPROVE=1]"
	@echo "  make show-urls"
	@echo "  make status"
	@echo "  make start                                   Alias for start-kind"
	@echo "  make start-kind"
	@echo "  make stop                                    Alias for stop-kind"
	@echo "  make stop-kind"
	@echo "  make test"
	@echo ""
	@echo "Stages:"
	@echo "  100 - cluster"
	@echo "  200 - cilium"
	@echo "  300 - hubble"
	@echo "  400 - argocd core"
	@echo "  500 - gitea + full argocd controllers"
	@echo "  600 - policies"
	@echo "  700 - app repos + actions runner"
	@echo "  800 - observability + headlamp + gateway-tls"
	@echo "  900 - full stack + sso"
	@echo ""
	@echo "Stage examples:"
	@echo "  make 100 plan"
	@echo "  make 900 apply AUTO_APPROVE=1"
	@echo ""
	@echo "Default kubeconfigs:"
	@echo "  kind -> $(KIND_KUBECONFIG_PATH) (merged into $(DEFAULT_KUBECONFIG_PATH) for kubectx)"
	@echo ""
	@echo "Local helper modes:"
	@echo "  KIND_PRELOAD_IMAGES_MODE=auto|on|off                 -> preload images before apply (default: off, current behavior)"

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
		suggestion="$$( "$(MAKE_SUGGEST_SCRIPT)" "$(firstword $(UNKNOWN_WORKFLOW_GOALS))" $(VALID_ACTIONS) $(VALID_TARGETS) $(VALID_STAGES) )"; \
		if [ -n "$$suggestion" ]; then \
			echo "$$suggestion" >&2; \
		fi; \
		echo "Use: make [kind] <stage> <plan|apply> [AUTO_APPROVE=1]" >&2; \
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

.PHONY: check-docker-daemon
check-docker-daemon:
	@set -euo pipefail; \
	command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH"; exit 1; }; \
	if ! docker info >/dev/null 2>&1; then \
		if [ "$$(uname -s)" = "Darwin" ]; then \
			echo "docker daemon not reachable (is Docker Desktop running?)"; \
		else \
			echo "docker daemon not reachable"; \
		fi; \
		exit 1; \
	fi; \
	os="$$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)"; \
	if [ "$$(uname -s)" = "Darwin" ] && ! echo "$$os" | grep -q "Docker Desktop"; then \
		echo "docker is reachable but Docker Desktop was not detected (OperatingSystem=$$os)"; \
	fi

.PHONY: check-kind-state
check-kind-state:
	@set -euo pipefail; \
	$(MAKE) check-docker-daemon >/dev/null; \
	if ! command -v kind >/dev/null 2>&1; then \
		exit 0; \
	fi; \
	if ! kind get clusters 2>/dev/null | grep -qx "kind-local"; then \
		exit 0; \
	fi; \
	if [ ! -f "$(STATE_FILE)" ]; then \
		echo "kind-local exists, but $(STATE_FILE) is missing."; \
		echo "Refusing to apply with no local state for the live cluster."; \
		exit 1; \
	fi; \
	if ! jq -e '.resources[] | select(.type=="kind_cluster" and .name=="local" and (.instances | length) > 0)' "$(STATE_FILE)" >/dev/null 2>&1; then \
		echo "kind-local exists, but $(STATE_FILE) does not contain kind_cluster.local[0]."; \
		if [ -f "$(STATE_FILE).backup" ]; then \
			echo "A backup exists at $(STATE_FILE).backup."; \
		fi; \
		echo "Refusing to apply against a live cluster with truncated state."; \
		exit 1; \
	fi

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
	kind_count=$$("$(KUBECONFIG_HELPER)" count-contexts "$(KUBECONFIG_PATH)"); \
	kind_current=$$(kubectl --kubeconfig "$(KUBECONFIG_PATH)" config current-context 2>/dev/null || true); \
	[ -n "$$kind_current" ] || kind_current="<none>"; \
	echo "OK   kind kubeconfig: $(KUBECONFIG_PATH) ($$kind_count context(s), current=$$kind_current)";

.PHONY: ensure-kind-running
ensure-kind-running:
	@set -euo pipefail; \
	cluster_name="$${TARGET_CLUSTER_NAME:-kind-local}"; \
	control_plane="$$cluster_name-control-plane"; \
	if ! command -v kind >/dev/null 2>&1; then \
		exit 0; \
	fi; \
	if ! kind get clusters 2>/dev/null | grep -qx "$$cluster_name"; then \
		exit 0; \
	fi; \
	if docker ps --format '{{.Names}}' | grep -qx "$$control_plane"; then \
		exit 0; \
	fi; \
	if ! docker ps -a --format '{{.Names}}' | grep -qx "$$control_plane"; then \
		echo "$$cluster_name metadata exists, but $$control_plane is missing." >&2; \
		echo "Run 'make reset AUTO_APPROVE=1' to clean up the stale kind metadata." >&2; \
		exit 1; \
	fi; \
	command -v kubectl >/dev/null 2>&1 || { echo "kubectl not found in PATH"; exit 1; }; \
	$(MAKE) check-kind-host-ports STAGE="$(STAGE)"; \
	echo "$$cluster_name exists but is stopped; starting node containers..."; \
	$(MAKE) start-kind SKIP_KIND_HOST_PORT_CHECK=1 >/dev/null; \
	for _ in $$(seq 1 $(KIND_API_READY_ATTEMPTS)); do \
		if docker ps --format '{{.Names}}' | grep -qx "$$control_plane" && \
		   KUBECONFIG="$(KUBECONFIG_PATH)" kubectl --context "$(KUBECONFIG_CONTEXT)" --request-timeout=5s get --raw=/readyz >/dev/null 2>&1; then \
			echo "$$cluster_name is running again."; \
			exit 0; \
		fi; \
		sleep $(KIND_API_READY_DELAY_SECONDS); \
	done; \
	echo "$$cluster_name started, but the Kubernetes API did not become ready." >&2; \
	exit 1

.PHONY: check-kind-host-ports
check-kind-host-ports:
	@set -euo pipefail; \
	args=(--var-file "$(stage_var_file)" --var-file "$(target_var_file)"); \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		args+=(--var-file "$${PLATFORM_BASE_TFVARS}"); \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		args+=(--var-file "$${PLATFORM_TFVARS}"); \
	fi; \
	"$(CHECK_KIND_HOST_PORTS)" "$${args[@]}"

.PHONY: check-lima-stopped
check-lima-stopped:
	@LIMA_INSTANCE_PREFIX="$(KIND_CHECK_LIMA_INSTANCE_PREFIX)" "$(CHECK_LIMA_STOPPED)"

.PHONY: check-slicer-stopped
check-slicer-stopped:
	@SLICER_URL="$(KIND_CHECK_SLICER_SOCKET)" SLICER_SOCKET="$(KIND_CHECK_SLICER_SOCKET)" SLICER_VM_NAME="$(KIND_CHECK_SLICER_VM_NAME)" "$(CHECK_SLICER_STOPPED)"

.PHONY: check-conflicting-clusters-stopped
check-conflicting-clusters-stopped:
	@$(MAKE) check-lima-stopped
	@$(MAKE) check-slicer-stopped

.PHONY: kind
kind: workflow-validate
	@set -euo pipefail; \
	if [ -z "$(ACTION_FROM_GOALS)" ]; then \
		echo "Usage: make [kind] <stage> <plan|apply> [AUTO_APPROVE=1]"; \
		exit 1; \
	fi; \
	$(MAKE) $(KIND_DISPATCH_TARGET) STAGE="$(STAGE)" AUTO_APPROVE="$(AUTO_APPROVE)"

.PHONY: init
init:
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Missing $(target_profile_file)"; exit 1; fi
	@if [ -n "$(stage_file)" ] && [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE). Expected one of: $(VALID_STAGES)"; exit 1; fi
	@cd "$(STACK_DIR)" && TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) init $(TG_INIT_FLAGS)

.PHONY: prepare-state
prepare-state:
	@set -euo pipefail; \
	if [ -f "$(STATE_FILE)" ]; then \
		exit 0; \
	fi; \
	if [ ! -f "$(LEGACY_STATE_FILE)" ]; then \
		exit 0; \
	fi; \
	echo "Migrating local state layout: $(LEGACY_STATE_FILE) -> $(STATE_FILE)"; \
	mkdir -p "$(dir $(STATE_FILE))"; \
	mv "$(LEGACY_STATE_FILE)" "$(STATE_FILE)"; \
	if [ -f "$(LEGACY_STATE_FILE).backup" ]; then \
		mv "$(LEGACY_STATE_FILE).backup" "$(STATE_FILE).backup"; \
	fi

.PHONY: plan
ifeq ($(HAS_PLATFORM_GOAL),1)
plan: workflow-validate
	@:
else
plan: workflow-validate
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Missing $(target_profile_file)"; exit 1; fi
	@if [ -z "$(stage_file)" ] || [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE). Expected one of: $(VALID_STAGES)"; exit 1; fi
	@$(MAKE) check-stage-monotonicity
	@$(MAKE) check-conflicting-clusters-stopped
	@$(MAKE) check-docker-daemon && $(MAKE) check-kind-state
	@$(MAKE) ensure-kind-running
	@$(MAKE) check-kubeconfig >/dev/null
	@set -euo pipefail; \
	stage_num=$$((10#$(STAGE))); \
	if [ "$$stage_num" -ge 200 ]; then \
		if ! command -v kind >/dev/null 2>&1; then \
			echo "kind not found in PATH (required for STAGE>=200 checks)"; exit 1; \
		fi; \
		if ! kind get clusters 2>/dev/null | grep -qx "kind-local"; then \
			echo "kind-local not found. Run: make 100 apply AUTO_APPROVE=1"; \
			exit 1; \
		fi; \
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
endif

.PHONY: apply
ifeq ($(HAS_PLATFORM_GOAL),1)
apply: workflow-validate
	@:
else
apply: workflow-validate
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Missing $(target_profile_file)"; exit 1; fi
	@if [ -z "$(stage_file)" ] || [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE). Expected one of: $(VALID_STAGES)"; exit 1; fi
	@$(MAKE) check-stage-monotonicity
	@$(MAKE) check-conflicting-clusters-stopped
	@$(MAKE) check-docker-daemon && $(MAKE) check-kind-state
	@$(MAKE) ensure-kind-running
	@$(MAKE) check-kubeconfig >/dev/null
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
	stage_num=$$((10#$(STAGE))); \
	cluster_name="$${TARGET_CLUSTER_NAME:-kind-local}"; \
	if [ "$$stage_num" -gt 200 ]; then \
		if ! command -v kind >/dev/null 2>&1; then \
			echo "kind not found in PATH (required for STAGE>200 checks)"; exit 1; \
		fi; \
		if ! kind get clusters 2>/dev/null | grep -qx "kind-local"; then \
			echo "kind-local not found; bootstrapping cluster via STAGE=100 (auto-approve)"; \
			$(MAKE) apply STAGE=100 AUTO_APPROVE=1; \
		fi; \
	fi; \
	if ! docker ps -a --format '{{.Names}}' | grep -qx "$$cluster_name-control-plane"; then \
		$(MAKE) check-kind-host-ports STAGE="$(STAGE)"; \
	fi; \
	if mode_enabled "$(KIND_PRELOAD_IMAGES_MODE)" 200 "$$stage_num"; then \
		$(MAKE) preload-images STAGE="$(STAGE)"; \
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
	run_apply() { \
		cd "$(STACK_DIR)" && \
		TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) init $(TG_INIT_FLAGS) && \
		TG_STATE_PATH="$(TG_STATE_PATH)" TG_LOG_SHOW_ABS_PATHS=$(TG_LOG_SHOW_ABS_PATHS) $(TG) apply $$apply_args; \
	}; \
	tmp_log=$$(mktemp); \
	set +e; \
	run_apply 2>&1 | tee "$$tmp_log"; \
	rc=$${PIPESTATUS[0]}; \
	set -e; \
		if [ $$rc -ne 0 ] && grep -qi "certificate signed by unknown authority" "$$tmp_log"; then \
			echo "Detected kubeconfig CA mismatch; refreshing kind kubeconfig and retrying once..."; \
			KUBECONFIG_PATH="$(KUBECONFIG_PATH)" GLOBAL_KUBECONFIG_PATH="$(DEFAULT_KUBECONFIG_PATH)" KUBECONFIG_HELPER="$(KUBECONFIG_HELPER)" "$(ENSURE_KIND_KUBECONFIG)"; \
			set +e; \
			run_apply 2>&1 | tee "$$tmp_log"; \
			rc=$${PIPESTATUS[0]}; \
		set -e; \
	fi; \
	rm -f "$$tmp_log"; \
	exit $$rc
endif
.PHONY: check-health
check-health:
	@$(MAKE) ensure-kind-kubeconfig >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	"$(STACK_DIR)/scripts/check-cluster-health.sh" $$vf

.PHONY: check-security
check-security:
	@$(MAKE) ensure-kind-kubeconfig >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	if [ -f "$(target_var_file)" ]; then \
		vf="$$vf --var-file $(target_var_file)"; \
	fi; \
	"$(STACK_DIR)/scripts/check-security.sh" $$vf

.PHONY: check-gateway-stack
check-gateway-stack:
	@$(MAKE) ensure-kind-kubeconfig >/dev/null
	@"$(STACK_DIR)/scripts/check-gateway-stack.sh"

.PHONY: check-cluster
check-cluster:
	"$(STACK_DIR)/scripts/check-cluster.sh"

.PHONY: check-gateway-urls
check-gateway-urls:
	@$(MAKE) ensure-kind-kubeconfig >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	"$(STACK_DIR)/scripts/check-gateway-urls.sh" $$vf

.PHONY: check-app
check-app:
	@$(MAKE) ensure-kind-kubeconfig >/dev/null
	@set -euo pipefail; \
	if [ -z "$${APP:-}" ]; then echo "Missing APP=... (e.g., APP=signoz)"; exit 1; fi; \
	vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	path_flag=""; \
	if [ -n "$${APP_PATH:-}" ]; then path_flag="--path $${APP_PATH}"; fi; \
	host_flag=""; \
	if [ -n "$${HOST:-}" ]; then host_flag="--host $${HOST}"; fi; \
	ext_flag=""; \
	if [ "$${EXTENDED:-0}" = "1" ]; then ext_flag="--extended"; fi; \
	"$(STACK_DIR)/scripts/check-app.sh" $$vf --app "$${APP}" $$host_flag $$path_flag $$ext_flag

.PHONY: check-sso
check-sso:
	@$(MAKE) ensure-kind-kubeconfig >/dev/null
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	KUBECONFIG_CONTEXT="$(KUBECONFIG_CONTEXT)" "$(STACK_DIR)/scripts/check-sso.sh" $$vf

.PHONY: check-sso-e2e
check-sso-e2e:
	@set -euo pipefail; \
	$(MAKE) ensure-kind-kubeconfig >/dev/null; \
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
	GITEA_LOCAL_ACCESS_MODE="$${GITEA_LOCAL_ACCESS_MODE:-nodeport}" \
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
	"$(STACK_DIR)/scripts/check-cluster-health.sh" --show-urls $$vf

.PHONY: docker-health
docker-health:
	@command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH"; exit 1; }
	@echo "Docker context:" && docker context show
	@echo "" && echo "Docker version:" && docker version
	@echo "" && echo "Kind containers (if any):" && (docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -E '(^NAMES|kind-local|kindest/node)' || true)
	@echo "" && echo "Kind networks (if any):" && (docker network ls --format 'table {{.Name}}\t{{.Driver}}' | grep -E '(^NAME|kind)' || true)

.PHONY: status
status:
	@set -euo pipefail; \
	$(MAKE) prepare-state >/dev/null; \
	$(MAKE) check-docker-daemon >/dev/null; \
	echo "=== Docker context ==="; \
	docker context show; \
	echo ""; \
	echo "=== kind clusters ==="; \
	if command -v kind >/dev/null 2>&1; then \
		clusters="$$(kind get clusters 2>/dev/null || true)"; \
		if [ -n "$$clusters" ]; then \
			printf '%s\n' "$$clusters"; \
		else \
			echo "No kind clusters found."; \
		fi; \
	else \
		echo "kind not found in PATH."; \
	fi; \
	echo ""; \
	echo "=== kind containers ==="; \
	containers="$$(docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E '^kind-local-(control-plane|worker([0-9]+)?)\t' || true)"; \
	if [ -n "$$containers" ]; then \
		printf 'NAME\tSTATUS\tPORTS\n%s\n' "$$containers"; \
	else \
		echo "No kind-local node containers found."; \
	fi; \
	if docker ps --format '{{.Names}}' | grep -qx 'kind-local-control-plane'; then \
		$(MAKE) ensure-kind-kubeconfig >/dev/null; \
		echo ""; \
		echo "=== Kubernetes nodes ==="; \
		KUBECONFIG="$(KUBECONFIG_PATH)" kubectl get nodes -o wide || true; \
		echo ""; \
		echo "=== Kubeconfig ==="; \
		$(MAKE) check-kubeconfig; \
	elif command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "kind-local"; then \
		echo ""; \
		echo "kind-local metadata exists, but the control-plane container is not running."; \
	fi

.PHONY: stop-kind
stop-kind:
	@set -euo pipefail; \
	command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH"; exit 1; }; \
	nodes="$$(docker ps -a --format '{{.Names}}' | grep -E '^kind-local-(control-plane|worker([0-9]+)?)$$' || true)"; \
	if [ -z "$$nodes" ]; then \
		echo "No kind-local node containers found."; \
	else \
		echo "Stopping kind-local node containers..."; \
		docker stop $$nodes >/dev/null; \
		echo "Stopped: $$nodes"; \
	fi; \
	$(MAKE) check-conflicting-clusters-stopped

.PHONY: stop
stop:
	@$(MAKE) stop-kind

.PHONY: start-kind
start-kind:
	@set -euo pipefail; \
	$(MAKE) check-conflicting-clusters-stopped; \
	command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH"; exit 1; }; \
	nodes="$$(docker ps -a --format '{{.Names}}' | grep -E '^kind-local-(control-plane|worker([0-9]+)?)$$' || true)"; \
	if [ -z "$$nodes" ]; then \
		echo "No kind-local node containers found."; \
		exit 1; \
	fi; \
	if [ "$${SKIP_KIND_HOST_PORT_CHECK:-0}" != "1" ]; then \
		$(MAKE) check-kind-host-ports STAGE="$(STAGE)"; \
	fi; \
	echo "Starting kind-local node containers..."; \
	docker start $$nodes >/dev/null; \
	KUBECONFIG_PATH="$(KUBECONFIG_PATH)" GLOBAL_KUBECONFIG_PATH="$(DEFAULT_KUBECONFIG_PATH)" KUBECONFIG_HELPER="$(KUBECONFIG_HELPER)" "$(ENSURE_KIND_KUBECONFIG)" || true; \
	echo "Started: $$nodes"; \
	kubectl --kubeconfig "$(DEFAULT_KUBECONFIG_PATH)" --context "$(KUBECONFIG_CONTEXT)" get nodes -o wide || true

.PHONY: start
start:
	@$(MAKE) start-kind

.PHONY: prereqs
prereqs:
	@set -euo pipefail; \
	required=(curl docker git jq kubectl kind ssh tofu terragrunt); \
	optional=(helm cilium hubble kubectx mkcert); \
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
	if [ $${#missing_required[@]} -gt 0 ]; then \
		echo ""; \
		echo "Missing required tools: $${missing_required[*]}"; \
		exit 1; \
	fi; \
	if command -v mkcert >/dev/null 2>&1; then \
		CAROOT=$$(mkcert -CAROOT 2>/dev/null || true); \
		if [ -n "$$CAROOT" ] && [ -f "$$CAROOT/rootCA.pem" ] && [ -f "$$CAROOT/rootCA-key.pem" ]; then \
			echo "OK   mkcert CA installed ($$CAROOT)"; \
		else \
			echo "WARN mkcert found but local CA not installed (run: mkcert -install)"; \
		fi; \
	fi; \
	echo ""; \
	echo "Docker daemon / Desktop:"; \
	if ! docker info >/dev/null 2>&1; then \
		echo "FAIL docker daemon not reachable (is Docker Desktop running?)"; \
		exit 1; \
	fi; \
	os=$$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true); \
	if echo "$$os" | grep -q "Docker Desktop"; then \
		echo "OK   Docker Desktop detected"; \
	else \
		if [ "$$(uname -s)" = "Linux" ]; then \
			echo "OK   Docker Engine detected (Linux; Docker Desktop not required)"; \
		else \
			echo "WARN Docker Desktop not detected (OperatingSystem=$$os)"; \
		fi; \
	fi; \
	echo "OK   Docker context: $$(docker context show)"; \
	echo ""; \
	$(MAKE) check-conflicting-clusters-stopped; \
	echo ""; \
	echo "Host-side LLM:"; \
	args=(--var-file "$(prereq_llm_stage_file)" --var-file "$(target_var_file)"); \
	if [ -n "$${PLATFORM_BASE_TFVARS:-}" ] && [ -f "$${PLATFORM_BASE_TFVARS}" ]; then \
		args+=(--var-file "$${PLATFORM_BASE_TFVARS}"); \
	fi; \
	if [ -n "$${PLATFORM_TFVARS:-}" ] && [ -f "$${PLATFORM_TFVARS}" ]; then \
		args+=(--var-file "$${PLATFORM_TFVARS}"); \
	fi; \
	"$(CHECK_HOST_LLM)" "$${args[@]}"; \
	echo ""; \
	echo "Versions:"; \
	docker version --format 'client={{.Client.Version}} server={{.Server.Version}}' 2>/dev/null || true; \
	kubectl version --client --output=yaml 2>/dev/null | sed -n '1,12p' || true; \
	kind --version 2>/dev/null || true; \
	tofu -version 2>/dev/null | head -n 1 || true; \
	terragrunt --version 2>/dev/null || true; \
	echo ""; \
	$(MAKE) check-kubeconfig

.PHONY: preload-images
preload-images:
	@set -euo pipefail; \
	args=(--cluster kind-local --parallelism 4 --image-list "$(preload_images_file)"); \
	if [ -f "$(stage_file)" ]; then \
		args+=(--tfvars "$(abspath $(stage_file))"); \
	fi; \
	"$(STACK_DIR)/scripts/preload-images.sh" "$${args[@]}"

.PHONY: preload-images-pull-only
preload-images-pull-only:
	@set -euo pipefail; \
	args=(--pull-only --image-list "$(preload_images_file)"); \
	if [ -f "$(stage_file)" ]; then \
		args+=(--tfvars "$(abspath $(stage_file))"); \
	fi; \
	"$(STACK_DIR)/scripts/preload-images.sh" "$${args[@]}"

.PHONY: discover-images
discover-images:
	@"$(STACK_DIR)/scripts/preload-images.sh" --discover

.PHONY: reset
reset:
	@set -euo pipefail; \
	CLUSTER_NAME="$${TARGET_CLUSTER_NAME:-kind-local}"; \
	KUBECONFIG_PATH="$${KUBECONFIG_PATH:-$(KUBECONFIG_PATH)}"; \
	CTX="$${KUBECONFIG_CONTEXT:-}"; \
	CLUSTER_EXISTS=0; \
	if [ -z "$$CTX" ]; then \
		CTX="kind-$$CLUSTER_NAME"; \
	fi; \
	STATE_DIR="$(dir $(STATE_FILE))"; \
	echo "This will:"; \
	echo "  - Delete kind cluster: $$CLUSTER_NAME"; \
	if [ -n "$$CTX" ]; then \
		echo "  - Remove kubeconfig context/cluster/user: $$CTX"; \
	else \
		echo "  - Kubeconfig context cleanup: skipped (set KUBECONFIG_CONTEXT to enable)"; \
	fi; \
	echo "  - Remove local terragrunt state: $$STATE_DIR"; \
	echo "  - Clean stack caches (.terraform/.terragrunt-cache)"; \
	echo ""; \
	echo "Preflight:"; \
	echo "  - Checking Docker daemon / Docker Desktop"; \
	if ! $(MAKE) check-docker-daemon; then \
		echo ""; \
		echo "FAIL reset cannot continue because Docker is not reachable."; \
		echo "kind clusters are Docker containers, so reset cannot delete or inspect them while the daemon is down."; \
		echo "Start Docker Desktop and rerun: make reset AUTO_APPROVE=1"; \
		exit 1; \
	fi; \
	echo "  - Docker daemon reachable"; \
	if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$$CLUSTER_NAME"; then \
		CLUSTER_EXISTS=1; \
		echo "  - kind cluster '$$CLUSTER_NAME' exists and will be deleted"; \
	else \
		echo "  - kind cluster '$$CLUSTER_NAME' does not exist"; \
		echo "    reset can still remove kubeconfig entries and local Terraform state"; \
	fi; \
	echo ""; \
	if [ "$(AUTO_APPROVE)" != "1" ]; then \
		if [ "$$CLUSTER_EXISTS" = "1" ]; then \
			printf "Proceed with cluster deletion, kubeconfig cleanup, and local state cleanup? [y/N] "; read -r confirm; \
			if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then echo "ABORTED: reset cancelled by user at the confirmation prompt. Docker preflight passed, and the kind cluster was left untouched. No kubeconfig or local state changes were made."; exit 0; fi; \
		else \
			printf "Proceed with kubeconfig cleanup and local state cleanup? [y/N] "; read -r confirm; \
			if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then echo "ABORTED: reset cancelled by user at the confirmation prompt. Docker preflight passed. No kubeconfig or local state changes were made."; exit 0; fi; \
		fi; \
	fi; \
	echo ""; \
	echo "Cleaning kubeconfig (best-effort)..."; \
	if [ -n "$$CTX" ]; then \
		if [ -e "$$KUBECONFIG_PATH" ]; then \
			"$(KUBECONFIG_HELPER)" ensure-valid "$$KUBECONFIG_PATH"; \
			if KUBECONFIG="$$KUBECONFIG_PATH" kubectl config get-contexts "$$CTX" >/dev/null 2>&1; then \
				local_ctx_found=1; \
			else \
				local_ctx_found=0; \
			fi; \
			"$(KUBECONFIG_HELPER)" delete-context "$$KUBECONFIG_PATH" "$$CTX" "$$CTX" "$$CTX" 1; \
			if [ "$$local_ctx_found" = "1" ]; then \
				echo "OK   Removed $$CTX from $$KUBECONFIG_PATH"; \
			else \
				echo "OK   No $$CTX entry found in $$KUBECONFIG_PATH"; \
			fi; \
		else \
			echo "OK   No kubeconfig file at $$KUBECONFIG_PATH"; \
		fi; \
		if [ -e "$(DEFAULT_KUBECONFIG_PATH)" ]; then \
			"$(KUBECONFIG_HELPER)" ensure-valid "$(DEFAULT_KUBECONFIG_PATH)"; \
			if KUBECONFIG="$(DEFAULT_KUBECONFIG_PATH)" kubectl config get-contexts "$$CTX" >/dev/null 2>&1; then \
				global_ctx_found=1; \
			else \
				global_ctx_found=0; \
			fi; \
			"$(KUBECONFIG_HELPER)" delete-context "$(DEFAULT_KUBECONFIG_PATH)" "$$CTX" "$$CTX" "$$CTX" 0; \
			if [ "$$global_ctx_found" = "1" ]; then \
				echo "OK   Removed $$CTX from $(DEFAULT_KUBECONFIG_PATH)"; \
			else \
				echo "OK   No $$CTX entry found in $(DEFAULT_KUBECONFIG_PATH)"; \
			fi; \
		else \
			echo "OK   No kubeconfig file at $(DEFAULT_KUBECONFIG_PATH)"; \
		fi; \
	elif [ -z "$$CTX" ]; then \
		echo "(skipping kubeconfig cleanup; no KUBECONFIG_CONTEXT set)"; \
	else \
		echo "(no kubeconfig at $$KUBECONFIG_PATH)"; \
	fi; \
	echo ""; \
	echo "Deleting kind cluster (best-effort)..."; \
	if [ "$$CLUSTER_EXISTS" = "1" ]; then \
		kind delete cluster --name "$$CLUSTER_NAME"; \
		echo "OK   Deleted $$CLUSTER_NAME"; \
	else \
		echo "OK   Cluster $$CLUSTER_NAME was already absent"; \
	fi; \
	echo ""; \
	echo "Cleaning local state/caches..."; \
	rm -rf "$$STATE_DIR" 2>/dev/null || true; \
	rm -rf "$(STACK_DIR)/.terraform" "$(STACK_DIR)/.terragrunt-cache" 2>/dev/null || true; \
	rm -rf "$(STACK_DIR)/.run" 2>/dev/null || true; \
	rm -f "$(STACK_DIR)/kind-config.yaml" "$(STACK_DIR)/backend.tf" 2>/dev/null || true; \
	echo "OK   Done"

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
		"$(STACK_DIR)/scripts/check-version.sh"

.PHONY: test-bats
test-bats:
	@bats "$(MAKEFILE_DIR)tests"

.PHONY: check-version
check-version:
	@$(MAKE) ensure-kind-kubeconfig >/dev/null
	@PRELOAD_IMAGES_FILE="$(preload_images_file)" "$(STACK_DIR)/scripts/check-version.sh"
	@echo ""
	@"$(STACK_DIR)/scripts/check-provider-version.sh"

.PHONY: check-provider-version
check-provider-version:
	@"$(STACK_DIR)/scripts/check-provider-version.sh"

.PHONY: ensure-kind-kubeconfig
ensure-kind-kubeconfig:
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" GLOBAL_KUBECONFIG_PATH="$(DEFAULT_KUBECONFIG_PATH)" KUBECONFIG_HELPER="$(KUBECONFIG_HELPER)" "$(ENSURE_KIND_KUBECONFIG)"

.PHONY: audit-bootstrap
audit-bootstrap:
	@$(MAKE) ensure-kind-kubeconfig >/dev/null
	@"$(MAKEFILE_DIR)scripts/audit-bootstrap.sh"
