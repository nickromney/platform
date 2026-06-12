# Default dependency update target for app wrappers that declare `update`.
# Included conditionally by mk/app-common.mk so text-driven help only lists
# the target when it is part of the wrapper's declared interface.

##@ Build and test
.PHONY: update
update: ## No dependency locks are managed at this wrapper level
	@echo "$(APP_NAME): Go-only app; no package-manager locks to update"
