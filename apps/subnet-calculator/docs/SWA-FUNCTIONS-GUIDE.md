# Azure Static Web Apps: Three Ways of Working with Functions

## Overview

Azure Static Web Apps (SWA) supports **three distinct approaches** for integrating backend APIs. This guide explains each approach, their trade-offs, and when to use each one.

---

## Quick Decision Matrix

| Approach | When to Use | Best For | Cost |
| ----------------------- | ------------------------------------------- | --------------------------------------- | ------------ |
| **Managed Functions** | EU deployments, simple APIs, GitHub Actions | Speed, simplicity, automated deployment | $9/month SWA |
| **Linked Backend** | Data sovereignty, same-origin benefits | UK/Australia, Entra ID, modern stacks | $9/month SWA |
| **Separate Deployment** | Existing function app, cross-origin API | Legacy integrations, direct API access | $9/month SWA |

---

## Approach 1: Managed Functions (SWA Deploys & Manages)

### How It Works

SWA **deploys and manages your function code** alongside the frontend.

```text
┌─────────────────────────────────────────────┐
│ Azure Static Web App │
│ ┌─────────────────────────────────────────┐ │
│ │ Frontend: TypeScript Vite (global CDN) │ │
│ └─────────────────────────────────────────┘ │
│ ┌─────────────────────────────────────────┐ │
│ │ Backend: Managed Functions (westeurope) │ │
│ │ (embedded, no separate function app) │ │
│ └─────────────────────────────────────────┘ │
└─────────────────────────────────────────────┘
```

### Deployment

**SWA CLI Configuration:**

```bash
swa deploy \
 --app-location dist \
 --api-location ../api-fastapi-azure-function \ # ← NOT empty (key difference!)
 --deployment-token "${TOKEN}"
```

**GitHub Actions:**

```yaml
- uses: Azure/static-web-apps-deploy@v1
 with:
 azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
 app_location: "frontend-typescript-vite"
 api_location: "api-fastapi-azure-function" # ← NOT empty
 output_location: "dist"
```

### Characteristics

**Managed Functions:**

- Automatic deployment (no separate function app)
- Simplified GitHub Actions workflow
- No separate function app to manage
- Included in SWA pricing
- Region locked to 5 regions
- Consumption plan only
- No VNet integration
- Limited networking

### Regions

Managed functions only available in:

- **westeurope** (EU - recommended for EU apps)
- **eastus2** (US)
- **centralus** (US)
- **westus2** (US)
- **eastasia** (Asia)

**NOT available:** UK (uksouth), Australia (australiaeast), Canada (canadacentral)

### Use Cases

**Good For:**

- EU-based applications (westeurope is acceptable)
- Simple APIs with no specific region requirements
- Teams preferring automated deployment
- Prototypes and demos
- When you don't need UK data sovereignty

 **Not For:**

- UK data sovereignty required
- Australia or Canada deployments
- Advanced networking (VNet, private endpoints)
- Premium function features
- Existing function apps to integrate

### Cost

- Included in SWA Standard pricing (~$9/month)
- No separate function app billing
- Functions share SWA consumption

### Example: Azure Stack 04 (Managed Functions, No Auth)

```bash
./azure-stack-04-swa-typescript-managed.sh

# Frontend: https://your-swa.azurestaticapps.net
# API: https://your-swa.azurestaticapps.net/api/v1/...
# Region: westeurope (SWA-managed)
```

---

## Approach 2: Linked Backend (BYO Function with SWA Proxy) RECOMMENDED

### How It Works

You **deploy function separately** in any region, then **link it to SWA** for proxy benefits.

```text
┌──────────────────────────────────────────┐
│ Azure Static Web App (global CDN) │
│ ┌──────────────────────────────────────┐ │
│ │ Frontend: TypeScript Vite │ │
│ └──────────────────────────────────────┘ │
│ │ │
│ │ Proxies /api/* to → │
│ │ │
├┤ (same-origin benefit) │
│ │
└──────────────────────────────────────────┘
 ↓
 (Private link or direct)
 ↓
┌──────────────────────────────────────────┐
│ Azure Function App (uksouth) │
│ - Public HTTP endpoint │
│ - Or private endpoint (Premium) │
└──────────────────────────────────────────┘
```

### Deployment

#### Step 1: Deploy Function App

```bash
export LOCATION=uksouth
./azure-stack-01-function-app.sh

FUNCTION_APP_ID=$(az functionapp show \
 --name func-subnet-calc \
 --resource-group rg-subnet-calc \
 --query id -o tsv)
```

#### Step 2: Deploy Frontend (SWA with empty api_location)

```bash
swa deploy \
 --app-location dist \
 --api-location "" \ # ← EMPTY (key difference!)
 --deployment-token "${TOKEN}"
```

#### Step 3: Link Backend to SWA

```bash
az staticwebapp backends link \
 --name swa-subnet-calc \
 --resource-group rg-subnet-calc \
 --backend-resource-id "${FUNCTION_APP_ID}" \
 --backend-region uksouth
```

**GitHub Actions:**

