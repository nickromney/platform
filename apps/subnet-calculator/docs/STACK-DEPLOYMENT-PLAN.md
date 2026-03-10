# Stack Deployment Scripts - Implementation Plan

## Overview

Create three "stack" wrapper scripts that orchestrate complete end-to-end deployments with different security/architecture profiles. These will be non-numeric scripts that call the existing numbered scripts in the correct order.

## Stack Definitions

### Stack 01: Public Simple (No Auth)

**File**: `stack-01-public-simple.sh`

**Architecture**:

```text
┌─────────────────────────────────────┐
│ Azure Static Web App (Free) │
│ - Static HTML + JavaScript │
│ - Client-side only │
│ - All API calls visible in browser │
└──────────────┬──────────────────────┘
 │ HTTPS (public)
┌──────────────▼──────────────────────┐
│ Azure Function App (Consumption) │
│ - Python 3.11 FastAPI │
│ - Public endpoint │
│ - NO AUTHENTICATION │
│ - Cold start possible │
└─────────────────────────────────────┘
```

**Components**:

- Frontend: Static HTML + JavaScript (client-side only)
- Backend: Function App (Consumption plan, public)
- Authentication: None - completely open
- Use case: Quick demos, testing, learning
- Cost: ~$0 (Free tier SWA + Consumption)

**Scripts called** (in order):

1. `./00-static-web-app.sh`
1. `./10-function-app.sh`
1. `DISABLE_AUTH=true ./22-deploy-function-zip.sh`
1. `FRONTEND=static ./20-deploy-frontend.sh`

**Features**:

- Auto-detects RESOURCE_GROUP (sandbox-friendly)
- Captures Function App URL and passes to frontend deployment
- Provides final summary with both URLs
- Shows test commands
- Idempotent (can re-run safely)

**Testing**:

```bash
# After deployment
curl https://func-subnet-calc-XXXXX.azurewebsites.net/api/v1/health
open https://happy-rock-XXXXX.westus2-1.azurestaticapps.net
```

---

### Stack 02: Flask + JWT Authentication (Public with VNet)

**File**: `stack-02-flask-jwt.sh`

**Architecture**:

```text
┌─────────────────────────────────────┐
│ Flask App (Azure App Service) │
│ - Python Flask │
│ - Server-side rendering │
│ - Handles JWT auth flow │
│ - Backend calls hidden from user │
│ - Public ingress │
└──────────────┬──────────────────────┘
 │ HTTPS + JWT token
┌──────────────▼──────────────────────┐
│ Azure Function App (App Svc Plan) │
│ - Python 3.11 FastAPI │
│ - Public endpoint │
│ - REQUIRES JWT TOKEN │
│ - Validates HS256 signature │
│ - Runs on App Service Plan B1 │
│ - VNet integrated (outbound) │
└──────────────┬──────────────────────┘
 │ Outbound only
┌──────────────▼──────────────────────┐
│ Azure Virtual Network │
│ - 10.0.0.0/16 address space │
│ - Function subnet (10.0.1.0/28) │
│ - Microsoft.Web/serverFarms delegate│
│ - NSG with outbound rules │
└─────────────────────────────────────┘
```

**Components**:

- Frontend: Python Flask (server-side rendering, App Service)
- Backend: Function App (App Service Plan B1, VNet integrated)
- Networking: VNet for outbound routing
- Authentication: JWT tokens - API requires valid token
- Use case: Development/staging with authentication
- Cost: ~$0.07 for 4-hour sandbox (B1 plan ~$0.018/hour)

**Deployment Method**:

- Flask: **Zip deployment to App Service** (NO containerization)
- Function: Zip deployment (standard)
- NO Azure Container Registry required

**Scripts called** (in order):

