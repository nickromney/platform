# Azure Static Web Apps Configuration Files

This directory contains production-ready configuration files for Azure Static Web Apps (SWA) deployments.

## Configuration Files

### 1. staticwebapp-noauth.config.json

**Purpose:** No authentication - completely public access

**Use Cases:**

- Stack 03: Public demo applications
- Stack 04: Managed functions without authentication
- Documentation sites
- Public tools

**Features:**

- Anonymous access to all routes
- SPA navigation fallback
- Security headers (X-Content-Type-Options, X-Frame-Options, etc.)
- Standard caching for static assets

**Usage:**

```bash
cp staticwebapp-noauth.config.json dist/staticwebapp.config.json
swa deploy --app-location dist --api-location "" --deployment-token "${TOKEN}"
```

### 2. staticwebapp-entraid.config.json

**Purpose:** Microsoft Entra ID (Azure AD) authentication with secure OAuth2 code flow

**Use Cases:**

- Stack 05a: Frontend-only authentication
- Stack 05b: Linked backend with authentication (RECOMMENDED)
- Stack 05c: Double authentication
- Stack 06: Network-secured with authentication
- Stack 07: Fully private architecture
- Stack 09: Managed functions with authentication
- Enterprise applications
- Internal tools

**Features:**

- All routes require authentication
- Auto-redirect to Entra ID login on 401
- Secure OAuth2 Authorization Code Flow (not exposed in URL)
- Tenant-specific endpoints (not /common/)
- PKCE protocol support for SPAs

**Setup Guide:** See `ENTRAID-SETUP-GUIDE.md` for complete step-by-step instructions

- Uses clientIdSettingName and clientSecretSettingName (secure pattern)
- HttpOnly cookies for security
- Enhanced security headers (HSTS, etc.)
- No-cache policy for authenticated content

**Required Settings:**

```bash
az staticwebapp appsettings set \
 --name swa-name \
 --resource-group rg-name \
 --setting-names \
 AZURE_CLIENT_ID="your-client-id" \
 AZURE_CLIENT_SECRET="your-client-secret"
```

**Usage:**

```bash
cp staticwebapp-entraid.config.json dist/staticwebapp.config.json
swa deploy --app-location dist --api-location "" --deployment-token "${TOKEN}"
```

### 3. staticwebapp-managed.config.json

**Purpose:** Configuration optimized for managed functions

**Use Cases:**

- Stack 04: Managed functions (westeurope)
- Stack 09: Managed functions with Entra ID
- EU-based applications where westeurope is acceptable
- Simplified deployment scenarios

**Features:**

- Anonymous access (combine with entraid config for authentication)
- Specifies Python 3.11 runtime for managed functions
- SPA navigation fallback
- Standard security headers

**Usage:**

```bash
# For managed functions, api_location must point to function code
cp staticwebapp-managed.config.json dist/staticwebapp.config.json
swa deploy \
 --app-location dist \
 --api-location ../api-fastapi-azure-function \
 --deployment-token "${TOKEN}"
```

## GitHub Actions Workflows

### swa-managed-functions.yml

**Purpose:** Deploy frontend and API functions together as managed functions

**Key Characteristics:**

- `api_location` points to function app source code
- SWA deploys and manages the API
- Functions run in westeurope (SWA-managed infrastructure)
- Suitable for Stack 04 and Stack 09

**Secrets Required:**

- `AZURE_STATIC_WEB_APPS_API_TOKEN`: SWA deployment token

**Usage:**

1. Get deployment token:

 ```bash
 az staticwebapp secrets list \
 --name swa-name \
 --resource-group rg-name \
 --query properties.apiKey -o tsv
 ```

1. Add to GitHub Secrets as `AZURE_STATIC_WEB_APPS_API_TOKEN`
1. Push to main branch

### swa-byo-functions.yml

**Purpose:** Deploy frontend only, using Bring Your Own Functions

**Key Characteristics:**

- `api_location` is empty string
- Function app deployed separately via other scripts
- Optional backend linking step (commented out)
- Suitable for Stack 03, 05a, 05b, 05c, 06, 07, 08

**Secrets Required:**

- `AZURE_STATIC_WEB_APPS_API_TOKEN`: SWA deployment token
- Optional (for backend linking):
- `AZURE_CREDENTIALS`: Service principal credentials
- `AZURE_CLIENT_ID`: Service principal client ID
- `AZURE_TENANT_ID`: Tenant ID
- `SWA_NAME`: Static Web App name
- `RESOURCE_GROUP`: Resource group name
- `FUNCTION_APP_RESOURCE_ID`: Full resource ID of function app
- `FUNCTION_APP_REGION`: Function app region (e.g., uksouth)

**Usage:**

1. Deploy function app separately:

 ```bash
 cd ~/Developer/personal/azure-tui/infrastructure/azure
 export LOCATION=uksouth
 ./10-function-app.sh
 ./21-deploy-function.sh
 ```

1. Configure GitHub secrets
1. Push to main branch

## Configuration Schema

All configuration files follow the Azure Static Web Apps schema:

```json
{
 "$schema": "https://json.schemastore.org/staticwebapp.config.json"
}
```

## Common Configuration Patterns

### Navigation Fallback for SPA

All configurations include:

```json
{
 "navigationFallback": {
 "rewrite": "/index.html",
 "exclude": ["/api/*", "/*.{css,scss,js,png,gif,ico,jpg,svg}"]
 }
}
```

