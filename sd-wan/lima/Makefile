# SD-WAN Multi-Cloud Simulation - Lima VM Orchestration
USE_COMMON_HELP := 1
MAKE_KNOWN_GOALS := help prereqs build check-host-ports fix-guest-hostnames up down status show-urls show-wireguard sync-wireguard sync-frontend sync-cloud1-diagnostics sync-subnet-api build-frontend test test-dns test-tunnel test-routing test-egress test-mtls test-tls test-subnetcalc test-e2e ssh-cloud1 ssh-cloud2 ssh-cloud3 logs destroy clean-pki
MAKE_SUGGEST_SCRIPT := ../../scripts/suggest-make-goal.sh

MAKEFILE_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
include ../../mk/common.mk
PROJECT_DIR := $(patsubst %/,%,$(MAKEFILE_DIR))
REPO_ROOT := $(abspath $(PROJECT_DIR)/../..)
PLATFORM_ENV_FILE ?= $(REPO_ROOT)/.env
PLATFORM_ENV_TEMPLATE ?= $(REPO_ROOT)/.env.example
PLATFORM_ADMIN_PASSWORD ?=
PLATFORM_DEMO_PASSWORD ?=
PLATFORM_REQUIRED_ENV_VARS := PLATFORM_ADMIN_PASSWORD PLATFORM_DEMO_PASSWORD
-include $(PLATFORM_ENV_FILE)
FRONTEND_SHARED_DIR := $(REPO_ROOT)/apps/subnet-calculator/shared-frontend
FRONTEND_DIR := $(REPO_ROOT)/apps/subnet-calculator/frontend-typescript-vite
CHECK_HOST_PORTS := $(PROJECT_DIR)/scripts/check-lima-host-ports.sh
CLOUDS := cloud1 cloud2 cloud3
LIMA_START_TIMEOUT ?= 30m

export PLATFORM_ENV_FILE
export PLATFORM_ENV_TEMPLATE
export PLATFORM_ADMIN_PASSWORD
export PLATFORM_DEMO_PASSWORD

.PHONY: prereqs build check-host-ports fix-guest-hostnames up down status show-urls show-wireguard sync-wireguard sync-frontend sync-cloud1-diagnostics sync-subnet-api build-frontend test test-dns test-tunnel test-routing test-egress test-mtls test-tls test-subnetcalc test-e2e \
        ssh-cloud1 ssh-cloud2 ssh-cloud3 logs destroy clean-pki

##@ Lifecycle
# --- Lifecycle ---

