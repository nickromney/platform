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

.DEFAULT:
	@set -euo pipefail; \
	echo "Unknown make goal '$@'." >&2; \
	if [ -n "$(strip $(MAKE_SUGGEST_SCRIPT))" ] && [ -x "$(MAKE_SUGGEST_SCRIPT)" ] && [ -n "$(strip $(MAKE_KNOWN_GOALS))" ]; then \
		suggestion="$$( "$(MAKE_SUGGEST_SCRIPT)" "$@" $(MAKE_KNOWN_GOALS) )"; \
		if [ -n "$$suggestion" ]; then \
			echo "$$suggestion" >&2; \
		fi; \
	fi; \
	echo "Run 'make help' for valid targets." >&2; \
	exit 2