1. `./11-create-vnet-infrastructure.sh` (VNet + subnets + NSG)
1. `PLAN_SKU=B1 ./12-create-app-service-plan.sh` (B1 Basic tier)
1. `./13-create-function-app-on-app-service-plan.sh` (Function on plan)
1. `./14-configure-function-vnet-integration.sh` (VNet integration)
1. `AUTH_METHOD=jwt ./22-deploy-function-zip.sh` (API with JWT)
1. `./50-deploy-flask-app-service.sh` (NEW - Flask to App Service)

**NEW Script Required**: `50-deploy-flask-app-service.sh`

**Purpose**: Deploy Flask application to Azure App Service using zip deployment (no containers)

**Key Features**:

- Detects or prompts for RESOURCE_GROUP
- Creates App Service (Linux, Python 3.11)
- Uses existing or creates new App Service Plan (can reuse plan from step 2)
- Zip deployment from `../../frontend-python-flask`
- Configures environment variables:
- `API_BASE_URL`: Function App URL
- `JWT_USERNAME`: Admin username for JWT login
- `JWT_PASSWORD`: Admin password (hashed with Argon2)
- `JWT_SECRET_KEY`: Shared secret with Function App
- `JWT_ALGORITHM`: HS256
- Enables HTTPS only
- Provides login URL and test credentials

**Flask App Service Details**:

- Runtime: Python 3.11 on Linux
- Startup command: `gunicorn --bind=0.0.0.0 --timeout 600 app:app`
- Requirements: Installed from `requirements.txt` during deployment
- Cost: Can share App Service Plan with Function App (no additional cost) or use separate F1 free tier

**Testing**:

```bash
# Test Function API health (should work with JWT)
curl https://func-subnet-calc-XXXXX.azurewebsites.net/api/v1/health

# Access Flask frontend
open https://app-flask-XXXXX.azurewebsites.net

# Login with credentials shown in deployment output
# Flask handles JWT authentication automatically
```

---

### Stack 03: Private VNet Architecture (Future - Deferred)

**File**: `stack-03-private-vnet.sh`

**Architecture**:

```text
Internet
 │
 ▼
┌─────────────────────────────────────┐
│ Application Gateway (WAF) │
│ - Public IP │
│ - Private Link to SWA │
│ - WAF rules for protection │
└──────────────┬──────────────────────┘
 │ Private Link
┌──────────────▼──────────────────────┐
│ Azure Static Web App (Standard) │
│ - TypeScript Vite SPA │
│ - Private Link mode │
│ - NO public access │
└──────────────┬──────────────────────┘
 │ Private traffic only
┌──────────────▼──────────────────────┐
│ Azure Function App (Private) │
│ - Private endpoint in VNet │
│ - NO public access │
│ - All traffic via VNet │
└──────────────┬──────────────────────┘
 │
┌──────────────▼──────────────────────┐
│ Azure Virtual Network │
│ - 10.0.0.0/16 address space │
│ - Function subnet (10.0.1.0/28) │
│ - Private Endpoints subnet │
│ - App Gateway subnet │
│ - NSG with strict rules │
└─────────────────────────────────────┘
```

**Components**:

- Frontend: TypeScript Vite (modern SPA)
- Backend: Function App (App Service Plan B1, private endpoint)
- Networking: Full VNet with private endpoints
- Gateway: Application Gateway with WAF
- Authentication: Configurable (can be JWT or open)
- Use case: Production-like private architecture
- Cost: ~$150/month (App Gateway ~$125/month + B1 ~$13/month + SWA Standard ~$9/month)

**Note**: This stack is **deferred** until Stack 01 and Stack 02 are tested and working. It requires:

- SWA Standard SKU ($9/month minimum)
- Application Gateway (~$150/month minimum)
- Private Link configuration
- Private endpoints for Function App

**Scripts called** (future):

