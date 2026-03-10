# Production Deployment Guide

Complete guide for deploying the subnet calculator to a permanent Azure environment with custom domain configuration.

## Overview

This guide covers deploying 6 complete stacks to Azure for long-term testing and production use:

1. **Storage Static Website** - Classic static hosting (~$0.05/month)
1. **Flask App Service** - Server-side rendering (~$13/month)
1. **SWA TypeScript (No Auth)** - Public API access (~$0/month)
1. **SWA TypeScript (JWT Auth)** - Custom authentication (~$0/month)
1. **SWA TypeScript (Entra ID)** - Enterprise SSO (~$0/month)

## Prerequisites

### Required Tools

```bash
# Azure CLI
brew install azure-cli
az login

# Azure Functions Core Tools
brew install azure-functions-core-tools

# Node.js and npm
brew install node

# Python and uv
brew install python@3.11
curl -LsSf https://astral.sh/uv/install.sh | sh

# SWA CLI (auto-installs if missing)
npm install -g @azure/static-web-apps-cli
```

### Azure Subscription

- Active Azure subscription
- Permissions to create resources
- Recommended: Separate resource group for production

### Azure Static Web Apps Hosting Plans

**Standard Tier** (DEFAULT - recommended for production):

- ~$9/month per Static Web App
- Custom domains with free SSL/TLS certificates (up to 5 per app)
- Entra ID (Azure AD) custom authentication
- 100 GB bandwidth/month
- 2 GB storage
- Managed or Bring Your Own Functions
- SLA available

**Free Tier** (testing only):

- $0/month
- Azure-provided domain only (`*.azurestaticapps.net`)
- No custom authentication
- 100 GB bandwidth/month
- 0.5 GB storage (1/4 of Standard)
- Managed Functions (limited regions: westus2, centralus, eastus2, westeurope, eastasia)

**DEFAULT**: All deployment scripts now use **Standard tier** by default.

To use Free tier for testing:

- Via script: `STATIC_WEB_APP_SKU=Free ./00-static-web-app.sh`
- Or for stack scripts: `STATIC_WEB_APP_SKU=Free ./stack-03-swa-typescript-noauth.sh`

### Custom Domain

- Domain registered (example: `publiccloudexperiments.net`)
- DNS provider with API or manual configuration (Cloudflare recommended)
- SSL/TLS certificate (provided automatically by Azure)
- **Requires Standard tier for Static Web Apps**

## Environment Configuration

### Default Settings

The deployment scripts use these defaults:

```bash
# Location
LOCATION=uksouth # UK South by default

# Custom Domain
CUSTOM_DOMAIN=publiccloudexperiments.net # Change to your domain

# Resource naming (auto-generated with random suffix)
RESOURCE_GROUP=rg-subnet-calc-prod # Or auto-detected
```

### Override Defaults

```bash
# Use different region
export LOCATION="eastus"

# Use different domain
export CUSTOM_DOMAIN="yourdomain.com"

# Use specific resource group
export RESOURCE_GROUP="rg-my-project"
```

## Deployment Sequence

### Phase 1: Core Infrastructure

#### 1. Create Resource Group

```bash
az group create \
 --name rg-subnet-calc-prod \
 --location uksouth
```

#### 2. Set Environment

**Bash/Zsh:**

```bash
export RESOURCE_GROUP="rg-subnet-calc-prod"
export LOCATION="uksouth"
export CUSTOM_DOMAIN="publiccloudexperiments.net"
```

**Nushell:**

```nushell
$env.RESOURCE_GROUP = "rg-subnet-calc-prod"
$env.LOCATION = "uksouth"
$env.CUSTOM_DOMAIN = "publiccloudexperiments.net"
```

**Or use automated setup:**

```bash
# Bash/Zsh
source ./setup-env.sh

# Nushell
source setup-env.nu
# or
overlay use setup-env.nu
setup
```

### Phase 2: Deploy All Stacks