```yaml
- uses: Azure/static-web-apps-deploy@v1
 with:
 azure_static_web_apps_api_token: ${{ secrets.AZURE_STATIC_WEB_APPS_API_TOKEN }}
 app_location: "frontend-typescript-vite"
 api_location: "" # ← EMPTY (linked backend, no managed functions)
 output_location: "dist"
```

### Characteristics

**Linked Backend:**

- Full control over region (any Azure region)
- Same-origin benefits (no CORS issues)
- SWA proxy hides function URL
- HttpOnly cookies (XSS protection)
- Data sovereignty compliance
- Can use Premium plan with VNet
- Separate deployment step
- Separate function app management

### Same-Origin Benefits

**With Linked Backend:**

```javascript
// Frontend calls relative URL
fetch("/api/v1/health");

// Network tab shows:
// URL: /api/v1/health (same domain)
// No CORS preflight
// Cookie sent automatically
// Function URL not visible
```

**Without Linked Backend:**

```javascript
// Frontend must call absolute URL
fetch("https://func-subnet-calc-xyz.azurewebsites.net/api/v1/health");

// Network tab shows:
// URL: https://func-subnet-calc-xyz.azurewebsites.net/api/v1/health
// CORS preflight required
// Cross-origin, cookies not sent automatically
// Function URL visible to users
```

### Regions

Deploy to any Azure region:

- uksouth (UK)
- australiaeast (Australia)
- canadacentral (Canada)
- Any other Azure region globally

### Use Cases

**Good For (RECOMMENDED):**

- UK data sovereignty required
- Enterprise applications
- Entra ID authentication
- Same-origin benefits needed
- Modern web apps (TypeScript, React, Vue)

 **Not For:**

- Simple APIs (Managed Functions is simpler)
- EU deployments where westeurope is acceptable
- Teams that want GitHub Actions to handle everything

### Cost

- SWA Standard: ~$9/month
- Function App (Consumption): ~$0/month (free tier)
- Total: ~$9/month

### Example: Azure Stack 06 (Linked + Entra ID) - RECOMMENDED

```bash
export LOCATION=uksouth
export AZURE_CLIENT_ID="your-app-id"
export AZURE_CLIENT_SECRET="your-secret"

./azure-stack-06-swa-typescript-entraid-linked.sh

# Frontend: https://your-swa.azurestaticapps.net
# API: https://your-swa.azurestaticapps.net/api/v1/... (via proxy)
# Function: https://func-subnet-calc-xyz.azurewebsites.net (hidden)
# Region: uksouth (your choice)
# Auth: Entra ID (platform-level)
```

---

## Approach 3: Separate Deployment (BYO Function, Direct Calls)

### How It Works

You **deploy SWA and function separately** with **no linking**. Frontend calls function URL directly.

```text
┌──────────────────────────────────────────┐
│ Azure Static Web App (global CDN) │
│ ┌──────────────────────────────────────┐ │
│ │ Frontend: TypeScript Vite │ │
│ │ (configured with VITE_API_URL) │ │
│ └──────────────────────────────────────┘ │
└──────────────────────────────────────────┘
 ↓
 (CORS cross-origin)
 ↓
┌──────────────────────────────────────────┐
│ Azure Function App (uksouth) │
│ - Separate function app │
│ - Direct CORS calls │
└──────────────────────────────────────────┘
```

### Deployment

#### Step 1: Deploy Function App

```bash
export LOCATION=uksouth
./azure-stack-01-function-app.sh
```

#### Step 2: Build Frontend with API URL

```bash
export VITE_API_URL="https://func-subnet-calc-xyz.azurewebsites.net"
npm run build
```

#### Step 3: Deploy Frontend (SWA with empty api_location, no linking)

```bash
swa deploy \
 --app-location dist \
 --api-location "" \ # ← EMPTY, no linking
 --deployment-token "${TOKEN}"

# NOTE: Don't run `az staticwebapp backends link`
```

### Characteristics

**Separate Deployment:**

- Full control over region
- Existing function apps (no redeployment)
- Multi-frontend scenarios (multiple SPAs → one API)
- CORS required (extra complexity)
- Function URL visible
- More cross-origin requests

### Cross-Origin Considerations

**Frontend Code:**

```typescript
// Must send credentials for cookies
fetch("https://func-api.azurewebsites.net/api/v1/health", {
 credentials: "include", // Important!
});
```

**Function CORS Configuration:**

```bash
az functionapp cors add \
 --name func-subnet-calc \
 --resource-group rg-subnet-calc \
 --allowed-origins "https://your-swa.azurestaticapps.net"
```

### Use Cases

**Good For:**

- Existing function apps (no migration)
- Multi-frontend scenarios (mobile + web share one API)
- REST API development (direct function access)
- When SWA proxy not beneficial

 **Not For:**

- New deployments (use Linked Backend instead)
- Avoiding CORS complexity
- Same-origin benefits wanted

### Cost

- SWA Standard: ~$9/month
- Function App (Consumption): ~$0/month (free tier)
- Total: ~$9/month

### Example: Azure Stack 03 (Separate + No Auth)

