import { expect, test } from '@playwright/test'

const BASE_URL = process.env.BASE_URL || 'http://localhost:3012'

test.describe('Mock Easy Auth logout regression', () => {
  test('logout clears UI auth state when /.auth/me returns 200 with an empty principal', async ({ context, page }) => {
    const url = new URL(BASE_URL)

    // Start as "logged in" by setting the mock cookie.
    await context.addCookies([
      {
        name: 'easyauth',
        value: '1',
        domain: url.hostname,
        path: '/',
      },
    ])

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
