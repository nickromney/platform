# Entra ID Authentication Implementation Summary

## What Was Added

A complete Entra ID (OAuth 2.0) authentication system for the Flask frontend with **full environment variable management**.

---

## Files Created

### 1. Core Implementation

| File | Purpose | Lines |
|------|---------|-------|
| `auth.py` | MSAL-based OAuth implementation | 139 |
| `ENTRAID.md` | Comprehensive Entra ID guide | 400+ |
| `README-ENTRAID.md` | Quick start reference | 250+ |

### 2. Environment Management

| File | Purpose |
|------|---------|
| `.envrc` | direnv configuration (auto-load env vars) |
| `.env.example` | Template with all variables documented |
| `ENV-SETUP.md` | Setup guide for developers |

### 3. Deployment

| File | Purpose | Lines |
|------|---------|-------|
| `azure-stack-13-flask-entraid.sh` | Deploy to App Service | 280+ |

### 4. Updated Files

| File | Changes |
|------|---------|
| `pyproject.toml` | Added msal, flask-session, cryptography |
| `app.py` | Integrated auth, added user info |
| `templates/index.html` | User display, logout button |
| `.gitignore` | Added .env, .envrc, .flask_session/ |

---

## How It Works

### 1. Authentication Flow

```bash
User visits app
    ↓
No credentials in .env? → App runs without auth
    ↓ (Credentials configured)
    ├→ No session? → Redirect to /login
    │   ↓
    │   Entra ID authorization endpoint
    │   User logs in
    │   ↓
    │ ← Redirect to /auth/callback with code
    │   ↓
    │   Exchange code for tokens
    │   Store in session
    │   ↓
    │ → Redirect to app
    │
    └→ Has session? → Show app + user info
        Logout clears session → Redirect to Entra ID logout
```bash

### 2. Environment Variable Hierarchy

```bash
direnv (.envrc)
    ↓
    Loads .env (git-ignored)
    ↓
    Optionally loads .env.local (git-ignored, machine-specific)
    ↓
    app.py reads:
    ├─ AZURE_CLIENT_ID
    ├─ AZURE_CLIENT_SECRET
    ├─ AZURE_TENANT_ID
    ├─ REDIRECT_URI
    ├─ FLASK_SECRET_KEY
    ├─ FLASK_ENV
    ├─ API_BASE_URL
    └─ STACK_NAME
```bash

### 3. Auth Initialization

```python
# app.py
auth = init_auth(app)  # Returns None if no env vars, otherwise EntraIDAuth

# In route
if auth and auth.is_authenticated() is False:
    return auth.login()  # Redirect to OAuth
```bash

---

## Quick Start Checklist

### Local Development with direnv

- [ ] Install direnv: `brew install direnv`
- [ ] Add hook to shell: `eval "$(direnv hook bash)"` → reload shell
- [ ] Copy template: `cp .env.example .env`
- [ ] Edit `.env` with your credentials (see `ENV-SETUP.md`)
- [ ] Allow direnv: `direnv allow`
- [ ] Run Flask: `uv run flask run`
- [ ] Visit `http://localhost:5000`

### Deployment to Azure

- [ ] Ensure app registration has web redirect URI
- [ ] Set environment variables
- [ ] Run: `AZURE_CLIENT_ID="..." AZURE_CLIENT_SECRET="..." AZURE_TENANT_ID="..." ./azure-stack-13-flask-entraid.sh`
- [ ] Update app registration redirect URI with deployed URL
- [ ] Visit deployed app

---

## Files Reference

### Documentation Files

- **`ENTRAID.md`** - Start here for complete guide
  - Local setup
  - Production deployment
  - Troubleshooting
  - Security considerations

- **`ENV-SETUP.md`** - Environment configuration
  - direnv installation
  - Variable setup
  - Usage scenarios
  - Troubleshooting

- **`README-ENTRAID.md`** - Quick reference
  - What was added
  - Quick start
  - Key features
  - Next steps

### Implementation Files

- **`auth.py`** - MSAL OAuth implementation
  - `EntraIDAuth` class
  - Login/callback/logout routes
  - Session management

- **`app.py`** - Flask app updates
  - Session configuration
  - Auth initialization
  - User info display

- **`templates/index.html`** - UI updates
  - User display
  - Logout button

### Configuration Files

- **`.envrc`** - direnv loader
- **`.env.example`** - Template (check in to git)
- **`.env`** - Your credentials (git-ignored)
- **`.env.local`** - Machine-specific overrides (git-ignored)

### Deployment

- **`azure-stack-13-flask-entraid.sh`** - Azure deployment script

---

## Key Features

 **Optional Authentication**

- Works with or without credentials
- No code changes needed to enable/disable

 **Environment Management**

- Uses direnv for automatic variable loading
- .env files are git-ignored
- .env.example template is checked in

 **OAuth 2.0 Authorization Code Flow**

- Industry-standard secure pattern
- PKCE support (automatic with MSAL)
- State validation for CSRF protection

 **Production Ready**

- Secure session cookies
- HTTPS enforcement in production
- Error handling
- Logging support

 **Easy Debugging**

- Every OAuth step is visible
- Can compare with SWA's auth
- Full token access for inspection

---

## Environment Variables

