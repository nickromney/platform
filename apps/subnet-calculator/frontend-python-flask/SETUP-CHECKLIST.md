# Setup Checklist - Flask Frontend with Entra ID

## Complete Implementation Checklist

### Authentication Implementation ✓

- [x] Created `auth.py` with MSAL OAuth 2.0 implementation
- [x] Updated `app.py` with authentication integration
- [x] Updated `templates/index.html` with user display and logout
- [x] Updated `pyproject.toml` with required dependencies

### Environment Management ✓

- [x] Created `.envrc` for direnv support
- [x] Created `.env.example` with all variables documented
- [x] Updated `.gitignore` to exclude .env, .envrc, .flask_session/
- [x] Created `ENV-SETUP.md` with setup instructions

### Documentation ✓

- [x] Created `ENTRAID.md` - comprehensive guide (400+ lines)
- [x] Created `README-ENTRAID.md` - quick reference
- [x] Created `IMPLEMENTATION-SUMMARY.md` - architecture and overview

### Deployment ✓

- [x] Created `azure-stack-13-flask-entraid.sh` deployment script
- [x] Made script executable

---

## Getting Started (Choose Your Path)

### Path 1: Quick Start (5 minutes)

```bash
# 1. Read quick overview
cat README-ENTRAID.md

# 2. Setup environment
cd subnet-calculator/frontend-python-flask
cp .env.example .env

# 3. Edit with your credentials
nano .env
# Get credentials from: ENV-SETUP.md

# 4. If using direnv:
direnv allow

# 5. Run
uv run flask run
```

### Path 2: Full Setup with direnv (10 minutes)

```bash
# 1. Install direnv
brew install direnv

# 2. Setup shell hook
eval "$(direnv hook bash)" >> ~/.bashrc
exec bash

# 3. Configure Flask app
cd subnet-calculator/frontend-python-flask
cp .env.example .env
nano .env

# 4. Allow direnv
direnv allow

# 5. Verify variables loaded
direnv export bash

# 6. Run Flask
uv run flask run
```

### Path 3: Production Deployment (15 minutes)

```bash
# 1. Create app registration in Entra ID
# (See ENTRAID.md for details)

# 2. Set environment variables
export AZURE_CLIENT_ID="..."
export AZURE_CLIENT_SECRET="..."
export AZURE_TENANT_ID="..."

# 3. Deploy
./azure-stack-13-flask-entraid.sh

# 4. Update app registration redirect URI
# https://your-app-service.azurewebsites.net/auth/callback

# 5. Test
open https://your-app-service.azurewebsites.net
```

---

## Documentation Files (Read in Order)

1. **`ENV-SETUP.md`** ← Start here if setting up environment
   - How to install direnv
   - How to configure .env
   - Troubleshooting environment issues

2. **`README-ENTRAID.md`** ← Quick reference
   - What was added
   - Quick start
   - Key features

3. **`ENTRAID.md`** ← Complete guide
   - Local testing setup
   - Production deployment
   - Troubleshooting Entra ID issues
   - Security considerations

4. **`IMPLEMENTATION-SUMMARY.md`** ← Architecture and reference
   - How it all works
   - File structure
   - Environment variable reference

---

## Implementation Files (Reference)

### Core Authentication

- **`auth.py`** - MSAL OAuth 2.0 implementation
  - Login flow
  - Token exchange
  - Session management
  - 139 lines, well-commented

### Flask Integration

- **`app.py`** - Updated with authentication
  - Session configuration
  - Auth initialization
  - User info passing to templates
  - Changes: ~25 lines added

- **`templates/index.html`** - User display UI
  - User name/email in header
  - Logout button
  - Changes: ~20 lines added

### Dependencies

- **`pyproject.toml`** - Added MSAL packages
  - msal (Microsoft Authentication Library)
  - flask-session (server-side sessions)
  - cryptography (session encryption)

---

## Environment Configuration

### Required Variables (for Entra ID auth)

```bash
AZURE_CLIENT_ID=<your-client-id>
AZURE_CLIENT_SECRET=<your-client-secret>
AZURE_TENANT_ID=<your-tenant-id>
```

### Recommended Variables

```bash
REDIRECT_URI=http://localhost:5000/auth/callback        # (local)
FLASK_SECRET_KEY=$(openssl rand -hex 32)                 # (generate new)
FLASK_ENV=development                                    # or production
API_BASE_URL=http://localhost:7071/api/v1               # backend
```

### File Locations

- Create `.env` from `.env.example` (git-ignored)
- Optional: `.env.local` for machine-specific overrides (git-ignored)
- `.envrc` tells direnv to load `.env` automatically

---

## Testing Scenarios

### Scenario 1: No Auth (Existing Behavior)