```bash
export LOCATION=uksouth
export VITE_API_URL="https://func-subnet-calc-xyz.azurewebsites.net"

./azure-stack-03-swa-typescript-noauth.sh

# Frontend: https://your-swa.azurestaticapps.net
# API: https://func-subnet-calc-xyz.azurewebsites.net/api/v1/...
# Direct calls, CORS enabled
# Region: uksouth (your choice)
```

---

## Comparison Table

| Feature | Managed | Linked | Separate |
| ----------------------- | ----------------- | --------------------- | ----------------------------------------------- |
| **Deployment** | Automatic (SWA) | Manual + Link | Manual |
| **Region** | 5 regions only | All regions | All regions |
| **URL Structure** | `/api/v1/...` | `/api/v1/...` | `https://func-api.azurewebsites.net/api/v1/...` |
| **Same-Origin** | Yes (embedded) | Yes (SWA proxy) | No (cross-origin) |
| **CORS** | Not needed | Not needed | Required |
| **Function URL** | Embedded (hidden) | Linked (hidden) | Visible |
| **Data Sovereignty** | Limited | Full control | Full control |
| **VNet Integration** | No | Yes (Premium) | Yes (Premium) |
| **Portal Visibility** | Embedded in SWA | Separate function app | Separate function app |
| **Separate Management** | No | Yes | Yes |
| **Cost (Consumption)** | $9/month | $9/month | $9/month |

---

## Local Testing Equivalents

### SWA CLI Emulation

```bash
# Managed Functions equivalent
swa start dist \
 --api-location api-fastapi-azure-function

# Linked Backend equivalent
swa start http://localhost:5173 \
 --api-location http://localhost:7071

# Separate Deployment equivalent
# Build with API_URL, then run server
# Frontend calls hardcoded API_URL directly
```

---

## Authentication Implications

### Managed Functions

```bash
# If using Entra ID:
staticwebapp.config.json:
{
 "routes": [{"route": "/api/*", "allowedRoles": ["authenticated"]}],
 "auth": { ... }
}

# Result: /api/* is protected by SWA
```

### Linked Backend

```bash
# Same config, but proxy goes through SWA
# Function app doesn't need auth (SWA handles it)
# Set function to AUTH_METHOD=none or AUTH_METHOD=apim
```

### Separate Deployment

```bash
# SWA config protects /api/* routing (but no /api route exists)
# Function auth must be handled by function itself
# Set function to AUTH_METHOD=jwt or AUTH_METHOD=api_key
# Frontend must send auth headers to function
```

---

## Real-World Decision Flow

```text
START: Choose your approach

Q1: Do you need a specific region?
├─ NO → Managed Functions (westeurope is fine?)
│ └─ Yes → Azure Stack 04 (Simple, automated)
│
└─ YES → BYO Functions
 ├─ Do you want same-origin benefits?
 │ ├─ YES → Linked Backend (RECOMMENDED)
 │ │ └─ With Entra ID? → Azure Stack 06
 │ │
 │ └─ NO → Separate Deployment
 │ └─ Azure Stack 03 (Direct calls)
 │
 └─ Do you have an existing function app?
 └─ YES → Separate Deployment (easier migration)
```

---

## Migration Path

### From Managed to Linked

```bash
# 1. Stop using Managed Functions
# 2. Deploy function app separately
./azure-stack-01-function-app.sh

# 3. Link to existing SWA
az staticwebapp backends link \
 --name swa-subnet-calc \
 --resource-group rg-subnet-calc \
 --backend-resource-id "${FUNCTION_APP_ID}" \
 --backend-region uksouth

# 4. Redeploy frontend with empty api_location
swa deploy \
 --app-location dist \
 --api-location "" \
 --deployment-token "${TOKEN}"
```

### From Separate to Linked

```bash
# 1. Already have function app (separate deployment)
# 2. Link it to SWA
az staticwebapp backends link \
 --name swa-subnet-calc \
 --resource-group rg-subnet-calc \
 --backend-resource-id "${FUNCTION_APP_ID}" \
 --backend-region uksouth

# 3. Update frontend to use relative URLs
# Change: VITE_API_URL="https://func-api.azurewebsites.net"
# To: VITE_API_URL="" (empty = use /api proxy)

# 4. Redeploy frontend
swa deploy \
 --app-location dist \
 --api-location "" \
 --deployment-token "${TOKEN}"
```

---

## Conclusion

### For most deployments: Use Linked Backend (Approach 2)

- Best security (same-origin, HttpOnly cookies)
- Full control (any region)
- Flexibility (can add VNet, premium features)
- Production-ready
- Recommended for enterprises

### Use Managed Functions (Approach 1) when

- Deploying to EU only (westeurope)
- Team prefers fully automated GitHub Actions
- Simple API with no special requirements

### Use Separate Deployment (Approach 3) when

- Migrating existing systems
- Need multi-frontend sharing one API
- REST API development priorities

---

## References

- [Azure Static Web Apps Documentation](https://learn.microsoft.com/en-us/azure/static-web-apps/)
- [Azure Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/)
- [SWA Authentication Architectures](SWA-AUTHENTICATION-ARCHITECTURES.md)
- [SWA CLI Documentation](https://azure.github.io/static-web-apps-cli/)