### Authentication (Optional)

```bash
AZURE_CLIENT_ID           # Your app registration client ID
AZURE_CLIENT_SECRET       # Your app registration secret
AZURE_TENANT_ID          # Your Entra ID tenant ID
REDIRECT_URI             # OAuth callback URL
```bash

### Flask Configuration

```bash
FLASK_SECRET_KEY         # Session encryption key (generate: openssl rand -hex 32)
FLASK_ENV                # development or production
```bash

### Application Configuration

```bash
API_BASE_URL             # Backend API endpoint
STACK_NAME               # Display name in UI
JWT_USERNAME             # Backend auth (optional)
JWT_PASSWORD             # Backend auth (optional)
```bash

---

## Architecture

### Local Development

```bash
┌─ Your Computer ─────────────────────┐
│                                      │
│  .env (git-ignored)                  │
│    ↓                                 │
│  direnv (.envrc)                     │
│    ↓                                 │
│  Flask app (localhost:5000)          │
│    │                                 │
│    ├─ No auth vars → Public app      │
│    └─ Auth vars → OAuth protected    │
│                                      │
└──────────────────────────────────────┘
```bash

### Production

```bash
┌─ Azure Subscription ─────────────────────────────────────┐
│                                                            │
│  App Service                                              │
│  ├─ App settings (from deployment script)                │
│  │  ├─ AZURE_CLIENT_ID                                  │
│  │  ├─ AZURE_CLIENT_SECRET                              │
│  │  └─ AZURE_TENANT_ID                                  │
│  │                                                        │
│  └─ Flask app ← reads app settings → OAuth protected    │
│                                                            │
│  App Registration (Entra ID)                             │
│  └─ Redirect URI:                                        │
│     https://your-app.azurewebsites.net/auth/callback    │
│                                                            │
└────────────────────────────────────────────────────────────┘
```bash

---

## Testing Scenarios

### 1. No Authentication (Existing Behavior)

```bash
# .env
AZURE_CLIENT_ID=          # Empty
AZURE_CLIENT_SECRET=      # Empty
AZURE_TENANT_ID=          # Empty

# Result: App works without login
```bash

### 2. Local Testing with Entra ID

```bash
# .env
AZURE_CLIENT_ID=your-id
AZURE_CLIENT_SECRET=your-secret
AZURE_TENANT_ID=your-tenant
REDIRECT_URI=http://localhost:5000/auth/callback

# Must have localhost redirect URI in app registration

# Result: Login required, full OAuth flow
```bash

### 3. Production with Entra ID

```bash
# App settings in Azure App Service
AZURE_CLIENT_ID=your-id
AZURE_CLIENT_SECRET=your-secret
AZURE_TENANT_ID=your-tenant
REDIRECT_URI=https://your-app.azurewebsites.net/auth/callback
FLASK_ENV=production

# Must have production redirect URI in app registration

# Result: Production OAuth with secure cookies
```bash

---

## Comparing with SWA's Entra ID

### Flask Implementation (Transparent)

```bash
✓ See every OAuth step
✓ Full token access
✓ Control token validation
✓ Can add logging/debugging
✓ Works on any Python host
```bash

### SWA Built-in (Opaque)

```bash
✓ No code to maintain
✓ Integrated with static web app
✓ Automatic token management
 Limited visibility for debugging
 Can't customize token validation
```bash

### Using Flask to Debug SWA

If SWA's Entra ID doesn't work but Flask does (with same app registration):

1. The issue is SWA-specific (config, response overrides, etc.)
2. Not an Azure Entra ID issue
3. Check `staticwebapp.config.json`
4. Verify app registration has both web AND spa redirect URIs

---

## Next Steps

1. **Setup Environment** - Follow `ENV-SETUP.md`
2. **Read Documentation** - Start with `ENTRAID.md`
3. **Test Locally** - Try with your credentials
4. **Deploy** - Use `azure-stack-13-flask-entraid.sh`
5. **Debug SWA Issue** - Compare Flask with SWA

---

## Security Checklist

- [ ] Never commit `.env` file (in .gitignore ✓)
- [ ] Use `.env.example` as template
- [ ] Generate new `FLASK_SECRET_KEY` for production
- [ ] Use HTTPS in production (`FLASK_ENV=production`)
- [ ] Rotate client secrets periodically
- [ ] Check app registration redirect URIs match deployment
- [ ] Use different secrets for dev/prod

---

## Troubleshooting

### Entra ID Issues

→ See `ENTRAID.md` (Troubleshooting section)

### Environment Variable Issues

→ See `ENV-SETUP.md` (Troubleshooting section)

### General Issues

1. Check `.env` file exists
2. Verify direnv is allowed: `direnv status`
3. Check variables are loaded: `direnv export bash`
4. Verify app registration settings
5. Check browser console for errors

---

## Additional Resources

- **Microsoft MSAL Python**: <https://github.com/AzureAD/microsoft-authentication-library-for-python>
- **Flask-Session**: <https://flask-session.readthedocs.io/>
- **direnv**: <https://direnv.net/>
- **OAuth 2.0**: <https://datatracker.ietf.org/doc/html/rfc6749>
- **PKCE**: <https://datatracker.ietf.org/doc/html/rfc7636>
