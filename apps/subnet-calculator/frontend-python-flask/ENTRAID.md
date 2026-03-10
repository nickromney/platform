# Entra ID Authentication for Flask Frontend

This Flask frontend supports optional Entra ID (Azure Active Directory) authentication using Microsoft's MSAL library.

## Architecture

The authentication uses OAuth 2.0 Authorization Code Flow with PKCE, which is the recommended secure pattern for web applications.

**Flow:**

1. User visits app
2. If not authenticated, redirected to `/login`
3. Redirected to Entra ID authorization endpoint
4. User logs in with their Entra ID credentials
5. Redirected back to `/auth/callback` with authorization code
6. Code is exchanged for access token and ID token
7. User info stored in secure session
8. User can now access the app

## Prerequisites

1. Azure tenant with Entra ID
2. App registration in Entra ID (see below)
3. Python 3.11+

## Setup

### 1. Create App Registration in Entra ID

```bash
# Via Azure Portal:
1. Go to Azure Entra ID → App registrations → New registration
2. Name: "Subnet Calculator Flask" (or your preference)
3. Supported account types: "Accounts in this organizational directory only"
4. Redirect URI: http://localhost:5000/auth/callback (for local testing)
5. Click "Register"

# Or via Azure CLI:
az ad app create \
  --display-name "Subnet Calculator Flask" \
  --web-redirect-uris "http://localhost:5000/auth/callback"
```bash

### 2. Create Client Secret

```bash
# Via Azure Portal:
1. Go to Certificates & secrets
2. Click "New client secret"
3. Description: "Flask app"
4. Expiry: 24 months
5. Copy the value (you won't see it again!)

# Or via Azure CLI:
az ad app credential create \
  --id <APPLICATION-ID> \
  --display-name "Flask app" \
  --years 2
```bash

### 3. Get Your Credentials

```bash
# Via Azure CLI:
TENANT_ID=$(az account show --query tenantId -o tsv)
CLIENT_ID=$(az ad app list --filter "displayName eq 'Subnet Calculator Flask'" --query "[0].appId" -o tsv)
CLIENT_SECRET="<from step 2>"

echo "AZURE_TENANT_ID=$TENANT_ID"
echo "AZURE_CLIENT_ID=$CLIENT_ID"
echo "AZURE_CLIENT_SECRET=$CLIENT_SECRET"
```bash

## Local Testing

### 1. Install Dependencies

```bash
cd subnet-calculator/frontend-python-flask
uv sync --extra dev
```bash

### 2. Set Environment Variables

**For bash/zsh:**

```bash
export AZURE_CLIENT_ID="your-client-id"
export AZURE_CLIENT_SECRET="your-client-secret"
export AZURE_TENANT_ID="your-tenant-id"
export FLASK_ENV="development"
export FLASK_SECRET_KEY="dev-key-change-in-production"
```bash

**For nushell:**

```nushell
$env.AZURE_CLIENT_ID = "your-client-id"
$env.AZURE_CLIENT_SECRET = "your-client-secret"
$env.AZURE_TENANT_ID = "your-tenant-id"
$env.FLASK_ENV = "development"
$env.FLASK_SECRET_KEY = "dev-key-change-in-production"
```bash

### 3. Run Flask Development Server

```bash
uv run flask run
# Server will be at http://localhost:5000
```bash

### 4. Test the Flow

1. Visit <http://localhost:5000>
2. You should be redirected to Entra ID login
3. Log in with your test account
4. You'll be redirected back to the app
5. User info should display in the top-right corner

### 5. Troubleshooting Local Testing

**Redirect URI Mismatch:**

- Error: "redirect_uri mismatch"
- Solution: Update app registration with correct callback URL (including port)

**CSRF State Validation Failed:**

- Error: "State validation failed"
- Solution: Clear browser cookies, clear Flask session folder, try again

**Token Acquisition Failed:**

- Check that `AZURE_CLIENT_SECRET` is correct
- Verify client secret hasn't expired (check in portal)
- Ensure you have the right permissions in Entra ID

## Testing with ngrok (Remote Testing)

For testing OAuth flow with a remote server:

```bash
# Install ngrok
brew install ngrok

# Start ngrok
ngrok http 5000
# Gives you: https://xxxxx.ngrok.io

# Add redirect URI to app registration:
# https://xxxxx.ngrok.io/auth/callback

# Set environment variable
export REDIRECT_URI="https://xxxxx.ngrok.io/auth/callback"

# Run Flask
uv run flask run

# Visit https://xxxxx.ngrok.io
```bash

## Deployment to Azure App Service

### 1. Create App Service (if not already created)

```bash
# Create App Service Plan
az appservice plan create \
  --name asp-subnet-calc-flask \
  --resource-group <YOUR_RESOURCE_GROUP> \
  --sku B1 \
  --is-linux

# Create App Service
az webapp create \
  --resource-group <YOUR_RESOURCE_GROUP> \
  --plan asp-subnet-calc-flask \
  --name webapp-subnet-calc-flask \
  --runtime "PYTHON:3.11" \
  --startup-file "gunicorn --bind 0.0.0.0:8000 --workers 4 app:app"
```bash

### 2. Update App Registration for Production

```bash
# Add production redirect URI
az ad app update \
  --id <CLIENT_ID> \
  --web-redirect-uris "https://webapp-subnet-calc-flask.azurewebsites.net/auth/callback"

# Also keep localhost for local testing
az ad app update \
  --id <CLIENT_ID> \
  --web-redirect-uris \
    "https://webapp-subnet-calc-flask.azurewebsites.net/auth/callback" \
    "http://localhost:5000/auth/callback"
```bash

