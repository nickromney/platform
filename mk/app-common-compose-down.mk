##@ Run
.PHONY: down
down: app-common-compose-prereqs ## Stop the compose stack
	@$(APP_COMPOSE_ENV) $(COMPOSE_CMD) $(APP_COMPOSE_DOWN_ARGS) down --remove-orphans
