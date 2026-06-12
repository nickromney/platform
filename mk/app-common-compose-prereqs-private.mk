.PHONY: app-common-compose-prereqs
app-common-compose-prereqs:
	@$(MAKE) --no-print-directory check-platform-env
	@if [ -n "$(COMPOSE_CMD)" ]; then \
		echo "✓ $(COMPOSE_CMD) found"; \
	else \
		echo "✗ No supported compose backend found"; \
		"$(abspath ../../scripts/install-tool-hints.sh)" --execute --plain docker podman podman-compose | sed 's/^/    /'; \
		exit 1; \
	fi