#### Stack 0: Storage Static Website

**What**: Classic static website hosting on Azure Storage

**Cost**: ~$0.05/month

```bash
cd ~/Developer/personal/azure-tui/infrastructure/azure

# Create storage account with static website
./05-static-website-storage.sh

# Deploy static HTML frontend
SUBDOMAIN="static" ./25-deploy-static-website-storage.sh
```

**DNS**: `static.publiccloudexperiments.net` → CNAME to `<storage>.z33.web.core.windows.net`

#### Stack 3: SWA TypeScript (No Auth)

**What**: Modern SPA with public API access

**Cost**: ~$9/month (Standard tier - DEFAULT)

**Resources created**:

- Static Web App: `swa-subnet-calc-noauth`
- Function App: Auto-detected or created

```bash
# Deploy complete stack (Standard tier - default)
SUBDOMAIN="noauth" ./stack-03-swa-typescript-noauth.sh

# Use Free tier for testing (Azure domain only)
SUBDOMAIN="noauth" STATIC_WEB_APP_SKU=Free ./stack-03-swa-typescript-noauth.sh
```

**DNS**: `noauth.publiccloudexperiments.net` → CNAME to `swa-subnet-calc-noauth.azurestaticapps.net`

#### Stack 4: SWA TypeScript (JWT Auth)

**What**: Modern SPA with JWT authentication

**Cost**: ~$9/month (Standard tier - DEFAULT)

**Resources created**:

- Static Web App: `swa-subnet-calc-jwt`
- Function App: Auto-detected or created

```bash
# Deploy complete stack (Standard tier - default)
SUBDOMAIN="jwt" \
JWT_USERNAME="demo" \
JWT_PASSWORD="your-secure-password" \
./stack-04-swa-typescript-jwt.sh

# Use Free tier for testing (Azure domain only)
SUBDOMAIN="jwt" \
JWT_USERNAME="demo" \
JWT_PASSWORD="your-secure-password" \
STATIC_WEB_APP_SKU=Free \
./stack-04-swa-typescript-jwt.sh
```

**DNS**: `jwt.publiccloudexperiments.net` → CNAME to `swa-subnet-calc-jwt.azurestaticapps.net`

**Login Credentials**: Username/password set during deployment

#### Stack 5: SWA TypeScript (Entra ID)

**What**: Modern SPA with enterprise SSO

**Cost**: ~$9/month (Standard tier - REQUIRED for Entra ID)

**Resources created**:

- Static Web App: `swa-subnet-calc-entraid`
- Function App: Auto-detected or created

**Requirements**:

