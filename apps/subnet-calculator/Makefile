.PHONY: help check-prerequisites clean-ports \
  start-direct-azure-function start-direct-container-app start-direct-flask start-direct-vite \
  start-direct-all-bg wait-direct-services \
  start-compose-all start-compose-01 start-compose-02 start-compose-03 start-compose-04 \
  start-swa-04 start-swa-05 start-swa-06 \
  test-bruno-direct test-bruno-compose test-bruno-swa \
  test-bruno-direct-full test-bruno-compose-full test-bruno-swa-full

help:
	@echo "Subnet Calculator - Development Commands"
	@echo ""
	@echo "=== Prerequisites ==="
	@echo "  make check-prerequisites            Check that podman/docker is running"
	@echo ""
	@echo "=== Direct Launches (7000s) ==="
	@echo "  make start-direct-azure-function    Start Azure Function API (port 7071)"
	@echo "  make start-direct-container-app     Start Container App API (port 7080)"
	@echo "  make start-direct-flask             Start Flask frontend (port 7000)"
	@echo "  make start-direct-vite              Start TypeScript Vite frontend (port 7010)"
	@echo ""
	@echo "=== Podman-Compose (8000s) ==="
	@echo "  make start-compose-all              Start all compose stacks (8000-8003)"
	@echo "  make start-compose-01               Start compose-01: Flask + Azure Function (8000)"
	@echo "  make start-compose-02               Start compose-02: Static HTML + Container App (8001)"
	@echo "  make start-compose-03               Start compose-03: Flask + Container App (8002)"
	@echo "  make start-compose-04               Start compose-04: TypeScript Vite + Container App (8003)"
	@echo ""
	@echo "=== SWA CLI (4000s) ==="
	@echo "  make start-swa-04                   Start SWA 04: No Auth (port 4280)"
	@echo "  make start-swa-05                   Start SWA 05: JWT Auth (port 4281)"
	@echo "  make start-swa-06                   Start SWA 06: Entra ID Auth (port 4282)"
	@echo ""
	@echo "=== Testing ==="
	@echo "  make test-bruno-direct              Test direct launches with Bruno CLI"
	@echo "  make test-bruno-direct-full         Start direct services + test + cleanup"
	@echo "  make test-bruno-compose             Test compose stacks with Bruno CLI"
	@echo "  make test-bruno-compose-full        Start compose services + test + cleanup"
	@echo "  make test-bruno-swa                 Test SWA stacks with Bruno CLI"
	@echo "  make test-bruno-swa-full            Start SWA services + test + cleanup"
	@echo ""
	@echo "=== Cleanup ==="
	@echo "  make clean-ports                    Kill all processes on used ports"
	@echo ""

check-prerequisites:
	@echo "Checking prerequisites..."
	@echo ""
	@echo "1. Checking for podman-compose or compose..."
	@if command -v podman-compose > /dev/null 2>&1; then \
		echo "✓ podman-compose found"; \
	elif command -v compose > /dev/null 2>&1; then \
		echo "✓ compose found"; \
	else \
		echo "✗ Neither podman-compose nor compose found"; \
		echo "  Install with: brew install podman-compose"; \
		exit 1; \
	fi
	@echo ""
	@echo "2. Checking if podman/docker is running..."
	@if command -v podman > /dev/null 2>&1; then \
		if podman info > /dev/null 2>&1; then \
			echo "✓ Podman is running"; \
		else \
			echo "✗ Podman is not running"; \
			echo "  Start with: podman machine start"; \
			exit 1; \
		fi; \
	elif command -v docker > /dev/null 2>&1; then \
		if docker info > /dev/null 2>&1; then \
			echo "✓ Docker is running"; \
		else \
			echo "✗ Docker is not running"; \
			echo "  Start Docker Desktop or use: docker-machine start"; \
			exit 1; \
		fi; \
	else \
		echo "✗ Neither podman nor docker found"; \
		echo "  Install podman: brew install podman"; \
		echo "  Or install docker: brew install docker"; \
		exit 1; \
	fi
	@echo ""
	@echo "✓ All prerequisites satisfied"