1. `./00-static-web-app.sh` (with Standard SKU)
1. `./11-create-vnet-infrastructure.sh` (with App Gateway subnet)
1. `PLAN_SKU=B1 ./12-create-app-service-plan.sh`
1. `./13-create-function-app-on-app-service-plan.sh`
1. `./14-configure-function-vnet-integration.sh`
1. `./60-create-app-gateway.sh` (NEW - to be created)
1. `./61-configure-swa-private-link.sh` (NEW - to be created)
1. `./62-configure-function-private-endpoint.sh` (NEW - to be created)
1. `DISABLE_AUTH=true ./21-deploy-function.sh` (or with JWT)
1. `FRONTEND=typescript ./20-deploy-frontend.sh`

---

## Implementation Strategy

### Phase 1: Stack 01 and Stack 02 (Priority)

Focus on public deployments first as they inform the patterns for Stack 03.

**Task 1**: Create `stack-01-public-simple.sh`

- Straightforward - all scripts exist
- Good template for other stacks
- Test in Pluralsight sandbox
- Establishes wrapper script pattern

**Task 2**: Create `50-deploy-flask-app-service.sh`

- Flask deployment to App Service (zip, not container)
- Python runtime configuration
- Environment variable setup
- Gunicorn startup command

**Task 3**: Create `stack-02-flask-jwt.sh`

- Reuses VNet scripts (11-14)
- Orchestrates App Service Plan creation
- Coordinates JWT secret sharing between Function and Flask
- More complex but scripts exist

### Phase 2: Stack 03 (After 01 and 02)

**Task 4**: Research and plan Stack 03 components

- Private Link for SWA (requires Standard SKU + App Gateway)
- Private endpoints for Function App
- Application Gateway configuration
- Cost analysis and trade-offs

**Task 5**: Create new scripts (60-62) for Stack 03

**Task 6**: Create `stack-03-private-vnet.sh` wrapper

---

## File Structure

```text
~/Developer/personal/azure-tui/infrastructure/azure/
├── stack-01-public-simple.sh # NEW: Public, no auth
├── stack-02-flask-jwt.sh # NEW: Flask + JWT + VNet
├── stack-03-private-vnet.sh # NEW (future): Private VNet
├── 50-deploy-flask-app-service.sh # NEW: Flask to App Service (zip)
├── 60-create-app-gateway.sh # NEW (future): App Gateway
├── 61-configure-swa-private-link.sh # NEW (future): SWA Private Link
├── 62-configure-function-private-endpoint.sh # NEW (future): Function Private Endpoint
├── (existing 00-40 scripts unchanged)
├── docs/
│ ├── STACK-DEPLOYMENT-PLAN.md # NEW: This file
│ └── (existing docs)
└── README.md # UPDATE: Add stack documentation
```

---

## Stack Script Template

All stack scripts should follow this pattern:

```bash
#!/usr/bin/env bash
#
# stack-XX-name.sh - Deploy complete stack for [use case]
#
# Architecture:
# [ASCII diagram]
#
# Components:
# - Frontend: [type]
# - Backend: [type]
# - Authentication: [type]
#
# Cost: [estimate]
# Use case: [description]

set -euo pipefail

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step() { echo -e "${BLUE}[STEP]${NC} $*"; }

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Banner
log_info "========================================="
log_info "Stack XX: [Name]"
log_info "========================================="
log_info ""

# Step 1: [First component]
log_step "Step 1/N: Creating [component]..."
"${SCRIPT_DIR}/00-xxx.sh"

# Step 2: [Second component]
log_step "Step 2/N: Creating [component]..."
# ... capture output, pass to next step

# Final summary
log_info ""
log_info "========================================="
log_info "Stack deployment complete!"
log_info "========================================="
log_info ""
log_info "Frontend: https://[url]"
log_info "Backend API: https://[url]"
log_info ""
log_info "Test commands:"
log_info " curl https://[api-url]/api/v1/health"
log_info " open https://[frontend-url]"
log_info ""
```

---

## README Updates

Add new section after "Auto-Detection and Smart Defaults":

### Stack Deployment Scripts

Quick deployment of complete stacks with different architectures:

#### Stack 01: Public Simple (No Authentication)

```bash
./stack-01-public-simple.sh
```