### 3. Configure App Settings

```bash
# Set configuration in App Service
az webapp config appsettings set \
  --resource-group <YOUR_RESOURCE_GROUP> \
  --name webapp-subnet-calc-flask \
  --settings \
    AZURE_CLIENT_ID="<CLIENT_ID>" \
    AZURE_CLIENT_SECRET="<CLIENT_SECRET>" \
    AZURE_TENANT_ID="<TENANT_ID>" \
    REDIRECT_URI="https://webapp-subnet-calc-flask.azurewebsites.net/auth/callback" \
    FLASK_ENV="production" \
    FLASK_SECRET_KEY="$(openssl rand -hex 32)" \
    API_BASE_URL="<YOUR_API_ENDPOINT>" \
    STACK_NAME="Python Flask + Entra ID"
```bash

### 4. Deploy the Application

```bash
# Using deployment script (if available)
./50-deploy-flask-app-service.sh

# Or manually:
az webapp deployment source config-zip \
  --resource-group <YOUR_RESOURCE_GROUP> \
  --name webapp-subnet-calc-flask \
  --src-path ./app.zip
```bash

## Environment Variables Reference

| Variable | Required | Example | Notes |
|----------|----------|---------|-------|
| `AZURE_CLIENT_ID` | Yes (for auth) | `370b8618-a252-442e-9941-c47a9f7da89e` | From app registration |
| `AZURE_CLIENT_SECRET` | Yes (for auth) | `sWa~...` | From app registration secrets |
| `AZURE_TENANT_ID` | Yes (for auth) | `e4cd804d-7192-4483-92de-7d574cff9827` | From Azure tenant |
| `REDIRECT_URI` | Optional | `https://app.example.com/auth/callback` | Defaults to <http://localhost:5000/auth/callback> |
| `FLASK_SECRET_KEY` | Recommended | Generate with `openssl rand -hex 32` | For session encryption (production) |
| `FLASK_ENV` | Optional | `production` or `development` | Affects cookie security settings |
| `API_BASE_URL` | Optional | `https://func-api.azurewebsites.net/api/v1` | Backend API endpoint |
| `STACK_NAME` | Optional | `Python Flask + Entra ID` | Display name in UI |

## Comparing with SWA Built-in Auth

This Flask implementation uses the same OAuth 2.0 Authorization Code Flow as SWA's built-in authentication, but with full visibility:

**Advantages of Flask Implementation:**

- See every step of the OAuth flow
- Log tokens and claims for debugging
- Control token validation
- Add custom claims or scopes
- Works on any cloud (not just SWA)
- Test locally easily with Flask development server

**Advantages of SWA Built-in Auth:**

- No code to maintain
- Integrated with static web app
- Automatic token management

**To Debug SWA Issues:**

1. Deploy this Flask version with same app registration
2. Compare the OAuth flows
3. Check token exchange differences
4. Look for issuer/audience mismatches

## Adding Custom Claims

To request additional claims from Entra ID:

```python
# In auth.py, modify the login function:
auth_url = self.msal_app.get_authorization_request_url(
    scopes=self.scopes,
    redirect_uri=self.redirect_uri,
    state=session["state"],
    claims_challenge=None,  # Can add custom claims here
)
```bash

## Troubleshooting

### Issue: "We couldn't sign you in. Please try again"

This is the "reprocess" error from SWA's built-in auth. In Flask, you'd see:

```bash
Token acquisition failed: invalid_grant - ...
```bash

**Possible causes:**

1. Client secret is wrong or expired
2. Redirect URI doesn't match app registration
3. Token validation failed (wrong issuer/audience)
4. User account disabled in Entra ID

**Solutions:**

1. Verify `AZURE_CLIENT_SECRET` matches portal
2. Check secret expiration date
3. Verify `REDIRECT_URI` exactly matches app registration
4. Check Entra ID user account status
5. Enable debug logging:

   ```python
   import logging
   logging.basicConfig(level=logging.DEBUG)
   ```

### Issue: "State Validation Failed"

Typically during local testing with multiple browser windows.

**Solutions:**

1. Clear browser cookies
2. Delete `.flask_session` directory
3. Close other browser windows
4. Use incognito/private mode

### Issue: Sessions Not Persisting

Sessions are stored in `.flask_session` directory by default (not suitable for production).

**For Production:**
Use Redis or other session backend:

```python
app.config["SESSION_TYPE"] = "redis"
app.config["SESSION_REDIS"] = redis.from_url(os.getenv("REDIS_URL"))
```bash

## Security Considerations

1. **HTTPS Only**: Always use HTTPS in production
2. **Secure Cookies**: Enabled automatically in production (`FLASK_ENV=production`)
3. **Session Keys**: Generate random secret key for each deployment
4. **Token Validation**: MSAL automatically validates tokens
5. **PKCE**: Authorization Code Flow always includes PKCE for enhanced security

## References

- Microsoft MSAL Python: <https://github.com/AzureAD/microsoft-authentication-library-for-python>
- Flask-Session: <https://flask-session.readthedocs.io/>
- OAuth 2.0 Authorization Code Flow: <https://datatracker.ietf.org/doc/html/rfc6749#section-1.3.1>
- PKCE (Proof Key for Public Clients): <https://datatracker.ietf.org/doc/html/rfc7636>