# Clean up all services
clean-ports:
	@echo "Cleaning up services..."
	@echo "  Stopping podman-compose stacks..."
	@podman-compose down 2>/dev/null || true
	@echo "  Killing direct services (7000s) and SWA services (4000s)..."
	@for port in 7071 7080 7000 7010 4280 4281 4282; do \
		pid=$$(lsof -ti:$$port 2>/dev/null); \
		if [ -n "$$pid" ]; then \
			echo "    Killing process on port $$port (PID: $$pid)"; \
			kill -9 $$pid 2>/dev/null || true; \
		fi; \
	done
	@sleep 1
	@echo "✓ Cleanup complete"

##@ Direct Launches

start-direct-azure-function:
	@echo "Starting Azure Function API (port 7071)..."
	cd api-fastapi-azure-function && \
		export AUTH_METHOD=jwt && \
		uv run func start

start-direct-container-app:
	@echo "Starting Container App API (port 7080)..."
	cd api-fastapi-container-app && \
		uv run uvicorn app.main:app --reload --port 7080

start-direct-flask:
	@echo "Starting Flask frontend (port 7000)..."
	cd frontend-python-flask && \
		export API_URL=http://localhost:7071 && \
		uv run flask run --port 7000

start-direct-vite:
	@echo "Starting TypeScript Vite frontend (port 7010)..."
	cd frontend-typescript-vite && \
		VITE_API_URL=http://localhost:7080 npm run dev -- --port 7010

