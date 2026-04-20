import { expect, test } from '@playwright/test'

test.describe('Mock Easy Auth logout regression', () => {
  test('logout clears UI auth state when /.auth/me returns 200 with an empty principal', async ({ page }) => {
    let loggedIn = true

    await page.addInitScript(() => {
      window.RUNTIME_CONFIG = {
        AUTH_METHOD: 'easyauth',
      }
    })

    await page.route('**/.auth/me', async (route) => {
      if (loggedIn) {
        await route.fulfill({
          status: 200,
          contentType: 'application/json',
          body: JSON.stringify([
            {
              user_id: 'demo-user',
              claims: [
                { typ: 'name', val: 'Demo User' },
                { typ: 'preferred_username', val: 'demo@dev.test' },
              ],
              authentication_token: 'mock-token',
            },
          ]),
        })
        return
      }

      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([{}]),
      })
    })

    await page.route('**/.auth/logout**', async (route) => {
      loggedIn = false
      await route.fulfill({
        status: 302,
        headers: {
          location: '/logged-out.html',
        },
      })
    })

    await page.route('**/oauth2/start**', async (route) => {
      await route.fulfill({
        status: 302,
        headers: {
          location: '/',
        },
      })
    })

    await page.route('**/api/v1/health', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ status: 'ok', service: 'subnetcalc-api', version: 'test' }),
      })
    })

    await page.goto('/')

    await expect(page.getByRole('heading', { name: /IPv4 Subnet Calculator/i })).toBeVisible({ timeout: 30000 })
    await expect(page.locator('#user-info')).toContainText(/Welcome,\s*Demo User/i)
    const logoutButton = page.getByRole('button', { name: /logout/i })
    await expect(logoutButton).toBeVisible()

    await logoutButton.click()
    await page.waitForURL(/logged-out\.html/i, { timeout: 30000 })
    await expect(page.getByRole('heading', { name: /logged out/i })).toBeVisible({ timeout: 30000 })

    // Return to the app. The mock server now returns an "empty principal" but still HTTP 200.
    await page.getByRole('button', { name: /return to calculator/i }).click()
    await page.waitForURL(/\/$/, { timeout: 30000 })

    await expect(page.locator('#user-info')).toHaveCount(0)
    await expect(page.getByRole('button', { name: /login/i })).toBeVisible()
  })
})
