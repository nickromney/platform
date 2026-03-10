# IP Subnet Calculator - Flask Frontend

A modern web frontend for the IP Subnet Calculator API with IPv4 and IPv6 support, built with Flask and styled with Pico CSS.

## Features

- **IPv4 & IPv6 Support**: Full support for both IPv4 and IPv6 addresses and CIDR notation
- **Address Validation**: Client-side validation for both IP versions
- **Real-time API Lookup**: Fetches comprehensive subnet information from the backend API
- **Address Classification**: Identifies RFC1918 private ranges (IPv4), RFC6598 shared address space (IPv4), and Cloudflare IP ranges (IPv4 and IPv6)
- **Cloud Provider Modes**: Select between Azure, AWS, OCI, or Standard IP reservation rules
- **Subnet Analysis**: For CIDR ranges, displays:
  - Network and broadcast addresses
  - Netmask and wildcard mask
  - Usable IP range
  - Total and usable address counts
  - Cloud provider-specific reservations
- **Performance Timing**:
  - With JavaScript: Rich collapsible details with timestamps for each API call (matches TypeScript frontend)
  - Without JavaScript: Simple response time display in server-rendered results
- **Quick Examples**: One-click buttons for common test cases (RFC1918, RFC6598, Public, Cloudflare, IPv6)
- **Copy to Clipboard**: Copy usable IP ranges with a single click
- **Clear Results**: Reset form and results with one button
- **Theme Switcher**: Toggle between dark mode (default) and light mode with preference saved
- **Mobile Responsive**: Works seamlessly on phones, tablets, and desktops
- **Modern UI**: Clean, responsive design using Pico CSS
- **Hybrid Authentication**:
  - **Azure deployment**: Uses Easy Auth (platform-level, zero code)
  - **Local development**: Uses MSAL library (application-level)
  - Automatic environment detection - single codebase for both
