VALID_STAGE_HELPERS ?=
STAGE_WORKFLOW_SUGGEST_GOALS ?= $(VALID_ACTIONS) $(VALID_STAGES)
STAGE_WORKFLOW_USAGE ?= make <stage> <plan|apply> [AUTO_APPROVE=1]
STAGE_WORKFLOW_GUIDE_HELPER ?= $(if $(filter check-security,$(VALID_STAGE_HELPERS)),check-security,$(firstword $(VALID_STAGE_HELPERS)))

STAGE_FROM_GOALS := $(firstword $(filter $(VALID_STAGES),$(MAKECMDGOALS)))
ACTION_FROM_GOALS := $(firstword $(filter $(VALID_ACTIONS),$(MAKECMDGOALS)))
STAGE_HELPER_FROM_GOALS := $(firstword $(filter $(VALID_STAGE_HELPERS),$(MAKECMDGOALS)))
ACTION_COUNT := $(words $(filter $(VALID_ACTIONS),$(MAKECMDGOALS)))
STAGE_HELPER_COUNT := $(words $(filter $(VALID_STAGE_HELPERS),$(MAKECMDGOALS)))
STAGE_DISPATCH_COUNT := $(words $(filter $(strip $(VALID_ACTIONS) $(VALID_STAGE_HELPERS)),$(MAKECMDGOALS)))
STAGE_COUNT := $(words $(filter $(VALID_STAGES),$(MAKECMDGOALS)))
UNKNOWN_WORKFLOW_GOALS := $(filter-out $(MAKE_KNOWN_GOALS),$(MAKECMDGOALS))

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

.PHONY: workflow-validate
workflow-validate:
	@set -euo pipefail; \
	if [ "$(ACTION_COUNT)" -gt 1 ]; then \
		echo "Specify only one workflow action: $(VALID_ACTIONS)" >&2; \
		exit 2; \
	fi; \
	if [ "$(STAGE_HELPER_COUNT)" -gt 1 ]; then \
		echo "Specify only one stage helper: $(VALID_STAGE_HELPERS)" >&2; \
		exit 2; \
	fi; \
	if [ "$(STAGE_DISPATCH_COUNT)" -gt 1 ]; then \
		echo "Specify only one stage workflow goal: $(VALID_ACTIONS) $(VALID_STAGE_HELPERS)" >&2; \
		exit 2; \
	fi; \
	if [ "$(STAGE_COUNT)" -gt 1 ]; then \
		echo "Specify only one stage: $(VALID_STAGES)" >&2; \
		exit 2; \
	fi; \
	if [ -n "$(UNKNOWN_WORKFLOW_GOALS)" ]; then \
		echo "Unknown workflow goal '$(firstword $(UNKNOWN_WORKFLOW_GOALS))'." >&2; \
		suggestion="$$( "$(MAKE_SUGGEST_SCRIPT)" --execute "$(firstword $(UNKNOWN_WORKFLOW_GOALS))" $(STAGE_WORKFLOW_SUGGEST_GOALS) )"; \
		if [ -n "$$suggestion" ]; then \
			echo "$$suggestion" >&2; \
		fi; \
		echo "Use: $(STAGE_WORKFLOW_USAGE)" >&2; \
		exit 2; \
	fi

.PHONY: $(VALID_STAGES)
$(VALID_STAGES): workflow-validate
	@set -euo pipefail; \
	if [ -z "$(ACTION_FROM_GOALS)" ] && [ -z "$(STAGE_HELPER_FROM_GOALS)" ]; then \
		echo "Stage $@ requires an action." >&2; \
		echo "Try: make $@ plan" >&2; \
		echo "  or: make $@ apply AUTO_APPROVE=1" >&2; \
		if [ -n "$(STAGE_WORKFLOW_GUIDE_HELPER)" ]; then \
			echo "  or: make $@ $(STAGE_WORKFLOW_GUIDE_HELPER)" >&2; \
		fi; \
		exit 2; \
	fi
