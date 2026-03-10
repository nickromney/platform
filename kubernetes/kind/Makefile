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
CHECK_STAGE_MONOTONICITY := $(MAKEFILE_DIR)scripts/check-stage-monotonicity.sh
CHECK_KIND_HOST_PORTS := $(MAKEFILE_DIR)scripts/check-kind-host-ports.sh
ENSURE_KIND_KUBECONFIG := $(MAKEFILE_DIR)scripts/ensure-kind-kubeconfig.sh
KUBECONFIG_HELPER := $(STACK_DIR)/scripts/manage-kubeconfig.sh
AUTO_APPROVE ?= 0
DRY_RUN ?= 0
TARGET ?= kind
STAGE ?= 100
DEFAULT_KUBECONFIG_PATH ?= $(HOME)/.kube/config
KIND_KUBECONFIG_CONTEXT ?= kind-kind-local
KIND_KUBECONFIG_PATH ?= $(HOME)/.kube/$(KIND_KUBECONFIG_CONTEXT).yaml

VALID_TARGETS := kind k3s
TARGET_FROM_GOALS := $(firstword $(filter $(VALID_TARGETS),$(MAKECMDGOALS)))
VALID_STAGES := 100 200 300 400 500 600 700 800 900
STAGE_FROM_GOALS := $(firstword $(filter $(VALID_STAGES),$(MAKECMDGOALS)))
ACTION_FROM_GOALS := $(firstword $(filter plan apply,$(MAKECMDGOALS)))
HAS_PLATFORM_GOAL := $(if $(TARGET_FROM_GOALS),1,)

KIND_DISPATCH_TARGET := $(if $(filter apply,$(ACTION_FROM_GOALS)),apply,plan)
K3S_DISPATCH_TARGET := $(if $(filter apply,$(ACTION_FROM_GOALS)),apply-existing,plan-existing)

ifneq ($(TARGET_FROM_GOALS),)
ifneq ($(origin TARGET),command line)
override TARGET := $(TARGET_FROM_GOALS)
endif
endif

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

ifeq ($(TARGET),kind)
KUBECONFIG_PATH ?= $(KIND_KUBECONFIG_PATH)
KUBECONFIG_CONTEXT ?= $(KIND_KUBECONFIG_CONTEXT)
endif

export KUBECONFIG_PATH
export KUBECONFIG_CONTEXT
export DEFAULT_KUBECONFIG_PATH

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
target_profile_file = targets/$(TARGET).tfvars
stage_var_file = $(abspath $(stage_file))
target_var_file = $(abspath $(target_profile_file))