- **Progressive Enhancement**:
  - Works without JavaScript (server-side rendering fallback)
  - Readable without CSS (semantic HTML structure)
  - API fallback to [cidr.xyz](https://cidr.xyz) when backend is unavailable

## Prerequisites

- Python 3.11+
- [uv](https://github.com/astral-sh/uv) package manager
- The IPv4 Subnet Calculator API running (default: `http://localhost:7071`)

## Installation

Install dependencies using uv:

```bash
uv sync
```

## Running Locally

### Development Server

Run with Flask's built-in development server:

```bash
uv run flask run
```

Or:

```bash
uv run python app.py
```

The application will be available at `http://localhost:5000`.

### Production Server

Run with Gunicorn (production WSGI server):

```bash
uv run gunicorn --bind 0.0.0.0:8000 --workers 4 app:app
```

## Configuration

### Authentication

The Flask app uses **hybrid authentication** - automatically detecting the environment:

**Azure Deployment (Easy Auth)**:

- Authentication handled by Azure platform (Web App or Container Apps)
- No environment variables needed for auth
- Zero code changes required
- See [EASY-AUTH-SETUP.md](EASY-AUTH-SETUP.md) for setup guide

**Local Development (MSAL)**:

- Authentication handled by MSAL library in code
- Requires environment variables:

```bash
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"
export REDIRECT_URI="http://localhost:5000/auth/callback"
```

**Optional authentication**:

- If auth env vars are not set, the app runs without authentication
- Useful for local testing without Entra ID setup

### API Configuration

The API base URL can be configured via environment variable:

```bash
export API_BASE_URL=http://localhost:7071/api/v1
uv run flask run
```

Or for production:

```bash
export API_BASE_URL=https://your-api.azurewebsites.net/api/v1
uv run gunicorn --bind 0.0.0.0:8000 --workers 4 app:app
```

## Docker Deployment

The Dockerfile uses a 2-stage build:

1. **Stage 1**: Install Python dependencies with uv
2. **Stage 2**: Copy everything to minimal runtime image

### Using Docker

Build the Docker image:

```bash
docker build -t subnet-calculator-frontend .
```

Run the container:

```bash
# Connect to local API running via Azure Functions (port 7071)
docker run -p 8000:8000 \
  -e API_BASE_URL=http://host.docker.internal:7071/api/v1 \
  subnet-calculator-frontend

# Connect to containerized API (port 8080)
docker run -p 8000:8000 \
  -e API_BASE_URL=http://host.docker.internal:8080/api/v1 \
  subnet-calculator-frontend

# Connect to deployed API (production)
docker run -p 8000:8000 \
  -e API_BASE_URL=https://your-api.azurewebsites.net/api/v1 \
  subnet-calculator-frontend
```

**Note**: `host.docker.internal` works on Docker Desktop (Mac/Windows). On Linux, use `--add-host=host.docker.internal:host-gateway`.

### Using Podman

Build the Podman image:

```bash
podman build -t subnet-calculator-frontend .
```

Run the container:

```bash
# Connect to local API running via Azure Functions (port 7071)
podman run -p 8000:8000 \
  -e API_BASE_URL=http://host.containers.internal:7071/api/v1 \
  subnet-calculator-frontend

# Connect to containerized API (port 8080)
podman run -p 8000:8000 \
  -e API_BASE_URL=http://host.containers.internal:8080/api/v1 \
  subnet-calculator-frontend

# Connect to deployed API (production)
podman run -p 8000:8000 \
  -e API_BASE_URL=https://your-api.azurewebsites.net/api/v1 \
  subnet-calculator-frontend
```

**Note**: Podman uses `host.containers.internal` instead of `host.docker.internal`.

### Running Both Containers Together

The recommended way to run both the frontend and API together is using the compose files in the parent directory:

```bash
# From the subnet-calculator directory (parent)
cd ..
docker compose up
```

Or with Podman:

```bash
cd ..
podman-compose up
```

This will start both the API (port 8080) and frontend (port 8000) with proper networking configured.

See [../README.md](../README.md) for complete Docker Compose documentation.

## Usage

1. Enter an IPv4 address (e.g., `192.168.1.1`), IPv6 address (e.g., `2001:db8::1`), or CIDR range (e.g., `10.0.0.0/24` or `2001:db8::/32`) manually, **or** click one of the example buttons
2. Click "Lookup" to fetch information from the API (example buttons automatically trigger lookup)
3. View the results in the table, including:
   - Address type (single address or network)
   - IP version (IPv4 or IPv6)
   - Classification (RFC1918 private, Cloudflare, etc.)
   - For networks: usable IP range, netmask, total addresses, etc.
   - Performance timing (response time and API call breakdown)

## Example Addresses

The UI includes quick-access buttons for common test cases:

**IPv4:**

- **RFC1918 (Private)**: `10.0.0.0/24` - Standard private network range
- **RFC6598 (Shared Address Space)**: `100.64.0.1` - Carrier-grade NAT address
- **Public IP (Non-Cloudflare)**: `8.8.8.8` - Google DNS (public internet)
- **Cloudflare Public IP**: `104.16.1.1` - Cloudflare's network

**IPv6:**

- **IPv6 Network**: `2001:db8::/32` - Documentation prefix
- **Cloudflare IPv6**: `2606:4700:4700::1111` - Cloudflare DNS

## Architecture

- **Frontend**: Flask with Jinja2 templates
- **Styling**: Tailwind CSS (CDN)
- **API Client**: Python `requests` library
- **Production Server**: Gunicorn WSGI server
- **Validation**: Client-side JavaScript validation with server-side API calls

## API Integration

The frontend automatically detects IPv4 vs IPv6 addresses and calls the appropriate API endpoints:

**IPv4 Endpoints:**

- `POST /api/v1/ipv4/validate` - Validate IPv4 address/CIDR
- `POST /api/v1/ipv4/check-private` - Check RFC1918/RFC6598 (IPv4 only)
- `POST /api/v1/ipv4/check-cloudflare` - Check Cloudflare ranges
- `POST /api/v1/ipv4/subnet-info` - Get subnet information (for networks)

**IPv6 Endpoints:**

- `POST /api/v1/ipv6/validate` - Validate IPv6 address/CIDR
- `POST /api/v1/ipv6/check-cloudflare` - Check Cloudflare ranges
- `POST /api/v1/ipv6/subnet-info` - Get subnet information (for networks)

Note: IPv6 does not have an equivalent to RFC1918 private addresses, so the `check-private` endpoint is IPv4-only.

### Server-to-Server API Calls

**Important:** The browser never directly calls the backend API. Instead, Flask makes server-to-server calls using Python's `requests` library.

**Request Flow:**

```text
Browser → Flask (/lookup endpoint)
          ↓ Python requests library
          Flask → API (http://api:8080/api/v1/*)
          ↓
Browser ← Flask (aggregated JSON response)
```

**What you see in browser DevTools:**

- AJAX calls to `http://localhost:8000/lookup` (Flask endpoint)
- NO calls to `http://localhost:8080` (backend API)

**To see the actual API calls:**

View Flask container logs:

```bash
# Docker
docker compose logs -f frontend

# Podman
podman logs -f subnet-calculator_frontend_1
```

**Why this architecture?**

- **CORS avoidance**: Server-to-server requests bypass CORS restrictions
- **API aggregation**: Single browser request triggers 3-4 backend API calls
- **Error handling**: Flask can catch API failures and provide fallback to cidr.xyz
- **Progressive enhancement**: Works without JavaScript (form POST directly to Flask)

## Architecture: Why Flask?

**Could this just be static HTML?** Yes, for the JavaScript-enabled path. But Flask enables **progressive enhancement** - the app works at three levels:

### Three Layers of Functionality

1. **Full JavaScript (best experience)**

   - AJAX calls to Flask `/lookup` endpoint
   - Flask aggregates 3-4 API calls
   - Instant results without page reload
   - Client-side validation

2. **No JavaScript, with Flask (core functionality)**

   - Traditional form POST to Flask `/` route
   - Flask calls API from server-side
   - Renders results in Jinja2 template
   - Full functionality, just with page reload

3. **No JavaScript, no Flask (limited options)**
   - Could POST form directly to API with `<form action="http://api/v1/ipv4/validate">`
   - But: CORS would likely block cross-origin requests
   - API returns JSON, not HTML - browser can't render it
   - No way to aggregate multiple API calls
   - No error handling or cidr.xyz fallback
   - Template variables (`{{ }}`) wouldn't render

### What Flask Provides

**Server-Side Rendering (No-JS Fallback):**

```python
if request.method == 'POST':
    results = perform_lookup(address, mode)
    return render_template('index.html', results=results)
```

**API Aggregation:**

- Single backend call → multiple API endpoints
- Solves the CORS problem (server-to-server requests)
- Transforms JSON responses into HTML (Jinja2 templates)
- Unified error handling
- Smart categorization (4xx validation vs 5xx/connection errors)

**Error Handling Logic:**

- Distinguishes invalid input from API unavailability
- cidr.xyz fallback for availability issues only
- Clear, contextual error messages

**Template Rendering:**

```jinja2
{% if results %}
  {{ results.subnet.first_usable_ip }}
{% endif %}
```

**Why not just HTML5 forms posting to the API?**

While HTML5 forms _can_ POST to any URL, this approach has critical limitations:

- **CORS blocking**: Browser blocks cross-origin form responses (security)
- **Content-Type mismatch**: API returns JSON, browser expects HTML
- **No aggregation**: Can't call 4 endpoints from one form submit
- **No error logic**: Can't distinguish validation errors from API downtime
- **No fallback**: Can't suggest cidr.xyz when API is down

Flask solves these by acting as a **backend-for-frontend (BFF)** - it's the translation layer that makes progressive enhancement actually work.

## Error Handling

The application implements comprehensive error handling at multiple levels:

### Client-Side Validation (JavaScript enabled)

- **Input format**: Regex validation for IPv4 and IPv6 addresses and CIDR notation
- **IPv4 octet validation**: Ensures each octet is 0-255
- **IPv6 format validation**: Validates hexadecimal groups and colon separators
- **Immediate feedback**: Shows error message without API call
- **User-friendly**: Explains expected format for both IP versions

### Server-Side Validation

- **4xx errors**: Invalid input caught by API (e.g., "10.10.10/42")

  - Returns `400 Bad Request` with detailed error
  - Shows validation error to user
  - **No cidr.xyz suggestion** (not an availability issue)

- **5xx errors**: Server errors or API unavailable
  - Returns `503 Service Unavailable`
  - Shows error with **cidr.xyz fallback link**
  - Pre-fills user's address in cidr.xyz URL

### Connection Errors

- **Network failure**: API completely unreachable
  - Caught by Python `requests` library
  - Treated same as 5xx (suggests cidr.xyz)
  - Helps user complete their task despite API issues

### Example Error Messages

**Invalid input (client-side):**

```text
Please enter a valid IP address (IPv4: 192.168.1.1 or 10.0.0.0/24, IPv6: 2001:db8::1 or 2001:db8::/32)
```

**Invalid input (server-side):**

```text
Invalid input: '10.10.10/42' does not appear to be an IPv4 or IPv6 address
```

**API unavailable:**

```text
Backend API Unavailable: Connection refused

Try using cidr.xyz as an alternative:
https://cidr.xyz/#10.0.0.0/24
```

## Progressive Enhancement

The frontend is built with progressive enhancement principles:

### With JavaScript (Enhanced Experience)

When JavaScript is enabled, the frontend provides a rich SPA-like experience matching the TypeScript frontend:

- **AJAX lookups**: No page reloads
- **Client-side validation**: Instant feedback for invalid addresses
- **Rich timing display**: Collapsible details with request/response timestamps for each API call
- **Interactive features**: Theme switcher, example buttons, copy to clipboard, clear results
- **Real-time updates**: Loading states, error messages, dynamic results

### Without JavaScript (Core Functionality)

- Form submits via traditional POST to server
- Server-side rendering of results
- All core functionality works (lookup, validation, results display)
- Shows `<noscript>` warning about limited interactivity
- **Theme**: Stays on default dark theme (no switcher visible)
- **Validation**: API validates input (not browser), providing detailed error messages
- **Timing**: Simple response time display (no collapsible details)
- **Hidden features** (require JavaScript):
  - Theme switcher
  - Example buttons (RFC1918, RFC6598, IPv6)
  - Copy to clipboard button
  - Clear results button
  - Real-time client-side validation
  - Rich timing details with timestamps

### Without CSS

- Semantic HTML ensures readability
- Uses `<header>`, `<table>`, proper headings
- Content structure preserved
- All information accessible

### API Unavailable

The frontend distinguishes between validation errors and API unavailability:

**Invalid Input (4xx errors):**

- Shows validation error from API
- No cidr.xyz suggestion
- Example: `Invalid input: '10.10.10/42' does not appear to be an IPv4 or IPv6 address`

**API Unavailable (connection errors, timeouts, 5xx errors):**

- Detects failure and returns 503 HTTP status
- Suggests alternative with direct link to [cidr.xyz](https://cidr.xyz)
- Pre-fills address in cidr.xyz URL (e.g., `https://cidr.xyz/#10.0.0.0/24`)

Example error message:

```text
Backend API Unavailable: Connection refused

Try using cidr.xyz as an alternative:
https://cidr.xyz/#10.0.0.0/24
```

## Testing

The project includes comprehensive Playwright tests for frontend functionality.

### Run Tests

```bash
# Install Playwright browsers (first time only)
uv run playwright install chromium

# Run all tests
uv run pytest test_frontend.py

# Run with verbose output
uv run pytest test_frontend.py -v

# Run specific test
uv run pytest test_frontend.py::TestFrontend::test_responsive_layout_mobile -v
```

### Test Coverage

The test suite includes 35 tests covering:

- **Page Load**: Verify page loads successfully
- **Input Validation**: Test IPv4, IPv6, and CIDR validation (client-side)
- **Example Buttons**: Test quick-access buttons populate input correctly (IPv4 and IPv6)
- **Cloud Mode Selector**: Verify all provider modes are available
- **Clear Button**: Test form reset functionality
- **Copy Button**: Verify copy-to-clipboard button presence
- **Responsive Layouts**: Test mobile (375px), tablet (768px), and desktop (1920px) viewports
- **Theme Management**: Test dark/light mode switching and persistence
- **Error Handling**: Verify error and loading states
- **Results Table**: Test table structure and visibility
- **No JavaScript Fallback**: Verify form works with traditional POST
- **JavaScript-Only Features**: Verify copy/clear buttons and examples hidden without JS
- **Semantic HTML**: Test structure for accessibility without CSS
- **Noscript Warning**: Verify warning message exists
- **IPv6 Support**: Test IPv6 address validation, CIDR notation, and example buttons

## Development

The project uses:

- `uv` for fast, reliable Python dependency management
- Flask for the web framework
- Gunicorn for production WSGI serving
- **Pico CSS v2** via CDN (~10KB) for modern, minimal styling
- Custom CSS (`static/style.css`) for app-specific styles
- 2-stage Docker builds for optimized images
- Playwright for end-to-end frontend testing

### Styling Approach

The frontend uses a lightweight CSS stack:

- **Pico CSS v2** (CDN): Provides semantic HTML styling, form elements, tables
  - Built-in dark and light themes
  - Theme switching via `data-theme` attribute
  - Responsive by default
- **Custom CSS** (`static/style.css`): ~200 lines for app-specific needs
  - Form layout (flexbox)
  - Example buttons with color coding
  - Alert styles
  - Theme switcher button (fixed position)
  - Utility classes (hidden, text-center, etc.)
  - Loading spinner
  - Responsive design

**Theme Switching:**

- **Dark mode by default** (easier on the eyes for network ops!)
- Toggle button (top-right) switches to light mode
- Preference saved in `localStorage`
- Works without JavaScript (stays on default dark theme)
- Sun emoji ☀️ in dark mode, moon emoji 🌙 in light mode

**Why no Tailwind/build step?**

- Simpler deployment (no Node.js dependency)
- Faster development (no build watching)
- Smaller footprint (~12KB total CSS vs 40KB+ Tailwind)
- Pico handles 90% of styling automatically
- Built-in theme switching!
