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
	@awk 'BEGIN { FS = ":.*## "; section = "Targets"; width = $(MAKE_HELP_WIDTH); count = 0; } \
	function remember_section(name) { \
		if (!(name in seen_section)) { \
			seen_section[name] = 1; \
			order[++count] = name; \
		} \
	} \
	/^##@/ { \
		section = substr($$0, 5); \
		remember_section(section); \
		next; \
	} \
	/^[A-Za-z0-9][A-Za-z0-9_.-]*:.*## / { \
		remember_section(section); \
		lines[section] = lines[section] sprintf("  %-" width "s %s\n", $$1, $$2); \
	} \
	END { \
		for (i = 1; i <= count; i++) { \
			name = order[i]; \
			print name ":"; \
			printf "%s", lines[name]; \
			if (i < count) { \
				printf "\n"; \
			} \
		} \
	}' $(MAKEFILE_LIST)
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
