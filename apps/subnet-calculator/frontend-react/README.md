# Subnet Calculator - React Frontend

React + TypeScript + Vite frontend for the subnet calculator with flexible authentication.

## Features

- **React 18** with TypeScript and Vite for fast development
- **Hybrid Authentication** - Auto-detects deployment environment:
  - Azure Web App: Easy Auth (platform-level)
  - Azure Container Apps: Easy Auth (platform-level)
  - Azure Static Web Apps: Entra ID via SWA
  - Local Development: MSAL (application-level OAuth)
  - Optional: No authentication
- **Dual-stack IP Support** - Both IPv4 and IPv6
- **Performance Timing** - Detailed API call timing with collapsible details
- **Responsive Design** - Mobile-first, works on all screen sizes
- **Dark/Light Theme** - User preference with persistence

## Architecture

### Authentication Flow

The frontend detects the deployment environment and uses the appropriate auth method:

```typescript
// config.ts determines auth method:
1. Check RUNTIME_CONFIG (injected by deployment)
2. Check VITE_AUTH_METHOD environment variable
3. Auto-detect from hostname:
   - *.azurewebsites.net → Easy Auth
   - *.azurecontainerapps.io → Easy Auth
   - *.azurestaticapps.net → Entra ID (SWA)
4. Check for MSAL config → MSAL
5. Default → No authentication
```

### Directory Structure

```text
src/
├── api/
│   └── client.ts          # API client with IPv4/IPv6 support
├── auth/
│   ├── AuthContext.tsx    # Unified auth context
│   ├── easyAuthProvider.ts # Easy Auth implementation
│   └── msalConfig.ts      # MSAL configuration
├── components/            # React components (TODO)
├── config.ts             # Runtime configuration
└── types.ts              # TypeScript type definitions
```

## Development

### Prerequisites

```bash
npm install
```

### Run Locally

```bash
# No authentication
npm run dev

# With MSAL (requires App Registration)
VITE_AUTH_METHOD=msal \
VITE_AZURE_CLIENT_ID="your-client-id" \
VITE_AZURE_TENANT_ID="your-tenant-id" \
npm run dev
```

### Configuration

#### Environment Variables

- `VITE_API_URL`: Backend API URL (default: `http://localhost:7071`)
- `VITE_AUTH_METHOD`: `none` | `easyauth` | `msal` | `entraid-swa`
- `VITE_AZURE_CLIENT_ID`: Azure AD app client ID (MSAL only)
- `VITE_AZURE_TENANT_ID`: Azure AD tenant ID (MSAL only)
- `VITE_AZURE_REDIRECT_URI`: OAuth redirect URI (MSAL only)

#### Runtime Configuration

For scenarios where build-time config isn't suitable, inject runtime config:

```html
<script>
  window.RUNTIME_CONFIG = {
    API_BASE_URL: 'https://api.example.com',
    AUTH_METHOD: 'easyauth',
  };
</script>
<script type="module" src="/src/main.tsx"></script>
```

#### Server-Side Proxy Controls

When the app runs behind a Node/Express host (e.g., Azure Web App), you can keep API details hidden:

- `API_BASE_URL`: **Set** to the public API host when the browser should call the backend directly (Static Web App / direct Easy Auth pattern).
- `PROXY_API_URL`: **Set** to the backend host when you want the Node server to proxy `/api/*` requests (Easy Auth proxy pattern). Leave `API_BASE_URL` empty so the SPA keeps using relative paths.
- `PROXY_FORWARD_EASYAUTH_HEADERS` (optional): defaults to `true`. Set to `false` to stop forwarding Easy Auth headers/cookies when proxying.
- `API_PROXY_ENABLED` (optional): set to `"true"` to force the SPA to call relative `/api/*` paths (pairs with `PROXY_API_URL`). Defaults to `false`.
- `AUTH_METHOD` or `AUTH_MODE`: either variable works; both feed `window.RUNTIME_CONFIG.AUTH_METHOD`.