.PHONY: help
help:
	@echo "kind demo (Docker Desktop + kind + Cilium + Argo CD + Gitea + Grafana/Prometheus/Loki)"
	@echo ""
	@echo "Workflow syntax:"
	@echo "  make kind apply 100 AUTO_APPROVE=1"
	@echo "  make kind plan 200"
	@echo "  make k3s plan 100"
	@echo "  make k3s apply 900 AUTO_APPROVE=1"
	@echo ""
	@echo "Targets (workflow syntax above is preferred):"
	@echo "  make apply        900 [AUTO_APPROVE=1]      (or STAGE=900, TARGET=kind|k3s)"
	@echo "  make plan         900                        (or STAGE=900, TARGET=kind|k3s)"
	@echo "  make init"
	@echo "  make check-gateway-urls"
	@echo "  make check-app  APP=signoz [APP_PATH=/metrics-explorer/summary] [EXTENDED=1]"
	@echo "  make check-health"
	@echo "  make check-security                           WireGuard, TLS 1.3, policy enforcement, negative tests"
	@echo "  make check-sso"
	@echo "  make check-sso-e2e                            Browser-based SSO end-to-end app checks (Playwright)"
	@echo "  make check-version"
	@echo "  make discover-images                          Dump images from running cluster"
	@echo "  make docker-health"
	@echo "  make env                                     Show local tool versions + Docker daemon status"
	@echo "  make audit-bootstrap                         Post-bootstrap audit: apps, pods, events, restarts, previous logs"
	@echo "  make gitea-sync                               Sync apps/ + cluster-policies/ into the Gitea policies repo"
	@echo "  make launchpad-render                         Regenerate Grafana launchpad dashboard from inventory"
	@echo "  make preload-images                           Pull + load images into kind"
	@echo "  make preload-images-pull-only                 Warm Docker cache only"
	@echo "  make prereqs"
	@echo "  make check-stage-monotonicity"
	@echo "  make reset        [AUTO_APPROVE=1] [TARGET=kind|k3s]"
	@echo "  make show-urls"
	@echo "  make start-kind"
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
	@echo "  make kind plan 100"
	@echo "  make kind apply 900 AUTO_APPROVE=1"
	@echo "  make k3s plan 100"
	@echo "  make k3s apply 900 AUTO_APPROVE=1"
	@echo ""
	@echo "Existing cluster overrides (k3s target):"
	@echo "  KUBECONFIG_PATH=/path/to/kubeconfig KUBECONFIG_CONTEXT=my-context make k3s apply 900"
	@echo "  make reset TARGET=k3s KUBECONFIG_CONTEXT=my-context K3S_RESET_CMD='limactl delete my-k3s-vm'"
	@echo ""
	@echo "Default kubeconfigs:"
	@echo "  kind -> $(KIND_KUBECONFIG_PATH) (merged into $(DEFAULT_KUBECONFIG_PATH) for kubectx)"
	@echo "  k3s  -> set KUBECONFIG_PATH=/path/to/kubeconfig"

.PHONY: $(VALID_STAGES)
$(VALID_STAGES):
	@:

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
	if [ "$(TARGET)" = "kind" ]; then \
		"$(KUBECONFIG_HELPER)" ensure-valid "$(KUBECONFIG_PATH)"; \
		kind_count=$$("$(KUBECONFIG_HELPER)" count-contexts "$(KUBECONFIG_PATH)"); \
		kind_current=$$(kubectl --kubeconfig "$(KUBECONFIG_PATH)" config current-context 2>/dev/null || true); \
		[ -n "$$kind_current" ] || kind_current="<none>"; \
		echo "OK   kind kubeconfig: $(KUBECONFIG_PATH) ($$kind_count context(s), current=$$kind_current)"; \
	fi

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

.PHONY: kind k3s
kind:
	@set -euo pipefail; \
	if [ -z "$(ACTION_FROM_GOALS)" ]; then \
		echo "Usage: make kind <plan|apply> <stage> [AUTO_APPROVE=1]"; \
		exit 1; \
	fi; \
	$(MAKE) $(KIND_DISPATCH_TARGET) TARGET=kind STAGE="$(STAGE)" AUTO_APPROVE="$(AUTO_APPROVE)"

k3s:
	@set -euo pipefail; \
	if [ -z "$(ACTION_FROM_GOALS)" ]; then \
		echo "Usage: make k3s <plan|apply> <stage> [AUTO_APPROVE=1]"; \
		exit 1; \
	fi; \
	$(MAKE) $(K3S_DISPATCH_TARGET) TARGET=k3s STAGE="$(STAGE)" AUTO_APPROVE="$(AUTO_APPROVE)"

# Backward-compatible aliases.
.PHONY: init-existing plan-existing apply-existing
init-existing:
	@$(MAKE) init TARGET=k3s STAGE="$(STAGE)"

plan-existing:
	@$(MAKE) plan TARGET=k3s STAGE="$(STAGE)"

apply-existing:
	@$(MAKE) apply TARGET=k3s STAGE="$(STAGE)" AUTO_APPROVE="$(AUTO_APPROVE)"

.PHONY: init
init:
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Unknown TARGET=$(TARGET) (missing $(target_profile_file))"; exit 1; fi
	@if [ -n "$(stage_file)" ] && [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE) (missing $(stage_file))"; exit 1; fi
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
plan:
	@:
else
plan:
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Unknown TARGET=$(TARGET)"; exit 1; fi
	@if [ -z "$(stage_file)" ] || [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE)"; exit 1; fi
	@$(MAKE) check-stage-monotonicity
	@if [ "$(TARGET)" = "kind" ]; then $(MAKE) check-docker-daemon && $(MAKE) check-kind-state; fi
	@$(MAKE) check-kubeconfig >/dev/null
	@set -euo pipefail; \
	stage_num=$$((10#$(STAGE))); \
	if [ "$(TARGET)" = "kind" ] && [ "$$stage_num" -ge 200 ]; then \
		if ! command -v kind >/dev/null 2>&1; then \
			echo "kind not found in PATH (required for TARGET=kind STAGE>=200 checks)"; exit 1; \
		fi; \
		if ! kind get clusters 2>/dev/null | grep -qx "kind-local"; then \
			echo "kind-local not found. Run: make kind apply 100 AUTO_APPROVE=1"; \
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
apply:
	@:
else
apply:
	@$(MAKE) prepare-state
	@if [ ! -f "$(target_profile_file)" ]; then echo "Unknown TARGET=$(TARGET)"; exit 1; fi
	@if [ -z "$(stage_file)" ] || [ ! -f "$(stage_file)" ]; then echo "Unknown STAGE=$(STAGE)"; exit 1; fi
	@$(MAKE) check-stage-monotonicity
	@if [ "$(TARGET)" = "kind" ]; then $(MAKE) check-docker-daemon && $(MAKE) check-kind-state; fi
	@$(MAKE) check-kubeconfig >/dev/null
	@set -euo pipefail; \
	stage_num=$$((10#$(STAGE))); \
	cluster_name="$${TARGET_CLUSTER_NAME:-kind-local}"; \
	if [ "$(TARGET)" = "kind" ] && [ "$$stage_num" -gt 200 ]; then \
		if ! command -v kind >/dev/null 2>&1; then \
			echo "kind not found in PATH (required for TARGET=kind STAGE>200 checks)"; exit 1; \
		fi; \
		if ! kind get clusters 2>/dev/null | grep -qx "kind-local"; then \
			echo "kind-local not found; bootstrapping cluster via STAGE=100 (auto-approve)"; \
			$(MAKE) apply TARGET=kind STAGE=100 AUTO_APPROVE=1; \
		fi; \
	fi; \
	if [ "$(TARGET)" = "kind" ] && ! docker ps -a --format '{{.Names}}' | grep -qx "$$cluster_name-control-plane"; then \
		$(MAKE) check-kind-host-ports TARGET=kind STAGE="$(STAGE)"; \
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
		if [ "$(TARGET)" = "kind" ] && [ $$rc -ne 0 ] && grep -qi "certificate signed by unknown authority" "$$tmp_log"; then \
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
	@if [ "$(TARGET)" = "kind" ]; then $(MAKE) ensure-kind-kubeconfig >/dev/null; fi
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
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	"$(STACK_DIR)/scripts/check-security.sh" $$vf

.PHONY: check-cluster
check-cluster:
	"$(STACK_DIR)/scripts/check-cluster.sh"

.PHONY: check-gateway-urls
check-gateway-urls:
	@if [ "$(TARGET)" = "kind" ]; then $(MAKE) ensure-kind-kubeconfig >/dev/null; fi
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	"$(STACK_DIR)/scripts/check-gateway-urls.sh" $$vf

.PHONY: check-app
check-app:
	@if [ "$(TARGET)" = "kind" ]; then $(MAKE) ensure-kind-kubeconfig >/dev/null; fi
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
	@if [ "$(TARGET)" = "kind" ]; then $(MAKE) ensure-kind-kubeconfig >/dev/null; fi
	@vf=""; \
	if [ "$(STAGE_SPECIFIED)" = "1" ] && [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
		vf="--var-file $(stage_var_file)"; \
	fi; \
	"$(STACK_DIR)/scripts/check-sso.sh" $$vf

.PHONY: check-sso-e2e
check-sso-e2e:
	@set -euo pipefail; \
	stage_tfvars=""; \
	if [ -n "$(stage_file)" ] && [ -f "$(stage_file)" ]; then \
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
	if [ "$(DRY_RUN)" = "1" ]; then dry_flag="--dry-run"; fi; \
	GITEA_POLICIES_REMOTE="${GITEA_POLICIES_REMOTE:-http://127.0.0.1:30090/platform/policies.git}" \
	GITEA_BRANCH="${GITEA_BRANCH:-main}" \
	GITEA_USER="${GITEA_USER:-gitea-admin}" \
		GITEA_PASSWORD="${GITEA_PASSWORD:-ChangeMe123!}" \
		GITEA_SYNC_TFVARS_FILE="$(stage_var_file)" \
		STACK_DIR="$$stack_path" \
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

.PHONY: stop-kind
stop-kind:
	@set -euo pipefail; \
	command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH"; exit 1; }; \
	nodes="$$(docker ps -a --format '{{.Names}}' | grep -E '^kind-local-(control-plane|worker([0-9]+)?)$$' || true)"; \
	if [ -z "$$nodes" ]; then \
		echo "No kind-local node containers found."; \
		exit 0; \
	fi; \
	echo "Stopping kind-local node containers..."; \
	docker stop $$nodes >/dev/null; \
	echo "Stopped: $$nodes"

.PHONY: start-kind
start-kind:
	@set -euo pipefail; \
	command -v docker >/dev/null 2>&1 || { echo "docker not found in PATH"; exit 1; }; \
	nodes="$$(docker ps -a --format '{{.Names}}' | grep -E '^kind-local-(control-plane|worker([0-9]+)?)$$' || true)"; \
	if [ -z "$$nodes" ]; then \
		echo "No kind-local node containers found."; \
		exit 1; \
	fi; \
	echo "Starting kind-local node containers..."; \
	docker start $$nodes >/dev/null; \
	KUBECONFIG_PATH="$(KUBECONFIG_PATH)" GLOBAL_KUBECONFIG_PATH="$(DEFAULT_KUBECONFIG_PATH)" KUBECONFIG_HELPER="$(KUBECONFIG_HELPER)" "$(ENSURE_KIND_KUBECONFIG)" || true; \
	echo "Started: $$nodes"; \
	kubectl --kubeconfig "$(DEFAULT_KUBECONFIG_PATH)" --context "$(KUBECONFIG_CONTEXT)" get nodes -o wide || true

.PHONY: prereqs
prereqs:
	@set -euo pipefail; \
	required=(curl docker git kubectl kind ssh tofu terragrunt); \
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
	args=(--cluster kind-local --parallelism 4); \
	if [ -f "$(stage_file)" ]; then \
		args+=(--tfvars "$(abspath $(stage_file))"); \
	fi; \
	"$(STACK_DIR)/scripts/preload-images.sh" "$${args[@]}"

.PHONY: preload-images-pull-only
preload-images-pull-only:
	@set -euo pipefail; \
	args=(--pull-only); \
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
	if [ "$(TARGET)" != "kind" ] && [ "$(TARGET)" != "k3s" ]; then \
		echo "Unknown TARGET=$(TARGET) (expected: kind or k3s)"; \
		exit 1; \
	fi; \
	CLUSTER_NAME="$${TARGET_CLUSTER_NAME:-kind-local}"; \
	if [ "$(TARGET)" = "k3s" ] && [ -z "$${TARGET_CLUSTER_NAME:-}" ]; then \
		CLUSTER_NAME="local-existing"; \
	fi; \
	KUBECONFIG_PATH="$${KUBECONFIG_PATH:-$(KUBECONFIG_PATH)}"; \
	CTX="$${KUBECONFIG_CONTEXT:-}"; \
	if [ "$(TARGET)" = "kind" ] && [ -z "$$CTX" ]; then \
		CTX="kind-$$CLUSTER_NAME"; \
	fi; \
	STATE_DIR="$(dir $(STATE_FILE))"; \
	echo "Target: $(TARGET)"; \
	echo "This will:"; \
	if [ "$(TARGET)" = "kind" ]; then \
		echo "  - Delete kind cluster: $$CLUSTER_NAME"; \
	else \
		echo "  - External cluster teardown (optional): $${K3S_RESET_CMD:-<none>}"; \
		echo "    (or set LIMA_INSTANCE=<name> to run limactl delete <name>)"; \
	fi; \
	if [ -n "$$CTX" ]; then \
		echo "  - Remove kubeconfig context/cluster/user: $$CTX"; \
	else \
		echo "  - Kubeconfig context cleanup: skipped (set KUBECONFIG_CONTEXT to enable)"; \
	fi; \
	echo "  - Remove local terragrunt state: $$STATE_DIR"; \
	echo "  - Clean stack caches (.terraform/.terragrunt-cache)"; \
	echo ""; \
	if [ "$(AUTO_APPROVE)" != "1" ]; then \
		printf "Proceed? [y/N] "; read -r confirm; \
		if [ "$$confirm" != "y" ] && [ "$$confirm" != "Y" ]; then echo "Aborted."; exit 0; fi; \
	fi; \
	echo ""; \
	echo "Cleaning kubeconfig (best-effort)..."; \
	if [ -n "$$CTX" ]; then \
		"$(KUBECONFIG_HELPER)" delete-context "$$KUBECONFIG_PATH" "$$CTX" "$$CTX" "$$CTX" 1; \
		echo "OK   Removed $$CTX from $$KUBECONFIG_PATH (if present)"; \
		"$(KUBECONFIG_HELPER)" delete-context "$(DEFAULT_KUBECONFIG_PATH)" "$$CTX" "$$CTX" "$$CTX" 0; \
		echo "OK   Removed $$CTX from $(DEFAULT_KUBECONFIG_PATH) (if present)"; \
	elif [ -z "$$CTX" ]; then \
		echo "(skipping kubeconfig cleanup; no KUBECONFIG_CONTEXT set)"; \
	else \
		echo "(no kubeconfig at $$KUBECONFIG_PATH)"; \
	fi; \
	echo ""; \
	if [ "$(TARGET)" = "kind" ]; then \
		echo "Deleting kind cluster (best-effort)..."; \
		if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -qx "$$CLUSTER_NAME"; then \
			kind delete cluster --name "$$CLUSTER_NAME"; \
			echo "OK   Deleted $$CLUSTER_NAME"; \
		else \
			echo "(cluster $$CLUSTER_NAME not found)"; \
		fi; \
	else \
		echo "Tearing down external k3s cluster (best-effort)..."; \
		if [ -n "$${K3S_RESET_CMD:-}" ]; then \
			echo "Running K3S_RESET_CMD"; \
			bash -lc "$${K3S_RESET_CMD}" || true; \
		elif [ -n "$${LIMA_INSTANCE:-}" ]; then \
			if command -v limactl >/dev/null 2>&1; then \
				limactl delete "$${LIMA_INSTANCE}" || true; \
			else \
				echo "limactl not found; skipping LIMA_INSTANCE teardown"; \
			fi; \
		else \
			echo "(no external teardown command configured; skipping cluster deletion)"; \
		fi; \
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
	@if [ "$(TARGET)" = "kind" ]; then $(MAKE) ensure-kind-kubeconfig >/dev/null; fi
	@"$(STACK_DIR)/scripts/check-version.sh"

.PHONY: ensure-kind-kubeconfig
ensure-kind-kubeconfig:
	@KUBECONFIG_PATH="$(KUBECONFIG_PATH)" GLOBAL_KUBECONFIG_PATH="$(DEFAULT_KUBECONFIG_PATH)" KUBECONFIG_HELPER="$(KUBECONFIG_HELPER)" "$(ENSURE_KIND_KUBECONFIG)"

.PHONY: audit-bootstrap
audit-bootstrap:
	@if [ "$(TARGET)" = "kind" ]; then $(MAKE) ensure-kind-kubeconfig >/dev/null; fi
	@"$(MAKEFILE_DIR)scripts/audit-bootstrap.sh"
