COMPOSE_BACKEND_SCRIPT ?= $(abspath $(CURDIR)/../..)/scripts/compose-backend.sh
COMPOSE_CMD ?= $(shell if [ -x "$(COMPOSE_BACKEND_SCRIPT)" ]; then "$(COMPOSE_BACKEND_SCRIPT)" --print --execute; fi)