prereqs: ## Check macOS host prerequisites for Lima + networking
	@echo "=== Checking host prerequisites ==="
	@set -e; \
	$(MAKE) check-platform-env; \
	missing=0; \
	missing_tools=(); \
	LIMA_NETWORKS_FILE="$$HOME/.lima/_config/networks.yaml"; \
	echo "Tool installation verification:"; \
	if [ "$$(uname -s)" != "Darwin" ]; then \
		echo "  This SD-WAN Lima path currently assumes macOS (vmType=vz)."; \
		missing=1; \
	fi; \
	if ! command -v limactl >/dev/null 2>&1; then \
		echo "  Missing Lima CLI: limactl"; \
		missing_tools+=("limactl"); \
		missing=1; \
	else \
		echo "  OK: limactl found ($$(limactl --version 2>/dev/null | head -1))"; \
	fi; \
	if ! command -v node >/dev/null 2>&1; then \
		echo "  Missing Node.js runtime: node"; \
		missing_tools+=("node"); \
		missing=1; \
	else \
		echo "  OK: node found ($$(node --version 2>/dev/null))"; \
	fi; \
	if ! command -v npm >/dev/null 2>&1; then \
		echo "  Missing npm (usually installed with Node.js)"; \
		missing_tools+=("npm"); \
		missing=1; \
	else \
		echo "  OK: npm found ($$(npm --version 2>/dev/null))"; \
	fi; \
	echo ""; \
	echo "Host configuration verification:"; \
	if command -v socket_vmnet >/dev/null 2>&1; then \
		echo "  Optional: socket_vmnet found (not required for lima:user-v2)"; \
	else \
		echo "  Optional: socket_vmnet not found (OK for lima:user-v2)"; \
	fi; \
	if [ ! -f "$$LIMA_NETWORKS_FILE" ]; then \
		echo "  Missing Lima networks config: $$LIMA_NETWORKS_FILE"; \
		echo "  Fix: limactl sudoers && limactl start-at-login"; \
		missing=1; \
	elif ! awk '/^[[:space:]]*user-v2:[[:space:]]*$$/ {found=1} END {exit found ? 0 : 1}' "$$LIMA_NETWORKS_FILE"; then \
		echo "  Missing Lima named network: user-v2"; \
		echo "  Fix: limactl sudoers && limactl start-at-login"; \
		missing=1; \
	else \
		echo "  OK: Lima named network user-v2 is configured"; \
	fi; \
	if [ -f "$$LIMA_NETWORKS_FILE" ]; then \
		socket_path=$$(awk -F'"' '/socketVMNet:/ {print $$2; exit}' "$$LIMA_NETWORKS_FILE"); \
		if [ -n "$$socket_path" ] && [ ! -x "$$socket_path" ]; then \
			echo "  Lima config mismatch: socketVMNet path '$$socket_path' is not executable"; \
			echo "  Fix (Apple Silicon): sudo mkdir -p /opt/socket_vmnet/bin && sudo ln -sf /opt/homebrew/opt/socket_vmnet/bin/socket_vmnet /opt/socket_vmnet/bin/socket_vmnet"; \
			echo "  Then run: sudo brew services start socket_vmnet"; \
			missing=1; \
		fi; \
	fi; \
	if [ $$missing -ne 0 ]; then \
		echo ""; \
		echo "Install hints:"; \
		"$(REPO_ROOT)/scripts/install-tool-hints.sh" --plain "$${missing_tools[@]}" | sed 's/^/  /'; \
		echo ""; \
		echo "Fix missing prerequisites and run: make prereqs"; \
		exit 1; \
	fi; \
	$(MAKE) check-host-ports; \
	echo "All prerequisites look good."

check-host-ports: ## Verify that planned Lima host port forwards are available
	@"$(CHECK_HOST_PORTS)" --execute

fix-guest-hostnames:
	@set -euo pipefail; \
	for cloud in $(CLOUDS); do \
		state="$$(limactl list --format '{{.Name}} {{.Status}}' 2>/dev/null | awk -v target="$$cloud" '$$1 == target {print $$2; exit}')"; \
		if [ "$$state" != "Running" ]; then \
			continue; \
		fi; \
		limactl shell "$$cloud" -- env TARGET_CLOUD_NAME="$$cloud" bash "$(PROJECT_DIR)/provision/fix-hostname.sh" >/dev/null; \
	done

