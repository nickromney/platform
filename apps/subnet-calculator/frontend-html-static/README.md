# IPv4 Subnet Calculator - Static Frontend

Pure client-side HTML/JavaScript/CSS implementation demonstrating the "old way" of building web applications.

## Architecture

This is a **static site** that makes direct API calls from the browser:

```text
User's Browser
    ↓
HTML/CSS/JavaScript (served as static files)
    ↓
Direct API calls (visible in browser Network tab)
    ↓
FastAPI Backend (http://localhost:7071 or http://localhost:8080)
```

### Key Characteristics

- **No server-side rendering**: Pure HTML/JS/CSS files
- **CORS required**: Browser security model enforces CORS headers
- **Visible API calls**: All requests visible in browser DevTools Network tab
- **No API key hiding**: Everything is client-side (suitable for public APIs)
- **Deployment**: Can be hosted on any static file server

### Comparison with Flask Frontend

| Aspect                      | Static (This)               | Flask (Server-Side)             |
| --------------------------- | --------------------------- | ------------------------------- |
| **Architecture**            | Client calls API directly   | Server calls API, renders HTML  |
| **CORS**                    | Required (browser security) | Not required (server-to-server) |
| **API Visibility**          | Visible in Network tab      | Hidden from user                |
| **Deployment**              | Static hosting (cheap/free) | Requires Python runtime         |
| **Caching**                 | Easy (CDN-friendly)         | Requires server-side setup      |
| **Progressive Enhancement** | JavaScript required         | Works without JS                |

## Quick Start

### Prerequisites

1. **API must be running**:

   ```bash
   # Option 1: Docker Compose (recommended)
   cd ..
   docker compose up

   # Option 2: Azure Functions locally
   cd ../api-fastapi-azure-function
   uv run func start
   ```

2. **Python 3.x** (for local development server)

### Run Locally

```bash
# Start the static file server
uv run python serve.py

# Or on custom port
uv run python serve.py 3000
```

Open `http://localhost:8001` in your browser.

### Alternative Serving Methods

```bash
# Python built-in (simpler, no CORS headers)
python -m http.server 8001

# Node.js http-server
npx http-server -p 8001

# VS Code Live Server extension
# Right-click index.html → "Open with Live Server"
```

## Configuration

### API Endpoint

Edit `js/config.js` to change the API URL:

```javascript
const API_CONFIG = {
  BASE_URL: "http://localhost:7071", // Default: Azure Functions local
  // ...
};
```

**Common configurations:**

| Environment             | API_BASE_URL                         |
| ----------------------- | ------------------------------------ |
| Azure Functions (local) | `http://localhost:7071` (default)    |
| Docker Compose          | `http://localhost:8080`              |
| Azure (production)      | `https://your-app.azurewebsites.net` |

### Environment-Specific Configuration

For production deployments, you can override the API URL with a script tag:

```html
<!-- index.html -->
<script>
  // Set before loading config.js
  window.API_BASE_URL = "https://your-production-api.azurewebsites.net";
</script>
<script src="js/config.js"></script>
```

## CORS Configuration

The API already has CORS enabled in `host.json`:

```json
{
  "http": {
    "customHeaders": {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Accept"
    }
  }
}
```

### Production CORS

For production, update `allowedOrigins` to specific domains:

```json
{
  "http": {
    "customHeaders": {
      "Access-Control-Allow-Origin": "https://your-frontend.github.io"
      // ...
    }
  }
}
```

## File Structure

```text
frontend-html-static/
├── index.html           # Main page
├── css/
│   └── style.css        # Custom styles (+ Pico CSS from CDN)
├── js/
│   ├── config.js        # API configuration
│   └── app.js           # Application logic
├── serve.py             # Development server
└── README.md            # This file
```

## Features

- **IPv4/IPv6 validation**: Validates addresses and CIDR ranges
- **RFC1918 detection**: Identifies private IP ranges
- **RFC6598 detection**: Identifies shared address space
- **Cloudflare detection**: Checks if IP is in Cloudflare ranges
- **Subnet calculations**: Cloud provider-specific reservations (Azure, AWS, OCI, Standard)
- **Dark/Light mode**: Theme switcher with localStorage persistence
- **Copy to clipboard**: One-click results copying
- **Example buttons**: Pre-filled examples for quick testing

## Browser Compatibility

- **Modern browsers**: Chrome, Firefox, Safari, Edge (latest)
- **Required features**:
  - Fetch API
  - ES6 (arrow functions, const/let, template literals)
  - localStorage
  - Clipboard API (for copy button)

No polyfills included - this is a modern browser-only demo.

## Development

### API Endpoints Used

All endpoints are POST requests to `/api/v1/*`:

1. `GET /health` - API health check
2. `POST /ipv4/validate` - Validate address/network
3. `POST /ipv4/check-private` - RFC1918/RFC6598 check
4. `POST /ipv4/check-cloudflare` - Cloudflare range check
5. `POST /ipv4/subnet-info` - Subnet calculations

### Viewing API Calls

Open browser DevTools → Network tab:

- Filter: `Fetch/XHR`
- See all requests with headers, payload, and CORS headers
- This is the key educational aspect of this static frontend

## Security Considerations

### What This Demo Shows

- CORS headers are required for browser security
- All API calls are visible to the user
- No secrets can be hidden client-side
- API must have authentication/authorization (not implemented here)

### Production Recommendations

1. **Add API authentication**:

   - API keys (visible but rate-limited)
   - OAuth 2.0 / OpenID Connect
   - Azure AD authentication

2. **Restrict CORS origins**:

   - Change `Access-Control-Allow-Origin: *`
   - To specific domains: `https://your-site.com`

3. **Rate limiting**:

   - Azure API Management
   - Cloudflare
   - Function-level quotas

4. **Content Security Policy (CSP)**:

   ```html
   <meta
     http-equiv="Content-Security-Policy"
     content="default-src 'self'; script-src 'self'; connect-src https://your-api.com"
   />
   ```

## Troubleshooting

### CORS Errors

```text
Access to fetch at 'http://localhost:7071/api/v1/health' from origin
'http://localhost:8001' has been blocked by CORS policy
```

**Solution:** Ensure API has CORS headers (check `host.json`).

### API Unavailable

```text
API Unavailable: Failed to fetch
```

**Solutions:**

1. Start the API: `uv run func start` or `docker compose up`
2. Check API URL in `js/config.js`
3. Verify API is responding: `curl http://localhost:7071/api/v1/health`

### Mixed Content (HTTPS/HTTP)

```text
Mixed Content: The page at 'https://...' was loaded over HTTPS, but
requested an insecure resource 'http://...'
```

**Solution:** When deploying to HTTPS, ensure API is also HTTPS.

## Next Steps

- Add error boundaries for better error handling
- Implement request/response caching
- Add loading states with skeleton screens
- Build process (Vite, webpack) for production
- Add TypeScript for type safety
- Service Worker for offline support
- Progressive Web App (PWA) features

## Educational Value

This static frontend demonstrates:

1. **Client-side architecture**: How SPAs work under the hood
2. **CORS mechanics**: Why and how browsers enforce same-origin policy
3. **API contracts**: RESTful API design with JSON
4. **Browser DevTools**: Network tab, Console, debugging
5. **Deployment options**: Various static hosting platforms
6. **Security trade-offs**: Client-side vs server-side rendering

Compare with `frontend-python-flask/` to understand the architectural differences.
