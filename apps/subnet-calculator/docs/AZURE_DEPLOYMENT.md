# Azure Deployment Guide

## Architecture

Two deployment options are available:

1. **Separate Resources (Recommended)**: Azure Static Web App (frontend) + Azure Function App (backend)
1. **Integrated (Future)**: Azure Static Web App with managed functions

This guide covers Option 1: Separate Resources.

```text
┌─────────────────────────────────────┐
│ Azure Static Web App (Free SKU) │
│ - TypeScript Vite SPA │
│ - Global CDN │
│ - Region: Central US │
└──────────────┬──────────────────────┘
 │
 │ HTTPS
 │
┌──────────────▼──────────────────────┐
│ Azure Function App (Consumption) │
│ - Python 3.11 │
│ - FastAPI │
│ - Subnet calculation API │
│ - Region: Any (e.g., South Central)│
└─────────────────────────────────────┘
```

## Prerequisites

**Required Tools:**

- Azure CLI: `brew install azure-cli`
- Azure Functions Core Tools: `brew install azure-functions-core-tools`
- Node.js and npm: `brew install node`
- Python 3.11+: `brew install python@3.11`
- uv: `curl -LsSf https://astral.sh/uv/install.sh | sh`

**Azure Login:**

```bash
az login
```

## Region Considerations

**Static Web Apps**: Only available in specific regions

- Central US
- East US 2
- East Asia
- West Europe
- West US 2

**Function Apps**: Available in most Azure regions

- Can be in a different region than the Static Web App
- Recommend choosing region closest to your users

**Pluralsight Sandbox**: Pre-created resource group in specific region

- Resource group location may not support Static Web Apps
- Use `LOCATION` environment variable to override for SWA

## Quick Start

### 1. Set Environment Variables

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure

# For Pluralsight Sandbox
export RESOURCE_GROUP="1-xxxxx-playground-sandbox"

# For your own subscription
export RESOURCE_GROUP="rg-subnet-calc"
```

### 2. Create Infrastructure

```bash
# Create Function App (uses resource group location)
./10-function-app.sh

# Create Static Web App (override location if needed)
LOCATION=centralus ./00-static-web-app.sh
```

### 3. Deploy Applications

```bash
# Deploy Function App (backend API)
RESOURCE_GROUP="xxx" \
FUNCTION_APP_NAME="func-subnet-calc-12345" \
DISABLE_AUTH=true \
./22-deploy-function-zip.sh

# Deploy Static Web App (frontend)
RESOURCE_GROUP="xxx" \
STATIC_WEB_APP_NAME="swa-subnet-calc" \
FRONTEND=typescript \
API_URL="https://func-subnet-calc-12345.azurewebsites.net" \
./20-deploy-frontend.sh
```

## Deployment Scripts

### Infrastructure Creation

#### 00-static-web-app.sh

Creates Azure Static Web App for hosting frontend.

```bash
# With location override (required if RG location doesn't support SWA)
RESOURCE_GROUP="xxx" LOCATION="centralus" ./00-static-web-app.sh

# Uses resource group location (if supported)
RESOURCE_GROUP="xxx" ./00-static-web-app.sh
```

#### 10-function-app.sh

Creates Azure Function App for hosting backend API.

Features:

- Adds random suffix to function name for uniqueness
- Creates storage account automatically
- Configures CORS for development (allows all origins)
- Enables HTTPS-only

```bash
RESOURCE_GROUP="xxx" ./10-function-app.sh

# Custom function name (suffix still added)
RESOURCE_GROUP="xxx" FUNCTION_APP_NAME="my-func" ./10-function-app.sh
```

### Application Deployment

#### 22-deploy-function-zip.sh

Deploys Function App using Azure CLI zip deployment.

Advantages over func CLI:

- Avoids Python version mismatch issues
- Uses `az functionapp deployment source config-zip`
- Enables remote build on Azure (correct Python version)

```bash
RESOURCE_GROUP="xxx" \
FUNCTION_APP_NAME="func-subnet-calc-12345" \
DISABLE_AUTH=true \
./22-deploy-function-zip.sh
```

Options:

- `DISABLE_AUTH=true`: Disable authentication (public API)
- `DISABLE_AUTH=false`: Enable JWT authentication (default)

#### 20-deploy-frontend.sh

Deploys frontend to Static Web App.

Supported frontends:

- `typescript`: TypeScript + Vite SPA (recommended)
- `static`: Static HTML + JavaScript
- `flask`: Not supported (requires server runtime)

```bash
RESOURCE_GROUP="xxx" \
STATIC_WEB_APP_NAME="swa-subnet-calc" \
FRONTEND=typescript \
API_URL="https://func-subnet-calc-12345.azurewebsites.net" \
./20-deploy-frontend.sh
```

Features:

- Builds production bundle
- Configures API URL at build time (TypeScript)
- Uses SWA CLI with Node.js 20
- Deploys to production environment

#### 21-deploy-function.sh

Legacy deployment script using func CLI.

Issues:

- Python version mismatch with system Python
- Use `22-deploy-function-zip.sh` instead

## Example: Pluralsight Sandbox Deployment

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure

# 1. Set resource group
export RESOURCE_GROUP="1-d79b3356-playground-sandbox"

# 2. Create Function App (uses sandbox region)
./10-function-app.sh
# Output: func-subnet-calc-71416

# 3. Deploy Function App code
RESOURCE_GROUP="1-d79b3356-playground-sandbox" \
FUNCTION_APP_NAME="func-subnet-calc-71416" \
DISABLE_AUTH=true \
./22-deploy-function-zip.sh

# 4. Create Static Web App (override to Central US)
RESOURCE_GROUP="1-d79b3356-playground-sandbox" \
LOCATION="centralus" \
./00-static-web-app.sh

# 5. Deploy frontend
RESOURCE_GROUP="1-d79b3356-playground-sandbox" \
STATIC_WEB_APP_NAME="swa-subnet-calc" \
FRONTEND=typescript \
API_URL="https://func-subnet-calc-71416.azurewebsites.net" \
./20-deploy-frontend.sh
```