build-frontend: ## Build subnet-calculator frontend for deployment
	@$(MAKE) check-platform-env
	@echo "=== Building frontend ==="
	@npm --prefix "$(FRONTEND_SHARED_DIR)" run build
	@cd "$(FRONTEND_DIR)" && \
		VITE_API_URL='' \
		VITE_AUTH_ENABLED=true \
		VITE_AUTH_METHOD=jwt \
		VITE_JWT_USERNAME=demo \
		VITE_JWT_PASSWORD="$${PLATFORM_DEMO_PASSWORD}" \
		VITE_SHOW_NETWORK_PATH=true \
		VITE_FRONTEND_STATUS_LABEL='Frontend origin' \
		VITE_API_INGRESS_STATUS_LABEL='Cloud1 ingress' \
		VITE_BACKEND_PATH_STATUS_LABEL='Backend path' \
		VITE_BACKEND_PATH_STATUS_DETAIL='cloud1 nginx -> WireGuard SD-WAN -> cloud2 nginx -> cloud2 FastAPI' \
		VITE_NETWORK_DIAGNOSTICS_LABEL='Backend Diagnostics (cloud2 viewpoint)' \
		VITE_SECONDARY_NETWORK_DIAGNOSTICS_LABEL='Frontend Diagnostics (cloud1 viewpoint)' \
		VITE_SECONDARY_NETWORK_DIAGNOSTICS_PATH='/cloud1-diagnostics/network/diagnostics' \
		VITE_NETWORK_HOPS='[{"label":"Browser","detail":"localhost:58081","role":"Host browser entrypoint"},{"label":"cloud1 nginx","detail":"127.0.0.1:58081 -> guest 10.10.1.4:8080","role":"Frontend + reverse proxy"},{"label":"WireGuard SD-WAN","detail":"172.16.11.2:443 (mTLS)","role":"Encrypted cross-cloud VIP path"},{"label":"cloud2 nginx","detail":"172.16.11.2:443","role":"Inbound gateway + mTLS termination"},{"label":"cloud2 FastAPI","detail":"10.10.1.4:8000","role":"Subnet Calculator API (JWT auth)"}]' \
		npm ci && \
		VITE_API_URL='' \
		VITE_AUTH_ENABLED=true \
		VITE_AUTH_METHOD=jwt \
		VITE_JWT_USERNAME=demo \
		VITE_JWT_PASSWORD="$${PLATFORM_DEMO_PASSWORD}" \
		VITE_SHOW_NETWORK_PATH=true \
		VITE_FRONTEND_STATUS_LABEL='Frontend origin' \
		VITE_API_INGRESS_STATUS_LABEL='Cloud1 ingress' \
		VITE_BACKEND_PATH_STATUS_LABEL='Backend path' \
		VITE_BACKEND_PATH_STATUS_DETAIL='cloud1 nginx -> WireGuard SD-WAN -> cloud2 nginx -> cloud2 FastAPI' \
		VITE_NETWORK_DIAGNOSTICS_LABEL='Backend Diagnostics (cloud2 viewpoint)' \
		VITE_SECONDARY_NETWORK_DIAGNOSTICS_LABEL='Frontend Diagnostics (cloud1 viewpoint)' \
		VITE_SECONDARY_NETWORK_DIAGNOSTICS_PATH='/cloud1-diagnostics/network/diagnostics' \
		VITE_NETWORK_HOPS='[{"label":"Browser","detail":"localhost:58081","role":"Host browser entrypoint"},{"label":"cloud1 nginx","detail":"127.0.0.1:58081 -> guest 10.10.1.4:8080","role":"Frontend + reverse proxy"},{"label":"WireGuard SD-WAN","detail":"172.16.11.2:443 (mTLS)","role":"Encrypted cross-cloud VIP path"},{"label":"cloud2 nginx","detail":"172.16.11.2:443","role":"Inbound gateway + mTLS termination"},{"label":"cloud2 FastAPI","detail":"10.10.1.4:8000","role":"Subnet Calculator API (JWT auth)"}]' \
		npm run build
	@mkdir -p /tmp/lima/frontend
	@rm -rf /tmp/lima/frontend/*
	@cp -r "$(FRONTEND_DIR)/dist/." /tmp/lima/frontend/
	@echo "Frontend built and staged to /tmp/lima/frontend/"

build: ## Build the frontend assets for deployment
	@$(MAKE) --no-print-directory build-frontend

up: prereqs build-frontend ## Start all 3 Lima VMs
	@echo "=== Starting SD-WAN simulation ==="
	@mkdir -p /tmp/lima/pki /tmp/lima/wireguard
	@set -e; for cloud in $(CLOUDS); do \
		if limactl list --format '{{.Name}}' 2>/dev/null | grep -qx "$$cloud"; then \
			echo "  Starting existing $$cloud..."; \
			limactl start $$cloud --tty=false --timeout=$(LIMA_START_TIMEOUT); \
		else \
			echo "  Creating and starting $$cloud..."; \
			limactl start --name=$$cloud ./$$cloud.yaml --tty=false --timeout=$(LIMA_START_TIMEOUT); \
		fi; \
	done
	@$(MAKE) fix-guest-hostnames
	@$(MAKE) sync-frontend
	@$(MAKE) sync-cloud1-diagnostics
	@$(MAKE) sync-subnet-api
	@$(MAKE) sync-wireguard
	@echo ""
	@echo "=== All VMs started ==="
	@$(MAKE) status

sync-wireguard: fix-guest-hostnames ## Rebuild WireGuard peers after all VMs are up
	@echo "=== Syncing WireGuard mesh ==="
	@set -e; for cloud in $(CLOUDS); do \
		case "$$cloud" in \
			cloud1) cloud_num=1; tunnel_ip=192.168.1.1 ;; \
			cloud2) cloud_num=2; tunnel_ip=192.168.1.2 ;; \
			cloud3) cloud_num=3; tunnel_ip=192.168.1.3 ;; \
		esac; \
		echo "  Reconfiguring $$cloud..."; \
		limactl shell $$cloud -- sudo env CLOUD_NUM=$$cloud_num CLOUD_NAME=$$cloud TUNNEL_IP=$$tunnel_ip bash $(PROJECT_DIR)/provision/setup-wireguard.sh; \
	done

sync-frontend: fix-guest-hostnames ## Sync frontend build artifacts to cloud1 and restart nginx
	@echo "=== Syncing frontend on cloud1 ==="
	@limactl shell cloud1 -- sudo bash -c 'set -euo pipefail; \
		if [ ! -d /tmp/lima/frontend ]; then \
			echo "Missing /tmp/lima/frontend; run make build-frontend first"; \
			exit 1; \
		fi; \
		mkdir -p /var/www/frontend; \
		rm -rf /var/www/frontend/*; \
		cp -r /tmp/lima/frontend/. /var/www/frontend/; \
		systemctl restart nginx'

sync-cloud1-diagnostics: fix-guest-hostnames ## Sync cloud1 diagnostics API and restart service
	@echo "=== Syncing cloud1 diagnostics API on cloud1 ==="
	@limactl shell cloud1 -- sudo env PROJECT_DIR="$(PROJECT_DIR)" bash -c 'set -euo pipefail; \
		mkdir -p /opt/cloud1-diagnostics; \
		cp "$$PROJECT_DIR/api/main.py" /opt/cloud1-diagnostics/main.py; \
		cp "$$PROJECT_DIR/config/proxy/frontend.cloud1.conf" /etc/nginx/conf.d/frontend.conf; \
		printf "%s\n" \
			"[Unit]" \
			"Description=SD-WAN Cloud1 Diagnostics API Service" \
			"After=network.target" \
			"" \
			"[Service]" \
			"Type=simple" \
			"Environment=CLOUD_NAME=cloud1" \
			"Environment=CLOUD_IP=10.10.1.4" \
			"Environment=DNS_IP=10.10.1.10" \
			"ExecStart=/opt/app-venv/bin/uvicorn main:app --host 127.0.0.1 --port 9000" \
			"WorkingDirectory=/opt/cloud1-diagnostics" \
			"Restart=always" \
			"" \
			"[Install]" \
			"WantedBy=multi-user.target" \
			> /etc/systemd/system/sdwan-cloud1-diagnostics.service; \
		systemctl daemon-reload; \
		systemctl enable --now sdwan-cloud1-diagnostics; \
		systemctl restart nginx'

sync-subnet-api: fix-guest-hostnames ## Sync subnet-calculator API code to cloud2 and restart service
	@echo "=== Syncing subnet calculator API on cloud2 ==="
	@limactl shell cloud2 -- sudo env REPO_ROOT="$(REPO_ROOT)" bash -c 'set -euo pipefail; \
		mkdir -p /opt/app/app; \
		cp -r "$$REPO_ROOT/apps/subnet-calculator/api-fastapi-container-app/app/." /opt/app/app/; \
		systemctl restart sdwan-app'

down: ## Stop all VMs (preserves state)
	@echo "=== Stopping all VMs ==="
	@for cloud in $(CLOUDS); do \
		limactl stop $$cloud 2>/dev/null || true; \
	done
	@echo "Done."

destroy: ## Delete all VMs permanently
	@echo "=== Destroying all VMs ==="
	@set -euo pipefail; \
	found=0; \
	for cloud in $(CLOUDS); do \
		state="$$(limactl list --format '{{.Name}} {{.Status}}' 2>/dev/null | awk -v target="$$cloud" '$$1 == target {print $$2; exit}')"; \
		if [ -z "$$state" ]; then \
			echo "  Skipping $$cloud (not present)"; \
			continue; \
		fi; \
		found=1; \
		echo "  Deleting $$cloud ($$state)..."; \
		limactl delete --force "$$cloud"; \
	done; \
	if [ "$$found" -eq 0 ]; then \
		echo "  No Lima instances found for this lab."; \
	fi; \
	if pkill -f 'limactl hostagent.*cloud[123]' 2>/dev/null; then \
		echo "  Cleaned up stale Lima hostagent processes."; \
	fi
	@$(MAKE) clean-pki
	@echo "Done."

clean-pki: ## Remove generated PKI material
	@set -euo pipefail; \
	removed=0; \
	for path in /tmp/lima/pki /tmp/lima/wireguard; do \
		if [ -e "$$path" ]; then \
			rm -rf "$$path"; \
			echo "  Removed $$path"; \
			removed=1; \
		fi; \
	done; \
	if [ "$$removed" -eq 0 ]; then \
		echo "  No generated PKI state found."; \
	fi

##@ Status
# --- Status ---

status: fix-guest-hostnames ## Show VM status + access URLs + WireGuard summary
	@echo "=== VM Status ==="
	@set -euo pipefail; \
	limactl list; \
	not_running=""; \
	for cloud in $(CLOUDS); do \
		state="$$(limactl list 2>/dev/null | awk -v target="$$cloud" 'NR>1 && $$1==target {print $$2; exit}')"; \
		if [ "$$state" != "Running" ]; then \
			not_running="$$not_running $$cloud"; \
		fi; \
	done; \
	echo ""; \
	echo "=== Access URLs ==="; \
	if [ -n "$$not_running" ]; then \
		echo "Frontend: unavailable until all lab VMs are running"; \
		echo "Run: make up"; \
	else \
		echo "Frontend: http://127.0.0.1:58081/"; \
		echo "Cloud1 diagnostics: http://127.0.0.1:58081/cloud1-diagnostics/network/diagnostics"; \
	fi; \
	echo ""; \
	echo "=== WireGuard Summary ==="; \
	if [ -n "$$not_running" ]; then \
		echo "Skipped because these instances are not running:$$not_running"; \
		echo "Run: make up"; \
		exit 0; \
	fi; \
	for cloud in $(CLOUDS); do \
		echo "--- $$cloud ---"; \
		limactl shell $$cloud -- sudo bash -lc '\
			set -euo pipefail; \
			if ! ip link show wg0 >/dev/null 2>&1; then \
				echo "wg0: unavailable"; \
				exit 0; \
			fi; \
			dump="$$(wg show wg0 dump)"; \
			iface_line="$$(printf "%s\n" "$$dump" | sed -n "1p")"; \
			listen_port="$$(printf "%s\n" "$$iface_line" | awk -F "\t" "{print \$$3}")"; \
			local_ip="$$(ip -4 -o addr show dev wg0 | awk "{print \$$4}" | head -n1)"; \
			peer_count="$$(printf "%s\n" "$$dump" | tail -n +2 | sed "/^[[:space:]]*$$/d" | wc -l | tr -d " ")"; \
			echo "wg0: up local=$${local_ip:-unknown} listen=$${listen_port:-unknown} peers=$$peer_count"; \
			if [ "$$peer_count" -eq 0 ]; then \
				exit 0; \
			fi; \
			now="$$(date +%s)"; \
			printf "%s\n" "$$dump" | tail -n +2 | while IFS=$$'\''\t'\'' read -r public_key _ endpoint _ latest_handshake _ _ _; do \
				[ -n "$$public_key" ] || continue; \
				short_key="$$(printf "%s" "$$public_key" | cut -c1-12)"; \
				if [ -z "$$endpoint" ]; then \
					endpoint="(none)"; \
				fi; \
				if [ -z "$$latest_handshake" ] || [ "$$latest_handshake" = "0" ]; then \
					handshake="never"; \
				else \
					age="$$((now - latest_handshake))"; \
					handshake="$${age}s ago"; \
				fi; \
				echo "peer $${short_key} endpoint=$$endpoint handshake=$$handshake"; \
			done'; \
		echo ""; \
	done

show-urls: ## Show frontend and diagnostics URLs
	@set -euo pipefail; \
	not_running=""; \
	for cloud in $(CLOUDS); do \
		state="$$(limactl list 2>/dev/null | awk -v target="$$cloud" 'NR>1 && $$1==target {print $$2; exit}')"; \
		if [ "$$state" != "Running" ]; then \
			not_running="$$not_running $$cloud"; \
		fi; \
	done; \
	if [ -n "$$not_running" ]; then \
		echo "Frontend URL unavailable because these instances are not running:$$not_running"; \
		echo "Run: make up"; \
		exit 0; \
	fi; \
	echo "Frontend: http://127.0.0.1:58081/"; \
	echo "Cloud1 diagnostics: http://127.0.0.1:58081/cloud1-diagnostics/network/diagnostics"

show-wireguard: fix-guest-hostnames ## Show raw WireGuard peer state
	@set -euo pipefail; \
	not_running=""; \
	for cloud in $(CLOUDS); do \
		state="$$(limactl list 2>/dev/null | awk -v target="$$cloud" 'NR>1 && $$1==target {print $$2; exit}')"; \
		if [ "$$state" != "Running" ]; then \
			not_running="$$not_running $$cloud"; \
		fi; \
	done; \
	if [ -n "$$not_running" ]; then \
		echo "WireGuard state unavailable because these instances are not running:$$not_running"; \
		echo "Run: make up"; \
		exit 0; \
	fi; \
	for cloud in $(CLOUDS); do \
		echo "--- $$cloud ---"; \
		limactl shell $$cloud -- sudo wg show 2>/dev/null || echo "  (not running)"; \
		echo ""; \
	done

##@ SSH
# --- SSH ---

ssh-cloud1: ## Shell into cloud1 (Azure)
	limactl shell cloud1

ssh-cloud2: ## Shell into cloud2 (on-prem)
	limactl shell cloud2

ssh-cloud3: ## Shell into cloud3 (AWS)
	limactl shell cloud3

##@ Tests
# --- Tests ---

test: test-dns test-tunnel test-routing test-egress test-mtls test-tls test-subnetcalc ## Run all tests
	@echo ""
	@echo "=== All tests passed ==="

test-dns: ## DNS split-brain verification
	@echo "=== DNS Tests ==="
	@bash $(PROJECT_DIR)/tests/test-dns.sh --execute

test-tunnel: ## WireGuard connectivity
	@echo "=== Tunnel Tests ==="
	@bash $(PROJECT_DIR)/tests/test-tunnel.sh --execute

test-routing: ## End-to-end flow verification
	@echo "=== Routing Tests ==="
	@bash $(PROJECT_DIR)/tests/test-routing.sh --execute

test-egress: ## Iptables firewall rules
	@echo "=== Egress Tests ==="
	@bash $(PROJECT_DIR)/tests/test-egress.sh --execute

test-mtls: ## mTLS certificate verification
	@echo "=== mTLS Tests ==="
	@bash $(PROJECT_DIR)/tests/test-mtls.sh --execute

test-tls: ## TLS protocol and HSTS verification
	@echo "=== TLS Tests ==="
	@bash $(PROJECT_DIR)/tests/test-tls.sh --execute

test-subnetcalc: ## Subnet calculator mTLS + JWT flow
	@echo "=== Subnet Calculator Tests ==="
	@bash $(PROJECT_DIR)/tests/test-subnetcalc.sh --execute

test-e2e: ## Browser-based SD-WAN checks with Playwright
	@cd "$(PROJECT_DIR)/e2e" && npm install && npx playwright install chromium && npx playwright test

.PHONY: test-shell quality
test-shell: ## Run shell portability and hidden-dependency audit
	@/bin/bash "$(REPO_ROOT)/scripts/check-bash32-compat.sh" --execute
	@"$(REPO_ROOT)/scripts/audit-shell-scripts.sh" --execute

quality: test-shell ## Run static shell quality checks

##@ Logs
# --- Logs ---

logs: fix-guest-hostnames ## Tail CoreDNS + nginx logs across all VMs
	@for cloud in $(CLOUDS); do \
		echo "=== $$cloud ===" ; \
		limactl shell $$cloud -- sudo journalctl -u coredns -u nginx -u sdwan-app -u sdwan-cloud1-diagnostics --no-pager -n 20 2>/dev/null || true; \
		echo ""; \
	done
