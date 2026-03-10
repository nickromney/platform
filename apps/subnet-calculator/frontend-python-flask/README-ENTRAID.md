# Entra ID Authentication for Flask Frontend - Quick Start

## What Was Added

We've added **optional** Entra ID authentication to the Flask frontend using Microsoft's MSAL library. This allows you to:

1. **Test Entra ID OAuth flows** with full visibility and control
2. **Debug the circular redirect issue** by comparing with SWA's built-in auth
3. **Deploy to Azure App Service** with complete authentication control

## New Files

- **`auth.py`** - MSAL-based OAuth 2.0 implementation
- **`ENTRAID.md`** - Comprehensive guide (setup, testing, deployment, troubleshooting)
- **`azure-stack-13-flask-entraid.sh`** - Deployment script to Azure App Service

## Quick Start (Local Testing)

### 1. Get Your Credentials

```bash
# From Azure CLI
TENANT_ID=$(az account show --query tenantId -o tsv)
echo "AZURE_TENANT_ID=$TENANT_ID"

# Then create app registration (see ENTRAID.md for details)
```

### 2. Set Environment Variables

```bash
export AZURE_CLIENT_ID="370b8618-a252-442e-9941-c47a9f7da89e"      # Your app ID
export AZURE_CLIENT_SECRET="b4p8Q~D6aXs1vWYWB0zR9..."                # Your secret
export AZURE_TENANT_ID="e4cd804d-7192-4483-92de-7d574cff9827"      # Your tenant
export FLASK_SECRET_KEY="dev-key-change-in-production"               # Session key
```

### 3. Install & Run

```bash
cd subnet-calculator/frontend-python-flask
uv sync --extra dev
uv run flask run
# Visit http://localhost:5000
```

### 4. What You'll See

1. **No credentials set** → App runs normally (no auth required)
2. **Credentials set** → Redirects to Entra ID login
3. **After login** → Shows user info at top, includes logout button
4. **User info comes from Entra ID** claims (name, email, etc.)

## Key Implementation Points

### `auth.py` - OAuth 2.0 Authorization Code Flow

```python
# Login initiates OAuth
GET /login → Redirect to Entra ID

# OAuth callback processes authorization code
GET /auth/callback?code=xxx → Exchange for tokens → Store in session

# Logout clears session
GET /logout → Clear session → Redirect to Entra ID logout
```

### `app.py` - Optional Authentication

```python
# Auth initialized from env vars (or None if not set)
auth = init_auth(app)

# In index route - check if auth is configured
if auth and auth.is_authenticated() is False:
    return auth.login()

# Pass user info to template
user_info = auth.get_user() if auth else None
```

### `templates/index.html` - User Display

```html
{% if user_info %}
  👤 {{ user_info.get('name') }}
  ({{ user_info.get('email') }})
  [Logout]
{% endif %}
```

## Deployment to Azure App Service

```bash
# Prerequisites: Create app registration with redirect URI
# https://your-app-service.azurewebsites.net/auth/callback

# Deploy
AZURE_CLIENT_ID="xxx" \
AZURE_CLIENT_SECRET="xxx" \
AZURE_TENANT_ID="xxx" \
./azure-stack-13-flask-entraid.sh
```

Script will:

1. Create App Service Plan (B1 Linux)
2. Create App Service with Python 3.11
3. Configure Entra ID settings
4. Deploy Flask app

## Troubleshooting

### Local Testing Issues

| Problem | Solution |
|---------|----------|
| "Not authenticated" when env vars are set | Clear `.flask_session` folder, restart Flask |
| "Redirect URI Mismatch" | Check redirect URI in app registration matches `http://localhost:5000/auth/callback` |
| "State Validation Failed" | Clear browser cookies, try incognito mode |

### Production Issues

See **`ENTRAID.md`** - Complete troubleshooting guide with detailed explanations.

## How This Helps Debug SWA's Entra ID Issue

### What We Know About Your SWA Issue

1. **Problem**: Circular redirect on SWA's Entra ID login
2. **Root Cause** (our analysis):
   - SWA uses `response_mode=form_post` by default
   - Your app registration only had SPA redirect URIs
   - We added web redirect URIs to fix it

### With This Flask Implementation

1. **Test the same OAuth flow** in a controlled environment
2. **See every step** of the authorization code exchange
3. **Validate tokens** independently
4. **Compare behavior** between Flask (working) and SWA (broken)

If Flask works with same app registration but SWA doesn't:

- Check SWA's staticwebapp.config.json for issues
- Look for response override misconfigurations
- Verify SWA's MSAL integration settings

## Environment Variables Reference

| Variable | Required for Auth | Example | Notes |
|----------|------------------|---------|-------|
| `AZURE_CLIENT_ID` | Yes | `370b8618-...` | App registration ID |
| `AZURE_CLIENT_SECRET` | Yes | `sWa~...` | App secret (expires) |
| `AZURE_TENANT_ID` | Yes | `e4cd804d-...` | Your tenant |
| `REDIRECT_URI` | Optional | `https://app.azurewebsites.net/auth/callback` | Defaults to `http://localhost:5000/auth/callback` |
| `FLASK_SECRET_KEY` | Recommended | Generate with `openssl rand -hex 32` | Session encryption key |
| `FLASK_ENV` | Optional | `production` or `development` | Affects cookie security |

## Testing Different Scenarios

### Scenario 1: No Auth (Existing Behavior)

```bash
# Don't set any AZURE_* variables
uv run flask run
# App works as before, no login required
```

### Scenario 2: OAuth with Local Entra ID

```bash
# Set credentials
export AZURE_CLIENT_ID="..."
export AZURE_CLIENT_SECRET="..."
export AZURE_TENANT_ID="..."
uv run flask run
# Visit http://localhost:5000 → redirects to login
```

### Scenario 3: Production Deployment

```bash
# Deploy to Azure App Service with full OAuth
./azure-stack-13-flask-entraid.sh
# Visit https://your-app-service.azurewebsites.net
# Full Entra ID authentication with real HTTPS
```

## Next Steps

1. **Read `ENTRAID.md`** for comprehensive documentation
2. **Test locally** with your Entra ID app registration
3. **Compare with SWA** to debug circular redirect
4. **Deploy to App Service** if you want production version

## Files Modified

- `pyproject.toml` - Added msal, flask-session, cryptography
- `app.py` - Integrated authentication, added user info
- `templates/index.html` - Added user display, logout button

## Files Created

- `auth.py` - MSAL authentication module (139 lines)
- `ENTRAID.md` - Complete implementation guide (400+ lines)
- `README-ENTRAID.md` - This quick reference
- `azure-stack-13-flask-entraid.sh` - Deployment script (280+ lines)

## Security Notes

- **HTTPS Only** - Enforced in production (`FLASK_ENV=production`)
- **Secure Cookies** - HttpOnly, Secure, SameSite=Lax
- **PKCE** - Automatic with MSAL's authorization code flow
- **State Validation** - CSRF protection via state parameter
- **Token Validation** - MSAL validates all tokens

## References

- Microsoft MSAL Python: <https://github.com/AzureAD/microsoft-authentication-library-for-python>
- Flask-Session: <https://flask-session.readthedocs.io/>
- OAuth 2.0 Code Flow: <https://datatracker.ietf.org/doc/html/rfc6749#section-1.3.1>

---

**Author's Note**: This implementation lets you debug Entra ID authentication with full visibility. Use it to understand the OAuth flow and compare with SWA's opaque authentication system.