This ensures:

- Client-side routing works (all non-asset routes serve index.html)
- API routes are excluded (not rewritten)
- Static assets are excluded (served as-is)

### Security Headers

Standard security headers included in all configs:

- `X-Content-Type-Options: nosniff` - Prevent MIME sniffing
- `X-Frame-Options: DENY` - Prevent clickjacking
- `X-XSS-Protection: 1; mode=block` - Enable XSS protection

Additional headers for authenticated configs:

- `Strict-Transport-Security: max-age=31536000; includeSubDomains` - Enforce HTTPS

### Caching Strategy

**Public content (no auth):**

```json
{
 "globalHeaders": {
 "cache-control": "public, max-age=3600"
 }
}
```

**Authenticated content:**

```json
{
 "globalHeaders": {
 "cache-control": "no-cache, no-store, must-revalidate"
 }
}
```

## Entra ID Setup

### 1. Create App Registration

Via Azure Portal:

1. Navigate to Entra ID → App registrations
1. Click "New registration"
1. Name: "Subnet Calculator SWA"
1. Supported account types: Single tenant (or multi-tenant as needed)
1. Redirect URI: Web → `https://your-swa.azurestaticapps.net/.auth/login/aad/callback`
1. Click "Register"
1. Note the "Application (client) ID"
1. Go to "Certificates & secrets" → "New client secret"
1. Add secret and copy the value

Via Azure CLI:

```bash
# Create app registration
az ad app create \
 --display-name "Subnet Calculator SWA" \
 --sign-in-audience AzureADMyOrg \
 --web-redirect-uris \
 "https://your-swa.azurestaticapps.net/.auth/login/aad/callback" \
 "https://your-custom-domain.com/.auth/login/aad/callback"

# Get client ID
APP_ID=$(az ad app list --display-name "Subnet Calculator SWA" --query "[0].appId" -o tsv)

# Create client secret
SECRET=$(az ad app credential reset --id "${APP_ID}" --append --query password -o tsv)

# Save for later
echo "AZURE_CLIENT_ID=${APP_ID}"
echo "AZURE_CLIENT_SECRET=${SECRET}"
```

### 2. Configure SWA Settings

```bash
az staticwebapp appsettings set \
 --name swa-name \
 --resource-group rg-name \
 --setting-names \
 AZURE_CLIENT_ID="${AZURE_CLIENT_ID}" \
 AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"
```

### 3. Add Custom Domain Redirect URIs

When using custom domains, add redirect URIs for each domain:

```bash
az ad app update \
 --id "${AZURE_CLIENT_ID}" \
 --web-redirect-uris \
 "https://your-swa.azurestaticapps.net/.auth/login/aad/callback" \
 "https://your-custom-domain.com/.auth/login/aad/callback"
```

## Testing

### Local Testing with SWA CLI

```bash
# Start frontend dev server
cd frontend-typescript-vite
npm run dev

# In another terminal, start API (if BYO)
cd api-fastapi-azure-function
func start

# In another terminal, start SWA CLI
cd frontend-typescript-vite
swa start http://localhost:5173 --api-location http://localhost:7071
```

**Note:** SWA CLI emulates authentication locally but does not fully enforce route protection. Test authentication in Azure for production behavior.

### Production Testing

After deployment:

```bash
# Get SWA URL
az staticwebapp show \
 --name swa-name \
 --resource-group rg-name \
 --query defaultHostname -o tsv

# Test endpoints
curl https://your-swa.azurestaticapps.net
curl https://your-swa.azurestaticapps.net/api/v1/health
curl https://your-swa.azurestaticapps.net/.auth/me
```

## Troubleshooting

### Issue: Authentication not working

**Symptoms:** No redirect to login, or login fails

**Solutions:**

1. Verify SWA settings:

 ```bash
 az staticwebapp appsettings list --name swa-name --resource-group rg-name
 ```

1. Check redirect URIs in Entra ID app registration
1. Verify staticwebapp.config.json is in deployed dist folder
1. Check browser console for errors

### Issue: API calls returning 404

**Symptoms:** `/api/*` routes not found

**Solutions:**

1. For BYO: Verify api_location is empty string
1. For managed: Verify api_location points to function code
1. Check if backend is linked (BYO):

 ```bash
 az staticwebapp show --name swa-name --resource-group rg-name --query linkedBackends
 ```

### Issue: Wrong region for functions

**Symptoms:** Data sovereignty requirements not met

**Solutions:**

1. For UK/Australia/specific regions: Use BYO functions (api_location="")
1. For EU: Can use managed functions (api_location="path/to/api")
1. Verify function app region:

 ```bash
 az functionapp show --name func-name --resource-group rg-name --query location
 ```

## References

- [Azure Static Web Apps Configuration](https://learn.microsoft.com/azure/static-web-apps/configuration)
- [SWA Authentication](https://learn.microsoft.com/azure/static-web-apps/authentication-authorization)
- [SWA API Integration](https://learn.microsoft.com/azure/static-web-apps/apis-overview)
- [Configuration Schema](https://json.schemastore.org/staticwebapp.config.json)
- [SWA-AUTHENTICATION-ARCHITECTURES.md](docs/SWA-AUTHENTICATION-ARCHITECTURES.md) - Comprehensive guide to all stack patterns
