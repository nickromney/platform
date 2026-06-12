# Compose lifecycle support shared by app wrappers that ship a compose.yml.
# Included by mk/app-common.mk; not meant for direct wrapper includes. This
# file wires compose backend detection and conditionally includes individual
# target files so text-driven help mirrors MAKE_KNOWN_GOALS.

include ../../mk/compose.mk

ifneq ($(filter prereqs down logs ps,$(MAKE_KNOWN_GOALS)),)
include ../../mk/app-common-compose-prereqs-private.mk
endif

ifneq ($(filter prereqs,$(MAKE_KNOWN_GOALS)),)
include ../../mk/app-common-compose-prereqs.mk
endif

ifneq ($(filter compose-smoke,$(MAKE_KNOWN_GOALS)),)
include ../../mk/app-common-compose-smoke.mk
endif

ifneq ($(filter down,$(MAKE_KNOWN_GOALS)),)
include ../../mk/app-common-compose-down.mk
endif

ifneq ($(filter logs,$(MAKE_KNOWN_GOALS)),)
include ../../mk/app-common-compose-logs.mk
endif

ifneq ($(filter ps,$(MAKE_KNOWN_GOALS)),)
include ../../mk/app-common-compose-ps.mk
endif
