K8S_IDP_RUNTIME ?= local
IDP_PREVIEW_ACTION_CATALOG ?= $(REPO_ROOT)/kubernetes/scripts/idp-preview-action-catalog.sh

.PHONY: idp-api
idp-api:
	@if [ "$(DRY_RUN)" = "1" ]; then \
		"$(IDP_PREVIEW_ACTION_CATALOG)" --dry-run-message idp-api --runtime "$(K8S_IDP_RUNTIME)" --idp-public-url "$(IDP_PUBLIC_URL)" --idp-api-public-url "$(IDP_API_PUBLIC_URL)"; \
	else \
		"$(IDP_PREVIEW_ACTION_CATALOG)" --run-command idp-api --runtime "$(K8S_IDP_RUNTIME)" --repo-root "$(REPO_ROOT)" --idp-public-url "$(IDP_PUBLIC_URL)" --idp-api-public-url "$(IDP_API_PUBLIC_URL)"; \
	fi

.PHONY: backstage
backstage:
	@if [ "$(DRY_RUN)" = "1" ]; then \
		"$(IDP_PREVIEW_ACTION_CATALOG)" --dry-run-message backstage --runtime "$(K8S_IDP_RUNTIME)" --idp-public-url "$(IDP_PUBLIC_URL)" --idp-api-public-url "$(IDP_API_PUBLIC_URL)"; \
	else \
		"$(IDP_PREVIEW_ACTION_CATALOG)" --run-command backstage --runtime "$(K8S_IDP_RUNTIME)" --repo-root "$(REPO_ROOT)" --idp-public-url "$(IDP_PUBLIC_URL)" --idp-api-public-url "$(IDP_API_PUBLIC_URL)"; \
	fi

.PHONY: idp-sdk
idp-sdk:
	@if [ "$(DRY_RUN)" = "1" ]; then \
		"$(IDP_PREVIEW_ACTION_CATALOG)" --dry-run-message idp-sdk --runtime "$(K8S_IDP_RUNTIME)" --idp-public-url "$(IDP_PUBLIC_URL)" --idp-api-public-url "$(IDP_API_PUBLIC_URL)"; \
	else \
		"$(IDP_PREVIEW_ACTION_CATALOG)" --run-command idp-sdk --runtime "$(K8S_IDP_RUNTIME)" --repo-root "$(REPO_ROOT)" --idp-public-url "$(IDP_PUBLIC_URL)" --idp-api-public-url "$(IDP_API_PUBLIC_URL)"; \
	fi

.PHONY: idp-mcp
idp-mcp:
	@if [ "$(DRY_RUN)" = "1" ]; then \
		"$(IDP_PREVIEW_ACTION_CATALOG)" --dry-run-message idp-mcp --runtime "$(K8S_IDP_RUNTIME)" --idp-public-url "$(IDP_PUBLIC_URL)" --idp-api-public-url "$(IDP_API_PUBLIC_URL)"; \
	else \
		"$(IDP_PREVIEW_ACTION_CATALOG)" --run-command idp-mcp --runtime "$(K8S_IDP_RUNTIME)" --repo-root "$(REPO_ROOT)" --idp-public-url "$(IDP_PUBLIC_URL)" --idp-api-public-url "$(IDP_API_PUBLIC_URL)"; \
	fi
