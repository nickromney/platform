##@ Run
.PHONY: ps
ps: app-common-compose-prereqs ## Show compose container status
	@$(APP_COMPOSE_ENV) $(COMPOSE_CMD) ps
