##@ Run
.PHONY: logs
logs: app-common-compose-prereqs ## Tail compose logs
	@$(APP_COMPOSE_ENV) $(COMPOSE_CMD) logs -f --tail=200
