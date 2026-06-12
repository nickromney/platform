# Shared app wrapper module for apps/<name>/Makefile entrypoints.
#
# A wrapper declares its goal surface first, then includes this module:
#
#   MAKE_KNOWN_GOALS := help prereqs build test update ...
#   include ../../mk/app-common.mk
#
# MAKE_KNOWN_GOALS is the wrapper's declared interface: it drives unknown-goal
# suggestions, apps/ aggregator discovery, and the make target surface audit.
#
# Optional wrapper inputs:
#   APP_NAME               wrapper name used in messages (default: directory name)
#   APP_COMPOSE_ENV        env prefix for the shared compose lifecycle recipes
#   APP_COMPOSE_DOWN_ARGS  extra compose args for down (for example --profile sso)
#   APP_LOCAL_PLATFORM     override the detected linux/arm64 or linux/amd64
#
# Wrappers get declared app-core delegation targets through
# mk/app-common-core.mk. Wrappers with a compose.yml get prereqs,
# compose-smoke, down, logs, and ps. Targets that genuinely differ per app
# (up*, urls, test, build, app-run*, app-prereqs, compose-smoke-sso) stay in
# the wrapper.

ifeq ($(strip $(MAKE_KNOWN_GOALS)),)
$(error MAKE_KNOWN_GOALS must list the wrapper goals before including mk/app-common.mk)
endif

USE_COMMON_HELP := 1
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

include ../../mk/common.mk

APP_NAME ?= $(notdir $(patsubst %/,%,$(CURDIR)))

REPO_ROOT := $(abspath $(CURDIR)/../..)
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
PLATFORM_DEMO_PASSWORD ?= local-dev-password
OAUTH2_PROXY_COOKIE_SECRET ?= 0123456789abcdef0123456789abcdef

export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE
export PLATFORM_DEMO_PASSWORD
export OAUTH2_PROXY_COOKIE_SECRET

HOST_ARCH := $(shell uname -m)
ifeq ($(HOST_ARCH),arm64)
APP_LOCAL_PLATFORM ?= linux/arm64
else ifeq ($(HOST_ARCH),aarch64)
APP_LOCAL_PLATFORM ?= linux/arm64
else
APP_LOCAL_PLATFORM ?= linux/amd64
endif
ifeq ($(APP_LOCAL_PLATFORM),linux/arm64)
APP_GOARCH := arm64
else
APP_GOARCH := amd64
endif

APP_HAS_COMPOSE ?= $(if $(wildcard $(CURDIR)/compose.yml),1,0)

include ../../mk/app-common-core.mk

# The compose lifecycle targets live in a separate include so the text-driven
# help only lists them for wrappers that actually define them.
ifeq ($(APP_HAS_COMPOSE),1)
include ../../mk/app-common-compose.mk
endif

ifneq ($(filter update,$(MAKE_KNOWN_GOALS)),)
include ../../mk/app-common-update.mk
endif
