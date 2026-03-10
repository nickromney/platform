.PHONY: help install dev build preview test lint format type-check docker-build docker-run clean

# Default target
help:
	@echo "Available targets:"
	@echo "  install      - Install dependencies"
	@echo "  dev          - Start development server"
	@echo "  build        - Build for production"
	@echo "  preview      - Preview production build"
	@echo "  test         - Run Playwright tests"
	@echo "  lint         - Run Biome linting and formatting"
	@echo "  format       - Format code with Biome"
	@echo "  type-check   - Run TypeScript type checking"
	@echo "  docker-build - Build Docker image"
	@echo "  docker-run   - Run Docker container"
	@echo "  clean        - Remove build artifacts"

# Development
install:
	npm install

dev:
	npm run dev

build:
	npm run build

preview:
	npm run preview

# Testing and Quality
test:
	npm run test

lint:
	npm run lint

format:
	npm run format

type-check:
	npm run type-check

# Docker
docker-build:
	docker build -t subnet-calculator-react .

docker-run:
	docker run -p 8080:8080 subnet-calculator-react

# Cleanup
clean:
	rm -rf node_modules dist .vite coverage playwright-report test-results
