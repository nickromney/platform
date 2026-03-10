# Subnet Calculator Frontend Testing - TODO

## Completed Tasks

### 1. Test Specification

- [x] Created `/subnet-calculator/docs/TEST_SPECIFICATION.md`
- [x] Defined 32 canonical tests across 10 groups
- [x] Documented element IDs, naming conventions, and requirements

### 2. Frontend Harmonization

- [x] Unified element IDs: All use `#ip-address` (not `#network-input`)
- [x] Unified default cloud mode: All default to `Azure` (changed from `Standard`)
- [x] Clear button resets to `Azure` in all frontends
- [x] Updated all JavaScript/TypeScript clearResults() functions

### 3. Test Suite Implementation

#### Flask Frontend (frontend-python-flask)

- [x] Rewrote `test_frontend.py` with all 32 tests in canonical order
- [x] Tests numbered 01-32 with consistent naming
- [x] All 32 tests passing
- [x] Fixed regex syntax issues (Python doesn't support `/pattern/`)
- [x] Fixed multi-element selector issue in test_23

**Test Results**: 32/32 PASS

#### Static HTML Frontend (frontend-html-static)

- [x] Rewrote `test_frontend.py` with all 32 tests in canonical order
- [x] Tests numbered 01-32 with consistent naming
- [x] Fixed regex syntax issues
- [x] Created `conftest.py` with base_url fixture

**Test Results**: Ready to test (requires server running on port 8001)

#### TypeScript Vite Frontend (frontend-typescript-vite)

- [ ] **TODO**: Rewrite `tests/frontend.spec.ts` with 30 tests
- [ ] Tests numbered 01-30 (skip 31-32: progressive enhancement)
- [ ] Use test.skip() for non-applicable tests
- [ ] Fix regex patterns and use proper TypeScript syntax

**Current**: 20 tests → **Target**: 30 tests

---

## [x] ALL TASKS COMPLETED

All remaining tasks have been completed successfully by parallel sub-agents!

### Final Results

- **Flask Frontend**: 32/32 tests PASSING [x]
- **Static HTML Frontend**: 32/32 tests PASSING [x]
- **TypeScript Frontend**: 30/30 tests PASSING [x]
- **Makefiles**: All 3 frontends + root Makefile [x]
- **Documentation**: Markdownlint clean [x]

---

## Previously Remaining Tasks (NOW COMPLETE)

### ~~Task 1: Complete TypeScript Test Suite~~ [x]

**File**: `subnet-calculator/frontend-typescript-vite/tests/frontend.spec.ts`

**Requirements**:

1. Rewrite file with tests 01-30 in canonical order
1. Skip tests 31-32 (progressive enhancement - N/A for SPAs)
1. Use Playwright Test framework syntax: `test('01 - description', ...)`
1. Ensure all tests match the specification

**Expected Result**: 30/30 tests passing

**Estimated Time**: 30 minutes

---

### Task 2: Add Makefiles to Each Frontend

Each frontend needs a `Makefile` with standardized targets.

#### Flask Frontend (frontend-python-flask/Makefile)

```makefile
.PHONY: test
test: ## Run Playwright tests
 @echo "Running Flask frontend tests..."
 @uv run pytest -v

.PHONY: test-headless
test-headless: ## Run tests in headless mode
 @uv run pytest -v --headed=false

.PHONY: install
install: ## Install dependencies
 @uv sync --extra dev

.PHONY: dev
dev: ## Run development server
 @uv run flask run

.PHONY: help
help: ## Show this help message
 @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf " %-20s %s\n", $$1, $$2}'
```

#### Static HTML Frontend (frontend-html-static/Makefile)

```makefile
.PHONY: test
test: ## Run Playwright tests
 @echo "Running Static HTML frontend tests..."
 @uv run pytest -v

.PHONY: test-docker
test-docker: ## Run tests against Docker Compose
 @uv run pytest --base-url=http://localhost:8001 -v

.PHONY: install
install: ## Install dependencies
 @uv sync --extra dev

.PHONY: serve
serve: ## Serve static files (requires Python http.server or nginx)
 @python3 -m http.server 8001

.PHONY: help
help: ## Show this help message
 @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf " %-20s %s\n", $$1, $$2}'
```

#### TypeScript Frontend (frontend-typescript-vite/Makefile)

```makefile
.PHONY: test
test: ## Run Playwright tests
 @echo "Running TypeScript frontend tests..."
 @npm test

.PHONY: test-headed
test-headed: ## Run tests with browser visible
 @npm run test:headed

.PHONY: test-ui
test-ui: ## Run tests with Playwright UI
 @npm run test:ui

.PHONY: install
install: ## Install dependencies
 @npm install

.PHONY: dev
dev: ## Run development server
 @npm run dev

.PHONY: build
build: ## Build for production
 @npm run build

.PHONY: lint
lint: ## Run linting
 @npm run lint

.PHONY: type-check
type-check: ## Run TypeScript type checking
 @npm run type-check

.PHONY: help
help: ## Show this help message
 @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf " %-20s %s\n", $$1, $$2}'
```

**Estimated Time**: 15 minutes

---

### Task 3: Update Root Makefile with Auto-Detection

**File**: `Makefile` (repository root)

**Requirement**: Remove hardcoded project paths and auto-detect projects.

**Current Approach** (hardcoded):

```makefile
python-test:
 for dir in subnet-calculator/api-fastapi-azure-function \
 subnet-calculator/api-fastapi-container-app \
 subnet-calculator/frontend-python-flask; do ...
```

**New Approach** (auto-detection):

```makefile
# Auto-detect Python projects (have pyproject.toml)
PYTHON_PROJECTS := $(shell find . -name "pyproject.toml" -not -path "*/\.*" -not -path "*/node_modules/*" | xargs -I {} dirname {})

# Auto-detect TypeScript projects (have package.json + tsconfig.json)
TYPESCRIPT_PROJECTS := $(shell find . -name "tsconfig.json" -not -path "*/\.*" -not -path "*/node_modules/*" | xargs -I {} dirname {})

# Auto-detect Terraform projects (have *.tf files)
TERRAFORM_PROJECTS := $(shell find . -name "*.tf" -not -path "*/\.*" -not -path "*/.terraform/*" | xargs -I {} dirname {} | sort -u)

python-test:
 @for dir in $(PYTHON_PROJECTS); do \
 if [ -f "$$dir/pyproject.toml" ]; then \
 echo "Testing $$dir..."; \
 (cd "$$dir" && make test) || exit 1; \
 fi; \
 done

typescript-test:
 @for dir in $(TYPESCRIPT_PROJECTS); do \
 if [ -f "$$dir/package.json" ]; then \
 echo "Testing $$dir..."; \
 (cd "$$dir" && make test) || exit 1; \
 fi; \
 done
```

**Benefits**:

- No hardcoded paths
- Automatically finds new projects
- Consistent with DRY principles
- Easier to maintain

**Estimated Time**: 20 minutes

---

## Testing Checklist

Before considering the work complete, verify:

- [ ] Flask frontend: `cd frontend-python-flask && make test` → 32/32 PASS
- [ ] Static HTML: `cd frontend-html-static && make test` → 32/32 PASS
- [ ] TypeScript: `cd frontend-typescript-vite && make test` → 30/30 PASS
- [ ] Root: `make test` runs all frontend tests successfully
- [ ] Root: `make python-test` runs only Python tests
- [ ] Root: `make typescript-test` runs only TypeScript tests
- [ ] All tests use identical element IDs and default values
- [ ] Test documentation is up to date

---

## Summary

**Total Estimated Time**: ~65 minutes

1. TypeScript test suite: 30 min
1. Add Makefiles: 15 min
1. Update root Makefile: 20 min

**Current Progress**: ~70% complete

**Remaining Work**:

- 1 test file to rewrite (TypeScript)
- 3 Makefiles to create
- 1 root Makefile to update