With `PROXY_API_URL` configured the Node process copies the incoming Easy Auth headers (`X-ZUMO-AUTH`, `x-ms-token-*`, etc.) to the backend call so the Function App receives the visitor’s identity without ever exposing its hostname to the browser.

## Deployment

### Azure Web App with Easy Auth

You have **two deployment options** for Azure Web App:

#### Option 1: Zip Deployment (Simpler - No Containers)

Azure Web App has built-in static hosting that works perfectly with React SPAs:

```bash
# Build the app
npm run build

# Deploy the dist folder as a zip
cd dist
zip -r ../dist.zip .
cd ..

# Deploy to Azure Web App
az webapp deploy \
  --resource-group rg-app \
  --name app-react \
  --src-path dist.zip \
  --type zip
```

**Advantages:**

- No container knowledge required
- Azure provides the web server automatically
- Handles SPA routing out of the box
- Easy Auth works identically
- Simpler for teams new to containers

**Setup Easy Auth:**

1. Go to Azure Portal → App Service → Authentication
2. Add Identity Provider → Microsoft Entra ID
3. Done! Auto-detects from `*.azurewebsites.net` hostname

#### Option 2: Container Deployment (More Control)

Use the Docker image for full environment control:

```bash
# Build Docker image
docker build -t subnet-calculator-react .

# Push to Azure Container Registry
az acr build --registry myacr --image subnet-calculator-react:latest .

# Create Web App with container
az webapp create \
  --resource-group rg-app \
  --name app-react \
  --plan asp-linux \
  --deployment-container-image-name myacr.azurecr.io/subnet-calculator-react:latest
```

**Advantages:**

- Same image runs locally, CI/CD, and production
- Full control over nginx configuration
- Works identically on Web App, Container Apps, AKS

**Setup Easy Auth:**
Same as Option 1 - configure via Azure Portal

### Azure Container Apps with Easy Auth

1. Deploy React app to Azure Container Apps (container only)
2. Enable Easy Auth via `az containerapp auth update`
3. No code changes needed - auto-detects Easy Auth from hostname

### Azure Static Web Apps with Entra ID

1. Deploy via `swa deploy` or GitHub Actions
2. Configure authentication in `staticwebapp.config.json`
3. No code changes needed - auto-detects SWA from hostname

### AKS with OAuth2 Proxy Sidecar

1. Deploy OAuth2 Proxy as sidecar container
2. Configure OAuth2 Proxy to inject headers
3. Set `VITE_AUTH_METHOD=easyauth` (OAuth2 Proxy mimics Easy Auth)

## Testing

```bash
# Unit tests
npm test

# E2E tests with Playwright
npm run test:e2e

# Type checking
npm run type-check

# Linting
npm run lint
```

### Proxy Mode Regression Test

To verify the Easy Auth proxy runtime configuration keeps API calls relative (mirroring the Azure Web App stack), run the dedicated Playwright spec:

```bash
npm run test -- tests/proxy-mode.spec.ts
```

The test injects `window.RUNTIME_CONFIG` at startup, so it works against the default Vite dev server—no Azure resources required.

## Docker Build

```bash
docker build -t subnet-calculator-react .
docker run -p 8080:8080 subnet-calculator-react
```

## Status

**Complete** - Production-ready React frontend with full feature parity.

### Features

- [x] Project structure with Vite + React + TypeScript
- [x] Flexible configuration system
- [x] Hybrid authentication (Easy Auth + MSAL + SWA + None)
- [x] API client with IPv4/IPv6 dual-stack support
- [x] Complete React UI with Pico CSS
- [x] Results display with validation, private check, Cloudflare, subnet info
- [x] Theme switching with localStorage persistence
- [x] Performance timing with collapsible API call details
- [x] Docker configuration with nginx
- [x] Comprehensive test suite (40+ tests)
- [x] Biome linting and formatting
- [x] Complete documentation

## Using with Makefile

```bash
make install     # Install dependencies
make dev         # Start development server
make test        # Run Playwright tests
make lint        # Run linting
make build       # Build for production
make docker-build # Build Docker image
make docker-run  # Run in container
```