```bash
# Don't set AZURE_* variables
uv run flask run
# App works without login ✓
```

### Scenario 2: Local with Entra ID

```bash
# Set all AZURE_* variables in .env
direnv allow
uv run flask run
# Redirects to login ✓
```

### Scenario 3: Production

```bash
# Deploy with script
./azure-stack-13-flask-entraid.sh
# Full Entra ID authentication ✓
```

---

## Troubleshooting Quick Links

| Issue | Solution |
|-------|----------|
| "direnv not found" | `brew install direnv` |
| "File .env not allowed" | `direnv allow` |
| "Environment variables not loading" | `direnv status` then `direnv reload` |
| "Redirect URI Mismatch" | Check app registration and `REDIRECT_URI` env var |
| "Token acquisition failed" | Verify `AZURE_CLIENT_SECRET` is correct and not expired |
| "State Validation Failed" | Clear `.flask_session/` folder, restart Flask |

See `ENV-SETUP.md` and `ENTRAID.md` for detailed troubleshooting.

---

## What This Solves

✓ **Your SWA Entra ID circular redirect issue**

- Flask implementation uses same OAuth 2.0 flow
- Full visibility for debugging
- Can compare behavior with SWA

✓ **Environment variable management**

- direnv matches your existing pattern
- No secrets in code
- Easy per-machine configuration

✓ **Production deployment**

- Deployment script automates setup
- App Service integration
- Secure in production

---

## Next Steps After Setup

1. **Test locally** with your Entra ID credentials
2. **Compare with SWA** - does Flask work but SWA doesn't?
3. **Debug SWA issue** - if Flask works, issue is SWA configuration
4. **Deploy to Azure** - use deployment script for production

---

## Security Checklist

- [ ] Generated new `FLASK_SECRET_KEY` (not using dev default)
- [ ] Never committed `.env` file (in .gitignore ✓)
- [ ] Verified redirect URI matches in app registration
- [ ] Set `FLASK_ENV=production` for production
- [ ] Used HTTPS for production deployment
- [ ] Rotated client secrets if needed

---

## Project Structure

```bash
subnet-calculator/frontend-python-flask/
├── auth.py                          # NEW: MSAL OAuth implementation
├── app.py                           # UPDATED: Auth integration
├── templates/index.html             # UPDATED: User display
├── pyproject.toml                   # UPDATED: Dependencies
├── .envrc                           # NEW: direnv configuration
├── .env.example                     # NEW: Environment template
├── .gitignore                       # UPDATED: Added .env, .envrc
├── ENV-SETUP.md                     # NEW: Setup guide
├── ENTRAID.md                       # NEW: Entra ID guide
├── README-ENTRAID.md                # NEW: Quick reference
├── IMPLEMENTATION-SUMMARY.md        # NEW: Architecture
├── SETUP-CHECKLIST.md              # THIS FILE
├── README.md                        # (existing)
└── azure-stack-13-flask-entraid.sh # NEW: Deployment script
```bash

---

## Files Status

| File | Status | Type |
|------|--------|------|
| `auth.py` |  Created | Implementation |
| `app.py` |  Updated | Implementation |
| `templates/index.html` |  Updated | Implementation |
| `pyproject.toml` |  Updated | Configuration |
| `.envrc` |  Created | Configuration |
| `.env.example` |  Created | Configuration |
| `.gitignore` |  Updated | Configuration |
| `ENV-SETUP.md` |  Created | Documentation |
| `ENTRAID.md` |  Created | Documentation |
| `README-ENTRAID.md` |  Created | Documentation |
| `IMPLEMENTATION-SUMMARY.md` |  Created | Documentation |
| `SETUP-CHECKLIST.md` |  Created | Documentation |
| `azure-stack-13-flask-entraid.sh` |  Created | Deployment |

---

## Questions?

1. **How do I set up environment variables?**
   → Read `ENV-SETUP.md`

2. **How do I test locally?**
   → Read `README-ENTRAID.md` → Local Testing section

3. **How do I deploy to Azure?**
   → Read `ENTRAID.md` → Deployment to Azure App Service

4. **What if something breaks?**
   → Read `ENV-SETUP.md` or `ENTRAID.md` → Troubleshooting

5. **How does this help with SWA's circular redirect?**
   → Read `IMPLEMENTATION-SUMMARY.md` → Comparing with SWA's Entra ID

---

## Summary

 **Everything is set up**

- Authentication implementation complete
- Environment management configured
- Documentation comprehensive
- Deployment script ready

 **Next action: Read `ENV-SETUP.md` to get started**

 **Questions? Check the appropriate guide file above**

---

*Last updated: 2025-10-19*
*Implementation complete and ready for testing*
