.DEFAULT_GOAL := help
SHELL := /bin/bash

DRY_RUN ?= 0
REPO_ROOT := $(abspath ../..)
KUBECONFIG_PATH ?= $(HOME)/.kube/kind-kind-local.yaml
KUBECONFIG_CONTEXT ?= kind-kind-local
KIND_CLUSTER_NAME ?= kind-local
APIM_GATEWAY_PORT ?= 8100
FOUNDRY_PORT ?= 8020
MODE_FLAG := $(if $(filter 1,$(DRY_RUN)),--dry-run,--execute)

export KUBECONFIG_PATH KUBECONFIG_CONTEXT KIND_CLUSTER_NAME
export APIM_GATEWAY_PORT FOUNDRY_PORT

.PHONY: help up check down
help:
	@echo "Kind AKS-shaped AI Foundry egress experiment"
	@echo "  make up [DRY_RUN=1]  Start or preview the experiment"
	@echo "  make check           Verify the live brokered request path"
	@echo "  make down [DRY_RUN=1] Remove or preview experiment-owned state"

up:
	@./scripts/up.sh $(MODE_FLAG)

check:
	@./scripts/check.sh --execute

down:
	@./scripts/down.sh $(MODE_FLAG)