# Background service startup helpers
start-direct-all-bg:
	@echo "Starting all direct services in background..."
	@mkdir -p /tmp/subnet-calc-logs
	@(cd api-fastapi-azure-function && export AUTH_METHOD=jwt && uv run func start) > /tmp/subnet-calc-logs/azure-func.log 2>&1 &
	@(cd api-fastapi-container-app && uv run uvicorn app.main:app --reload --port 7080) > /tmp/subnet-calc-logs/container-app.log 2>&1 &
	@(cd frontend-python-flask && export API_URL=http://localhost:7071 && uv run flask run --port 7000) > /tmp/subnet-calc-logs/flask.log 2>&1 &
	@(cd frontend-typescript-vite && VITE_API_URL=http://localhost:7080 npm run dev -- --port 7010) > /tmp/subnet-calc-logs/vite.log 2>&1 &
	@echo "✓ Services started in background"
	@echo "  Logs available in /tmp/subnet-calc-logs/"

wait-direct-services:
	@echo "Waiting for direct services to be ready..."
	@for service in "Azure Function:7071" "Container App:7080"; do \
		name=$${service%:*}; \
		port=$${service#*:}; \
		echo "Checking $$name (port $$port)..."; \
		success=false; \
		for i in 1 2 3 4 5; do \
			if curl -s http://localhost:$$port/api/v1/health > /dev/null 2>&1; then \
				echo "✓ $$name is ready"; \
				success=true; \
				break; \
			fi; \
			if [ $$i -lt 5 ]; then \
				echo "  Attempt $$i/5, waiting..."; \
				sleep 2; \
			fi; \
		done; \
		if [ "$$success" = "false" ]; then \
			echo "✗ $$name failed to become ready"; \
			exit 1; \
		fi; \
	done
	@echo "✓ All direct services are ready!"

##@ Podman-Compose

start-compose-all: check-prerequisites
	@echo "Starting all podman-compose stacks..."
	@echo "  compose-01 (Flask + Azure Function):           http://localhost:8000"
	@echo "  compose-02 (Static HTML + Container App):      http://localhost:8001"
	@echo "  compose-03 (Flask + Container App):            http://localhost:8002"
	@echo "  compose-04 (TypeScript Vite + Container App):  http://localhost:8003"
	podman-compose up

start-compose-01: check-prerequisites
	@echo "Starting compose-01: Flask + Azure Function (port 8000)..."
	podman-compose up frontend-python-flask api-fastapi-azure-function

start-compose-02: check-prerequisites
	@echo "Starting compose-02: Static HTML + Container App (port 8001)..."
	podman-compose up frontend-html-static api-fastapi-container-app

start-compose-03: check-prerequisites
	@echo "Starting compose-03: Flask + Container App (port 8002)..."
	podman-compose up frontend-python-flask-container-app api-fastapi-container-app

start-compose-04: check-prerequisites
	@echo "Starting compose-04: TypeScript Vite + Container App (port 8003)..."
	podman-compose up frontend-typescript-vite api-fastapi-container-app

##@ SWA CLI

start-swa-04: check-prerequisites
	@echo "Checking if compose backend is running for SWA 04..."
	@if ! curl -s http://localhost:8090/api/v1/health > /dev/null 2>&1; then \
		echo "✗ Container App API (port 8090 - from compose) is not running"; \
		echo "Starting compose stack..."; \
		podman-compose up -d api-fastapi-container-app; \
		echo "Waiting for Container App to be ready..."; \
		for i in 1 2 3 4 5; do \
			if curl -s http://localhost:8090/api/v1/health > /dev/null 2>&1; then \
				echo "✓ Container App is ready"; \
				break; \
			fi; \
			if [ $$i -lt 5 ]; then echo "  Attempt $$i/5, waiting..."; sleep 2; fi; \
		done; \
	fi
	@echo "✓ Container App (port 8090 - compose) is ready"
	@echo "Building frontend..."
	cd frontend-typescript-vite && VITE_API_URL= npm run build && cd ..
	@if [ ! -d "frontend-typescript-vite/dist" ]; then \
		echo "✗ Frontend build failed - dist folder not found"; \
		exit 1; \
	fi
	@echo "✓ Frontend built successfully"
	@echo "Starting SWA 04: TypeScript Vite + Container App (No Auth) on port 4280..."
	@echo "Backend: http://localhost:8090 (compose)"
	swa start --config-name swa-04

start-swa-05: check-prerequisites
	@echo "Checking if compose backend is running for SWA 05..."
	@if ! curl -s http://localhost:8080/api/v1/health > /dev/null 2>&1; then \
		echo "✗ Azure Function API (port 8080 - from compose) is not running"; \
		echo "Starting compose stack..."; \
		podman-compose up -d api-fastapi-azure-function; \
		echo "Waiting for Azure Function to be ready..."; \
		for i in 1 2 3 4 5; do \
			if curl -s http://localhost:8080/api/v1/health > /dev/null 2>&1; then \
				echo "✓ Azure Function is ready"; \
				break; \
			fi; \
			if [ $$i -lt 5 ]; then echo "  Attempt $$i/5, waiting..."; sleep 2; fi; \
		done; \
	fi
	@echo "✓ Azure Function (port 8080 - compose) is ready"
	@echo "Building frontend with JWT auth enabled..."
	cd frontend-typescript-vite && VITE_API_URL= VITE_AUTH_ENABLED=true npm run build && cd ..
	@if [ ! -d "frontend-typescript-vite/dist" ]; then \
		echo "✗ Frontend build failed - dist folder not found"; \
		exit 1; \
	fi
	@echo "✓ Frontend built successfully"
	@echo "Starting SWA 05: TypeScript Vite + Azure Function (JWT Auth) on port 4281..."
	@echo "Backend: http://localhost:8080 (compose)"
	swa start --config-name swa-05

start-swa-06: check-prerequisites
	@echo "Checking if compose backend is running for SWA 06..."
	@if ! curl -s http://localhost:8090/api/v1/health > /dev/null 2>&1; then \
		echo "✗ Container App API (port 8090 - from compose) is not running"; \
		echo "Starting compose stack..."; \
		podman-compose up -d api-fastapi-container-app; \
		echo "Waiting for Container App to be ready..."; \
		for i in 1 2 3 4 5; do \
			if curl -s http://localhost:8090/api/v1/health > /dev/null 2>&1; then \
				echo "✓ Container App is ready"; \
				break; \
			fi; \
			if [ $$i -lt 5 ]; then echo "  Attempt $$i/5, waiting..."; sleep 2; fi; \
		done; \
	fi
	@echo "✓ Container App (port 8090 - compose) is ready"
	@echo "Building frontend (Entra ID auth handled by SWA layer)..."
	cd frontend-typescript-vite && VITE_API_URL= npm run build && cd ..
	@if [ ! -d "frontend-typescript-vite/dist" ]; then \
		echo "✗ Frontend build failed - dist folder not found"; \
		exit 1; \
	fi
	@echo "✓ Frontend built successfully"
	@echo "Starting SWA 06: TypeScript Vite + Container App (Entra ID at SWA layer) on port 4282..."
	@echo "Backend: http://localhost:8090 (compose) - no app-level auth"
	swa start --config-name swa-06

##@ SWA Comparison (all stacks)

start-swa-backends: check-prerequisites
	@echo "Starting SWA backends (compose)..."
	@echo "  Starting Container App (port 8090) for swa-04, swa-06..."
	@podman-compose up -d api-fastapi-container-app
	@echo "  Starting Azure Function (port 8080) for swa-05..."
	@podman-compose up -d api-fastapi-azure-function
	@echo "Waiting for backends to be ready..."
	@for i in 1 2 3 4 5; do \
		if curl -s http://localhost:8090/api/v1/health > /dev/null && curl -s http://localhost:8080/api/v1/health > /dev/null; then \
			echo "✓ All backends ready"; \
			break; \
		fi; \
		if [ $$i -lt 5 ]; then echo "  Attempt $$i/5, waiting..."; sleep 2; fi; \
	done

start-swa-all: start-swa-backends
	@echo ""
	@echo "Building frontend for all SWA stacks..."
	cd frontend-typescript-vite && VITE_API_URL= npm run build && cd ..
	@echo ""
	@echo "╔════════════════════════════════════════════════════════════════╗"
	@echo "║ Starting all three SWA stacks for comparison                   ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║ SWA 04 (port 4280): Container App + No Auth                   ║"
	@echo "║ SWA 05 (port 4281): Azure Function + JWT Auth                 ║"
	@echo "║ SWA 06 (port 4282): Azure Function + Entra ID                 ║"
	@echo "╠════════════════════════════════════════════════════════════════╣"
	@echo "║ NOTE: These will run in foreground. Use separate terminals:    ║"
	@echo "║   make start-swa-04                                            ║"
	@echo "║   make start-swa-05                                            ║"
	@echo "║   make start-swa-06                                            ║"
	@echo "╚════════════════════════════════════════════════════════════════╝"

##@ Testing

test-bruno-direct:
	@echo "Testing direct launches with Bruno CLI..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run direct-azure-function --env local && \
		npx @usebruno/cli@latest run direct-container-app --env local

test-bruno-compose:
	@echo "Testing compose stacks with Bruno CLI..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run compose-01 --env local && \
		npx @usebruno/cli@latest run compose-02 --env local && \
		npx @usebruno/cli@latest run compose-03 --env local && \
		npx @usebruno/cli@latest run compose-04 --env local

test-bruno-swa:
	@echo "Testing SWA stacks with Bruno CLI..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run swa-04 --env local && \
		npx @usebruno/cli@latest run swa-05 --env local && \
		npx @usebruno/cli@latest run swa-06 --env local

test-bruno-swa-all: clean-ports start-swa-backends
	@echo "Building frontend for all SWA stacks..."
	cd frontend-typescript-vite && VITE_API_URL= npm run build && cd ..
	@echo "Starting SWA emulators in background..."
	@mkdir -p /tmp/subnet-calc-logs
	@(swa start --config-name swa-04) > /tmp/subnet-calc-logs/swa-04.log 2>&1 &
	@echo "$$!" > /tmp/swa-04.pid
	@(swa start --config-name swa-05) > /tmp/subnet-calc-logs/swa-05.log 2>&1 &
	@echo "$$!" > /tmp/swa-05.pid
	@(swa start --config-name swa-06) > /tmp/subnet-calc-logs/swa-06.log 2>&1 &
	@echo "$$!" > /tmp/swa-06.pid
	@echo "Waiting for SWA services to be ready..."
	@sleep 10
	@echo "Running Bruno tests on all SWA stacks..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run swa-04 --env local && \
		npx @usebruno/cli@latest run swa-05 --env local && \
		npx @usebruno/cli@latest run swa-06 --env local
	@echo "Stopping SWA emulators..."
	@kill $$(cat /tmp/swa-04.pid 2>/dev/null) 2>/dev/null || true
	@kill $$(cat /tmp/swa-05.pid 2>/dev/null) 2>/dev/null || true
	@kill $$(cat /tmp/swa-06.pid 2>/dev/null) 2>/dev/null || true
	@sleep 1
	@echo "✓ All SWA tests complete"

##@ Full Test Chains (Start + Test + Cleanup)

test-bruno-direct-full: clean-ports start-direct-all-bg wait-direct-services test-bruno-direct clean-ports
	@echo ""
	@echo "✓ Direct testing complete (services cleaned up)"

test-bruno-compose-full: check-prerequisites
	@echo "Starting compose services..."
	podman-compose up -d
	@echo "Waiting for compose services to be ready..."
	@sleep 10
	@echo "Running compose tests..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run compose-01 --env local && \
		npx @usebruno/cli@latest run compose-02 --env local && \
		npx @usebruno/cli@latest run compose-03 --env local && \
		npx @usebruno/cli@latest run compose-04 --env local
	@echo "Stopping compose services..."
	podman-compose down
	@echo "✓ Compose testing complete"

test-bruno-swa-full: clean-ports check-prerequisites
	@echo "Starting SWA backend dependencies (via compose)..."
	@mkdir -p /tmp/subnet-calc-logs
	@echo "  Starting both backends..."
	@podman-compose up -d api-fastapi-container-app api-fastapi-azure-function > /tmp/subnet-calc-logs/compose-up.log 2>&1
	@echo "Waiting for backends to be ready..."
	@for i in 1 2 3 4 5; do \
		if curl -s http://localhost:8090/api/v1/health > /dev/null && curl -s http://localhost:8080/api/v1/health > /dev/null; then \
			echo "✓ Backends ready"; \
			break; \
		fi; \
		if [ $$i -lt 5 ]; then echo "  Attempt $$i/5, waiting..."; sleep 3; fi; \
	done
	@echo "Building frontends for SWA (using SWA proxy pattern)..."
	@(cd frontend-typescript-vite && VITE_API_URL= npm run build) > /tmp/subnet-calc-logs/build-swa.log 2>&1
	@echo "Starting SWA services..."
	@(swa start --config-name swa-04) > /tmp/subnet-calc-logs/swa-04.log 2>&1 &
	@echo "$$!" > /tmp/swa-04.pid
	@(export AUTH_METHOD=jwt && export VITE_AUTH_ENABLED=true && swa start --config-name swa-05) > /tmp/subnet-calc-logs/swa-05.log 2>&1 &
	@echo "$$!" > /tmp/swa-05.pid
	@(export AUTH_METHOD=none && swa start --config-name swa-06) > /tmp/subnet-calc-logs/swa-06.log 2>&1 &
	@echo "$$!" > /tmp/swa-06.pid
	@echo "Waiting for SWA services to be ready..."
	@sleep 15
	@echo "Running SWA tests..."
	cd bruno-collections && \
		npx @usebruno/cli@latest run swa-04 --env local || true; \
		npx @usebruno/cli@latest run swa-05 --env local || true; \
		npx @usebruno/cli@latest run swa-06 --env local || true
	@echo "Stopping SWA services (4xxx ports)..."
	@kill $$(cat /tmp/swa-04.pid 2>/dev/null) 2>/dev/null || true
	@kill $$(cat /tmp/swa-05.pid 2>/dev/null) 2>/dev/null || true
	@kill $$(cat /tmp/swa-06.pid 2>/dev/null) 2>/dev/null || true
	@sleep 2
	@echo "Stopping compose backend services..."
	@podman-compose down
	@echo "✓ SWA testing complete"
