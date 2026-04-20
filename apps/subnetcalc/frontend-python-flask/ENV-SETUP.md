# Environment Setup Guide - Flask Frontend

## Quick Start (direnv)

### 1. Install direnv

```bash
# macOS
brew install direnv

# Linux
# See https://direnv.net/docs/installation.html
```

### 2. Configure Your Shell

Add direnv hook to your shell rc file:

**bash:**

```bash
# Add to ~/.bashrc
eval "$(direnv hook bash)"
```

**zsh:**

```bash
# Add to ~/.zshrc
eval "$(direnv hook zsh)"
```

**fish:**

```fish
# Add to ~/.config/fish/config.fish
direnv hook fish | source
```

Then reload your shell:

```bash
exec $SHELL
```

### 3. Setup Flask Directory

```bash
cd subnetcalc/frontend-python-flask

# Copy example file
cp .env.example .env

# Edit with your values (see below)
nano .env

# Allow direnv to load environment
direnv allow
```

### 4. Verify Setup

```bash
# Check loaded variables
direnv export bash

# Should show your environment variables
```

---

## Environment Variables

### For Entra ID Authentication (Optional)

Get these from your Entra ID app registration:

```bash
# 1. Get your tenant ID
az account show --query tenantId -o tsv

# 2. List your app registrations
az ad app list --filter "displayName eq 'Subnet Calculator Flask'" --query "[].{id:appId,name:displayName}"

# 3. Get the secret from Azure Portal:
#    Entra ID → App registrations → Your app → Certificates & secrets
```

### For Flask Configuration

```bash
# Generate secure key for production
FLASK_SECRET_KEY=$(openssl rand -hex 32)

# Set environment
FLASK_ENV=development  # or production

# Set API endpoint
API_BASE_URL=http://localhost:7071/api/v1
```

---

## Usage Scenarios

### Scenario 1: No Auth (Default)

```bash
# In .env, leave Entra ID vars blank:
AZURE_CLIENT_ID=
AZURE_CLIENT_SECRET=
AZURE_TENANT_ID=

# Run normally
uv run flask run
# App works without login
```

### Scenario 2: Local Entra ID Testing

```bash
# In .env, set all Entra ID vars
AZURE_CLIENT_ID=your-id
AZURE_CLIENT_SECRET=your-secret
AZURE_TENANT_ID=your-tenant
REDIRECT_URI=http://localhost:5000/auth/callback

# Make sure app registration has this redirect URI registered

# Run Flask
uv run flask run

# Visit http://localhost:5000 → redirects to login
```

### Scenario 3: Production Deployment

```bash
# In .env (or in deployment script)
AZURE_CLIENT_ID=your-id
AZURE_CLIENT_SECRET=your-secret
AZURE_TENANT_ID=your-tenant
REDIRECT_URI=https://your-app-service.azurewebsites.net/auth/callback
FLASK_ENV=production
FLASK_SECRET_KEY=$(openssl rand -hex 32)

# Deploy
./azure-stack-13-flask-entraid.sh
```

---

## Direnv Commands

```bash
# Show current environment
direnv export bash

# Show status
direnv status

# Temporarily disable
direnv deny

# Re-enable
direnv allow

# Clear cache
direnv reload

# Show what changed
direnv diff

# View raw .env file
direnv cat .env
```

---

## Alternative: Manual Environment Loading

If you don't use direnv, you can manually load the file:

**bash/zsh:**

```bash
# Before running Flask
source .env
uv run flask run
```

**Or inline:**

```bash
$(cat .env | xargs) uv run flask run
```

**Or with env file:**

```bash
uv run env $(cat .env) flask run
```

---

## Troubleshooting

### "direnv not found"

```bash
# Make sure direnv is installed
which direnv

# If not found
brew install direnv

# Add to shell rc and reload
eval "$(direnv hook bash)" >> ~/.bashrc
exec bash
```

### "File .env not allowed"

```bash
# direnv asks permission first time
# Fix with:
direnv allow
```

### "Environment variables not loading"

```bash
# Check if .env exists
ls -la .env

# Check direnv status
direnv status

# Reload
direnv reload

# Verify variables
echo $AZURE_CLIENT_ID
```

### "FLASK_SECRET_KEY not set"

```bash
# Generate one
openssl rand -hex 32

# Add to .env
FLASK_SECRET_KEY=<output-from-above>

# Reload
direnv allow
```

---

## Security Best Practices

1. **Never commit .env**

   - It's in .gitignore
   - Always use .env.example as template

2. **Rotate secrets regularly**

   - Especially client secrets (they expire)
   - Check expiration: `az ad app credential list --id <CLIENT_ID>`

3. **Use different secrets per environment**

   - Local: Test credentials
   - Production: Real credentials in deployment secrets

4. **Use .env.local for overrides**
   - Machine-specific settings
   - Also ignored by git

---

## Integration with Deployment Scripts

The deployment script (`azure-stack-13-flask-entraid.sh`) reads from environment variables:

```bash
# Script sources from .env if present
AZURE_CLIENT_ID="xxx" \
AZURE_CLIENT_SECRET="xxx" \
./azure-stack-13-flask-entraid.sh
```

Or with direnv:

```bash
cd subnetcalc/frontend-python-flask
direnv allow
# Variables are loaded automatically
cd ~/Developer/personal/azure-tui/infrastructure/azure
./azure-stack-13-flask-entraid.sh
```

---

## References

- **direnv Documentation**: <https://direnv.net/>
- **direnv Installation**: <https://direnv.net/docs/installation.html>
- **Environment Variables**: `.env.example` (this directory)
- **Flask Configuration**: <https://flask.palletsprojects.com/config/>
- **Azure Entra ID**: <https://learn.microsoft.com/en-us/entra/>
