# Entra ID Authentication & Logout Testing

This document describes how to test the Azure Static Web Apps Entra ID authentication and logout functionality.

## Test Suite: `auth-logout.spec.ts`

Tests the complete logout flow for Azure SWA with Entra ID authentication, including:

- Logged-out page accessibility without authentication
- No data exposure on logged-out page
- Logout route behavior
- Configuration validation
- Logout button functionality
- Authentication state clearing

## Prerequisites

1. **Deploy to Azure SWA with Entra ID enabled**

   ```bash
   cd ~/Developer/personal/azure-tui/infrastructure/azure
   RESOURCE_GROUP='rg-subnet-calc' \
   STATIC_WEB_APP_NAME='swa-subnet-calc-entraid-linked' \
   FRONTEND='typescript' \
   VITE_AUTH_ENABLED=true \
   ./20-deploy-frontend.sh
   ```

2. **Verify deployment**

   ```bash
   ./64-verify-entraid-setup.sh
   ```

## Running the Tests

### Against Deployed Azure SWA

```bash
# Set the BASE_URL to your deployed SWA
BASE_URL=https://proud-bay-05b7e1c03.1.azurestaticapps.net bun run test:auth

# Run with browser visible (headed mode)
BASE_URL=https://proud-bay-05b7e1c03.1.azurestaticapps.net bun run test:auth:headed
```

### Against Local Development

```bash
# Default (uses http://localhost:3000)
bun run test:auth

# With custom BASE_URL
BASE_URL=http://localhost:4280 bun run test:auth
```

## Test Coverage

### Test 01: Logged-out page accessibility

**Verifies:** `/logged-out.html` is accessible without authentication

- Direct navigation to logged-out page returns 200 OK
- Page displays "You've been logged out" message
- "Log in again" button is visible

### Test 02: No data exposure

**Verifies:** Logged-out page does not expose application data

- No calculator form elements visible
- No API status visible
- No user info visible
- Only logout message and login button

### Test 03: Logout route redirect

**Verifies:** `/logout` route redirects correctly

- Navigation to `/logout` redirects to logged-out page
- Final URL contains `/logged-out.html`
- Logout message is displayed

**Note:** This test automatically skips when running against local dev server (localhost:3000/5173) because `staticwebapp.config.json` routing only works in Azure SWA or the SWA CLI emulator (localhost:4280/4281).

### Test 04: Configuration validation

**Verifies:** `staticwebapp.config.json` has correct settings

- `/logged-out.html` route allows anonymous access
- `/logout` route redirects to `/.auth/logout?post_logout_redirect_uri=/logged-out.html`
- Navigation fallback excludes `/logged-out.html`

### Test 05: Logout button functionality

**Verifies:** Logout button works correctly (requires authenticated session)

- Logout button is visible when authenticated
- Clicking logout redirects to `/logout` route
- User lands on logged-out page

### Test 06: Styling and layout

**Verifies:** Logged-out page has correct presentation

- Uses Pico CSS
- Has container and logout-container classes
- Displays logout icon (👋)

### Test 07: Login button

**Verifies:** Login button on logged-out page

- Button links to `/.auth/login/aad`
- Button is visible and clickable

### Test 08: Authentication state clearing

**Verifies:** Logout clears authentication (requires authenticated session)

- `/.auth/me` returns authenticated user before logout
- After logout, `/.auth/me` returns null clientPrincipal
- Session is properly cleared

## Test Results Interpretation

### Tests that Always Run

Tests 01-04, 06-07 test static functionality and configuration that doesn't require authentication.

### Tests that Require Authentication

Tests 05 and 08 require an authenticated session. If running against a deployment where you're not logged in, these tests will automatically skip.

### Tests that Require Azure SWA or SWA Emulator

Test 03 requires Azure SWA or the SWA CLI emulator to be running. It automatically skips when running against local dev server (localhost:3000/5173) because the local Vite dev server doesn't process `staticwebapp.config.json` routing rules.

To test these:

1. Deploy to Azure SWA with Entra ID
2. Manually log in via browser first
3. Then run the tests (Playwright will use the authenticated session)

## Troubleshooting

### "Test skipped" for tests 05 and 08

**Cause:** No authenticated session available
**Solution:** Log in to the SWA in your browser before running tests

### "Timeout waiting for /logged-out.html"

**Cause:** Logout redirect not working properly
**Solution:**

1. Verify `staticwebapp.config.json` has correct logout route
2. Check Azure SWA deployment completed successfully
3. Wait 1-2 minutes for deployment to propagate

### "404 Not Found" for /logged-out.html

**Cause:** `logged-out.html` file not deployed
**Solution:**

1. Verify `public/logged-out.html` exists
2. Rebuild: `bun run build`
3. Check `dist/logged-out.html` exists
4. Redeploy to Azure

### Configuration validation fails

**Cause:** `staticwebapp.config.json` not updated correctly
**Solution:**

1. Verify using `staticwebapp-entraid-builtin.config.json`
2. Check deployment script copies correct config
3. Inspect deployed config: `curl https://your-app.azurestaticapps.net/staticwebapp.config.json`

## CI/CD Integration

Add to your CI/CD pipeline:

```yaml
# Example GitHub Actions
- name: Run auth logout tests
  run: |
    BASE_URL=${{ secrets.SWA_URL }} bun run test:auth
  working-directory: subnet-calculator/frontend-typescript-vite
```

**Note:** For full test coverage in CI, you'll need to set up automated authentication or use a test account. Tests that require authentication (05, 08) will skip in unauthenticated CI environments.

## Further Reading

- [Azure Static Web Apps Authentication](https://learn.microsoft.com/en-us/azure/static-web-apps/authentication-authorization)
- [Playwright Testing](https://playwright.dev/docs/intro)
- [Entra ID Configuration](~/Developer/personal/azure-tui/infrastructure/azure/ENTRA-ID-SETUP.md)