- **Standard tier REQUIRED** - Entra ID custom authentication not available on Free tier
- Entra ID App Registration (see [Entra ID Setup](#entra-id-setup))

```bash
# Deploy complete stack (Standard tier - default, required for Entra ID)
SUBDOMAIN="entraid" \
AZURE_CLIENT_ID="<your-client-id>" \
AZURE_CLIENT_SECRET="<your-client-secret>" \
./stack-05-swa-typescript-entraid.sh
```

**DNS**: `entraid.publiccloudexperiments.net` → CNAME to `swa-subnet-calc-entraid.azurestaticapps.net`

**Note**: Entra ID authentication requires Standard tier - Free tier will not work for this stack.

#### Stack 6: Flask App Service

**What**: Server-side rendered Flask application

**Cost**: ~$13/month (App Service Plan B1)

```bash
# Deploy complete stack
SUBDOMAIN="flask" ./stack-06-flask-appservice.sh
```

**DNS**: `flask.publiccloudexperiments.net` → CNAME to `<appservice>.azurewebsites.net`

## DNS Configuration

See [DNS-CONFIGURATION.md](./DNS-CONFIGURATION.md) for detailed instructions.

### Quick Summary

Add CNAME records in Cloudflare:

```text
static.publiccloudexperiments.net → <storage>.z33.web.core.windows.net
noauth.publiccloudexperiments.net → <swa-noauth>.<region>.azurestaticapps.net
jwt.publiccloudexperiments.net → <swa-jwt>.<region>.azurestaticapps.net
entraid.publiccloudexperiments.net → <swa-entraid>.<region>.azurestaticapps.net
flask.publiccloudexperiments.net → <appservice>.azurewebsites.net
```

**Cloudflare Settings:**

- Proxy status: DNS only (grey cloud)
- SSL/TLS mode: Full (not Full Strict)
- Always Use HTTPS: On

## Entra ID Setup

Required for Stack 5 (SWA TypeScript with Entra ID auth).

### 1. Create App Registration

```bash
# Via Azure Portal
1. Navigate to: Azure Active Directory → App registrations
1. Click "New registration"
1. Name: subnet-calc-entraid
1. Supported account types: Single tenant
1. Click "Register"
```

### 2. Configure Redirect URI

After deployment, add redirect URI:

```text
https://entraid.publiccloudexperiments.net/.auth/login/aad/callback
```

Or Azure default:

```text
https://<swa-name>.<region>.azurestaticapps.net/.auth/login/aad/callback
```

### 3. Create Client Secret

```bash
# In App Registration
1. Go to "Certificates & secrets"
1. Click "New client secret"
1. Description: swa-auth-prod
1. Expires: 24 months
1. Click "Add"
1. COPY THE VALUE IMMEDIATELY (shown only once)
```

### 4. Configure SWA

```bash
# Set app settings
az staticwebapp appsettings set \
 --name swa-subnet-calc-entraid \
 --resource-group rg-subnet-calc-prod \
 --setting-names \
 AZURE_CLIENT_ID="<application-client-id>" \
 AZURE_CLIENT_SECRET="<client-secret-value>"
```

## Custom Domain Configuration

### Storage Static Website

```bash
# After DNS propagation
STORAGE_ACCOUNT_NAME="<your-storage-account>"

az storage account update \
 --name ${STORAGE_ACCOUNT_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --custom-domain static.${CUSTOM_DOMAIN}
```

### Static Web Apps

```bash
# For each SWA
STATIC_WEB_APP_NAME="swa-subnet-calc-noauth"
CUSTOM_HOSTNAME="noauth.${CUSTOM_DOMAIN}"

az staticwebapp hostname set \
 --name ${STATIC_WEB_APP_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --hostname ${CUSTOM_HOSTNAME}
```

### App Service (Flask)

```bash
APP_SERVICE_NAME="app-flask-subnet-calc"
CUSTOM_HOSTNAME="flask.${CUSTOM_DOMAIN}"

az webapp config hostname add \
 --webapp-name ${APP_SERVICE_NAME} \
 --resource-group ${RESOURCE_GROUP} \
 --hostname ${CUSTOM_HOSTNAME}
```

## Cost Summary

### Production Configuration (DEFAULT - Standard Tier)

Using custom domains (`publiccloudexperiments.net`) with Standard tier:

| Stack | Resource | Monthly Cost | Notes |
|-------|----------|--------------|-------|
| **Storage** | Storage Account | ~$0.05 | Static website with custom domain |
| **Stack 3** | SWA (Standard) | ~$9.00 | swa-subnet-calc-noauth |
| **Stack 3** | Function App | ~$0.00 | Consumption, minimal traffic |
| **Stack 4** | SWA (Standard) | ~$9.00 | swa-subnet-calc-jwt |
| **Stack 4** | Function App | ~$0.00 | Shared with Stack 3 |
| **Stack 5** | SWA (Standard) | ~$9.00 | swa-subnet-calc-entraid (Entra ID requires Standard) |
| **Stack 5** | Function App | ~$0.00 | Shared with Stack 3/4 |
| **Stack 6** | App Service Plan B1 | ~$13.00 | Runs 24/7 |
| **Stack 6** | App Service | $0.00 | Uses existing plan |
| **Total (all stacks)** | | **~$40.05/month** | All features enabled |

### Testing Configuration (Free Tier)

For cost-conscious testing with Azure domains (`*.azurestaticapps.net`):

| Stack | Resource | Monthly Cost | Notes |
|-------|----------|--------------|-------|
| **Storage** | Storage Account | ~$0.05 | Static website only |
| **Stack 3** | SWA (Free) | $0.00 | Azure domain only, 0.5GB storage |
| **Stack 3** | Function App | ~$0.00 | Consumption, minimal traffic |
| **Stack 4** | SWA (Free) | $0.00 | Azure domain only, 0.5GB storage |
| **Stack 4** | Function App | ~$0.00 | Shared with Stack 3 |
| **Stack 5** | N/A | N/A | **Not available** - Entra ID requires Standard |
| **Stack 6** | App Service Plan B1 | ~$13.00 | Runs 24/7 |
| **Stack 6** | App Service | $0.00 | Uses existing plan |
| **Total (without Stack 5)** | | **~$13.05/month** | Limited features |

### Cost Optimization

#### Option 1: Serverless Only with Free Tier (~$0.05/month)

For testing without custom domains:

- Storage static website
- SWA stacks (3, 4) on Free tier
- Function Apps (Consumption)
- Skip Stack 5 (Entra ID requires Standard)
- Skip Stack 6 (Flask App Service)

#### Option 2: Production with Minimal SWAs (~$22.05/month)

Deploy only needed stacks with Standard tier:

- Storage static website (~$0.05)
- Stack 5: SWA with Entra ID (~$9)
- Stack 6: Flask App Service (~$13)
- Shared Function App (~$0)

#### Option 3: Shared Resources

All stacks can share the same Function App to reduce complexity:

```bash
# Use same FUNCTION_APP_NAME for all deployments
export FUNCTION_APP_NAME="func-subnet-calc-shared"
```

**Upgrade Path**: Start with Free tier for testing, upgrade to Standard only when ready for production with custom domains.

## Monitoring and Maintenance

### Health Checks

```bash
# Function App health
curl https://func-subnet-calc.azurewebsites.net/api/v1/health

# Static websites
curl https://static.publiccloudexperiments.net
curl https://noauth.publiccloudexperiments.net
curl https://jwt.publiccloudexperiments.net
curl https://entraid.publiccloudexperiments.net
curl https://flask.publiccloudexperiments.net
```

### Logs

```bash
# Function App logs
az functionapp log tail \
 --name func-subnet-calc \
 --resource-group ${RESOURCE_GROUP}

# App Service logs (Flask)
az webapp log tail \
 --name app-flask-subnet-calc \
 --resource-group ${RESOURCE_GROUP}
```

### Updates

```bash
# Redeploy Function App
cd ~/Developer/personal/azure-tui/infrastructure/azure
./22-deploy-function-zip.sh

# Redeploy Frontend (any stack)
./20-deploy-frontend.sh

# Redeploy Storage static website
./25-deploy-static-website-storage.sh

# Redeploy Flask App Service
./50-deploy-flask-app-service.sh
```

## Backup and Disaster Recovery

### Configuration Backup

```bash
# Export all resource configurations
az group export \
 --name ${RESOURCE_GROUP} \
 --include-parameter-default-value \
 > backup-$(date +%Y%m%d).json
```

### Code Backup

- All code is in git repository
- Function App code: `api-fastapi-azure-function/`
- Frontend code: `frontend-*/`
- Infrastructure scripts: `~/Developer/personal/azure-tui/infrastructure/azure/`

### Secrets Backup

**CRITICAL**: Store these securely (password manager/vault):

- JWT secret keys
- Entra ID client secrets
- Storage account access keys
- Function App deployment keys

## Troubleshooting

### DNS Not Resolving

```bash
# Check DNS propagation
dig noauth.publiccloudexperiments.net

# Check Cloudflare DNS
nslookup noauth.publiccloudexperiments.net 1.1.1.1
```

**Solution**: Wait 5-10 minutes for DNS propagation

### SSL Certificate Errors

**SWA**: Certificates are automatic after custom domain validation

**App Service**: Enable managed certificate:

```bash
az webapp config ssl create \
 --resource-group ${RESOURCE_GROUP} \
 --name app-flask-subnet-calc \
 --hostname flask.publiccloudexperiments.net

az webapp config ssl bind \
 --resource-group ${RESOURCE_GROUP} \
 --name app-flask-subnet-calc \
 --certificate-thumbprint <thumbprint> \
 --ssl-type SNI
```

### Deployment Failures

```bash
# Check resource status
az resource list \
 --resource-group ${RESOURCE_GROUP} \
 --query "[].{Name:name, Type:type, Status:provisioningState}" \
 -o table

# View activity log
az monitor activity-log list \
 --resource-group ${RESOURCE_GROUP} \
 --max-events 20 \
 -o table
```

### Function App Cold Start

First request after idle period may be slow (Consumption plan).

**Solutions**:

1. Use App Service Plan instead (always warm)
1. Implement health check pings (costs minimal)
1. Upgrade to Premium plan (more expensive)

## Security Best Practices

### 1. Restrict Function App Access

For production, configure IP restrictions:

```bash
az functionapp config access-restriction add \
 --resource-group ${RESOURCE_GROUP} \
 --name func-subnet-calc \
 --rule-name AllowOnlySWA \
 --action Allow \
 --ip-address <swa-outbound-ip>/32 \
 --priority 100
```

### 2. Enable Application Insights

```bash
az functionapp config appsettings set \
 --name func-subnet-calc \
 --resource-group ${RESOURCE_GROUP} \
 --settings \
 APPINSIGHTS_INSTRUMENTATIONKEY="<key>" \
 APPLICATIONINSIGHTS_CONNECTION_STRING="<connection-string>"
```

### 3. Rotate Secrets Regularly

- JWT secrets: Every 90 days
- Entra ID client secrets: Before expiration (24 months max)
- Storage keys: Every 180 days

### 4. Enable HTTPS Only

All scripts enable this by default, but verify:

```bash
# Function App
az functionapp show \
 --name func-subnet-calc \
 --resource-group ${RESOURCE_GROUP} \
 --query httpsOnly

# App Service
az webapp show \
 --name app-flask-subnet-calc \
 --resource-group ${RESOURCE_GROUP} \
 --query httpsOnly
```

## Cleanup

### Delete All Resources

```bash
# Complete cleanup
az group delete \
 --name ${RESOURCE_GROUP} \
 --yes \
 --no-wait
```

### Delete Individual Stacks

```bash
# Delete specific SWA
az staticwebapp delete \
 --name swa-subnet-calc-noauth \
 --resource-group ${RESOURCE_GROUP} \
 --yes

# Delete Function App
az functionapp delete \
 --name func-subnet-calc \
 --resource-group ${RESOURCE_GROUP}

# Delete App Service
az webapp delete \
 --name app-flask-subnet-calc \
 --resource-group ${RESOURCE_GROUP}

# Delete App Service Plan (if not shared)
az appservice plan delete \
 --name plan-subnet-calc \
 --resource-group ${RESOURCE_GROUP} \
 --yes
```

## References

- [Azure Static Web Apps Documentation](https://docs.microsoft.com/azure/static-web-apps/)
- [Azure Functions Documentation](https://docs.microsoft.com/azure/azure-functions/)
- [Azure App Service Documentation](https://docs.microsoft.com/azure/app-service/)
- [Cloudflare DNS Documentation](https://developers.cloudflare.com/dns/)
- [Entra ID App Registration](https://docs.microsoft.com/azure/active-directory/develop/quickstart-register-app)