## Testing Deployment

### Function App

```bash
# Health check
curl https://func-subnet-calc-12345.azurewebsites.net/api/v1/health

# Test validation endpoint
curl -X POST https://func-subnet-calc-12345.azurewebsites.net/api/v1/ipv4/validate \
 -H "Content-Type: application/json" \
 -d '{"address":"192.168.1.1"}'

# API documentation
open https://func-subnet-calc-12345.azurewebsites.net/api/v1/docs
```

### Static Web App

```bash
# Open in browser
open https://proud-coast-xxxxx.1.azurestaticapps.net

# Check deployment
curl -I https://proud-coast-xxxxx.1.azurestaticapps.net
```

## Monitoring

### Function App Logs

```bash
# Tail logs
az functionapp log tail \
 --name func-subnet-calc-12345 \
 --resource-group xxx

# View log stream in portal
az functionapp browse \
 --name func-subnet-calc-12345 \
 --resource-group xxx
```

### Static Web App Status

```bash
# Show details
az staticwebapp show \
 --name swa-subnet-calc \
 --resource-group xxx

# List all environments
az staticwebapp environment list \
 --name swa-subnet-calc \
 --resource-group xxx
```

## Troubleshooting

### Python Version Mismatch

**Problem**: func CLI uses system Python 3.9, Function App expects 3.11

```text
Local python version '3.9.6' is different from the version expected
```

**Solution**: Use `22-deploy-function-zip.sh` instead of `21-deploy-function.sh`

### Static Web App Region Not Supported

**Problem**: Resource group in unsupported region (e.g., South Central US)

**Solution**: Override location when creating SWA

```bash
LOCATION=centralus ./00-static-web-app.sh
```

### Deployment Status Malformed Data

**Problem**: Deployment warnings about malformed status data

```text
WARNING: Deployment status endpoint returns malformed data. Retrying...
```

**Impact**: Informational only - deployment usually succeeds

**Verification**: Test the endpoint directly

```bash
curl https://func-app-name.azurewebsites.net/api/v1/health
```

### CORS Errors

**Problem**: Frontend cannot call Function App API

**Solution**: CORS configured automatically in `10-function-app.sh`

Verify:

```bash
az functionapp cors show \
 --name func-subnet-calc-12345 \
 --resource-group xxx
```

Manual fix:

```bash
az functionapp cors add \
 --name func-subnet-calc-12345 \
 --resource-group xxx \
 --allowed-origins "*"
```

### Function App Cold Start

**Problem**: First request takes 10-20 seconds

**Explanation**: Consumption plan has cold start delay

**Solutions**:

1. Wait for warm-up (1-2 minutes after deployment)
1. Use Premium plan (not free tier)
1. Keep function warm with scheduled pings

## Cleanup

### Remove All Resources

```bash
# Using cleanup script
./99-cleanup.sh

# Manual removal
az group delete --name xxx --yes --no-wait
```

### Remove Individual Resources

```bash
# Remove Function App
az functionapp delete \
 --name func-subnet-calc-12345 \
 --resource-group xxx

# Remove Static Web App
az staticwebapp delete \
 --name swa-subnet-calc \
 --resource-group xxx

# Remove storage account
az storage account delete \
 --name stsubnetcalc12345 \
 --resource-group xxx
```

## Cost Estimates

**Free Tier (Development)**:

- Static Web App Free: $0/month
- Function App Consumption: ~$0-5/month (1M executions free)
- Storage Account: ~$0.50/month
- Total: ~$0.50-5.50/month

**Production (Low Traffic)**:

- Static Web App Standard: $9/month
- Function App Consumption: ~$5-20/month
- Storage Account: ~$1/month
- Total: ~$15-30/month

## Security Considerations

### Development (Current Setup)

- Function App: Public access, no authentication
- Static Web App: Public access
- CORS: Allow all origins

### Production Recommendations

1. **Enable Authentication**:

- JWT tokens
- Azure AD integration
- API key management

1. **Configure CORS**:

- Restrict to SWA domain only
- Remove wildcard (`*`)

1. **Enable Application Insights**:

- Monitor usage and errors
- Set up alerts

1. **Custom Domain**:

- Use custom domain with SSL
- Azure Front Door for enterprise

## References

- [Azure Static Web Apps Documentation](https://learn.microsoft.com/en-us/azure/static-web-apps/)
- [Azure Functions Python Developer Guide](https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference-python)
- [FastAPI on Azure Functions](https://learn.microsoft.com/en-us/samples/azure-samples/fastapi-on-azure-functions/fastapi-on-azure-functions/)
- [Infrastructure Scripts README](~/Developer/personal/azure-tui/infrastructure/azure/README.md)