- Static HTML frontend
- Public Function App (Consumption)
- No authentication
- Cost: Free
- Use case: Demos, learning, quick tests

#### Stack 02: Flask + JWT Authentication

```bash
./stack-02-flask-jwt.sh
```

- Flask frontend (App Service, zip deployment)
- Public Function App with JWT validation (App Service Plan + VNet)
- JWT authentication required
- Cost: ~$0.07 for 4-hour sandbox
- Use case: Development, staging with authentication

#### Stack 03: Private VNet Architecture (Future)

```bash
./stack-03-private-vnet.sh
```

- TypeScript Vite frontend (SWA Standard with Private Link)
- Private Function App in VNet (App Service Plan)
- Application Gateway with WAF
- Full VNet isolation
- Cost: ~$150/month
- Use case: Production-like private architecture

---

## Success Criteria

### Stack 01

1. Works end-to-end in Pluralsight sandbox
1. Creates SWA + Function App + deploys both
1. No authentication - fully public
1. Idempotent - can re-run safely
1. Clear output with URLs and test commands

### Stack 02

1. Works end-to-end in Pluralsight sandbox
1. Creates VNet + App Service Plan + Function + Flask App Service
1. JWT authentication works end-to-end
1. Flask deployed via zip (no containers)
1. Shows login flow and token usage
1. Idempotent - can re-run safely

### Stack 03

1. Deferred until Stack 01 and 02 tested
1. Requires research on Private Link + App Gateway
1. Document cost implications clearly
1. Provide fallback to cheaper alternatives

---

## Testing Strategy

### Sequential Testing in Pluralsight Sandbox

Due to Azure Static Web Apps limitation (1 per resource group on Free tier):

1. **Test Stack 01**:

- Deploy complete stack
- Verify all endpoints
- Test frontend → API calls
- Cleanup or note SWA name

1. **Test Stack 02**:

- Reuse same SWA or create new (if cleaned up)
- Deploy Flask to separate App Service
- Verify JWT authentication
- Test Flask → Function API calls
- Verify VNet integration

1. **Test Stack 03** (future):

- Requires SWA Standard SKU ($9/month minimum)
- May need separate subscription for cost reasons
- Test in personal subscription, not sandbox

### Cost Management

**Pluralsight Sandbox** (4 hours):

- Stack 01: $0 (free tier only)
- Stack 02: ~$0.07 (B1 @ $0.018/hour × 4 hours)
- Stack 03: Not feasible in sandbox (App Gateway too expensive)

**Personal Subscription**:

- Stack 01: ~$0/month (free tier, may incur minimal egress)
- Stack 02: ~$13/month (B1 always running)
- Stack 03: ~$150/month (App Gateway dominant cost)

---

## Open Questions and Decisions

### Stack 02 Decision: Zip Deployment (Decided)

**Chosen**: Zip deployment to App Service

- **Pros**: Simpler, no container registry needed, F1 free tier available
- **Cons**: Less portable than containers

**Alternative (rejected for now)**: Container Apps

- Would require Azure Container Registry
- More complex for this use case
- Can revisit if portability becomes important

### Stack 03 Decision: Defer to Phase 2

**Reasoning**:

- App Gateway costs ~$125/month minimum
- SWA Standard costs ~$9/month minimum
- Not suitable for Pluralsight sandbox (4-hour limit)
- Should establish patterns with Stack 01/02 first

**Future considerations**:

- Document as enhancement path
- Provide cost analysis
- Show migration path from Stack 02 → Stack 03

---

## Next Steps

1. **Create documentation** (this file)
1. **Implement stack-01-public-simple.sh**
1. **Implement 50-deploy-flask-app-service.sh**
1. **Implement stack-02-flask-jwt.sh**
1. **Test Stack 01** in Pluralsight sandbox
1. **Test Stack 02** in Pluralsight sandbox
1. **Update README** with stack documentation
1. **Plan Stack 03** (after Stack 01/02 validated)
