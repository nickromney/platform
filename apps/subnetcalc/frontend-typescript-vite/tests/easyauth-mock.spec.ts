import { expect, test } from '@playwright/test'

test.describe('Mock Easy Auth logout regression', () => {
  test('gateway auth clears UI state when /.auth/me returns 200 with an empty principal', async ({ page }) => {
    await page.goto('/')

    await expect(page.getByRole('heading', { name: /IPv4 Subnet Calculator/i })).toBeVisible({ timeout: 30000 })
    await expect(page.locator('#stack-description')).toContainText(/OAuth2 Proxy|gateway/i)
    await expect(page.locator('#login-btn')).toContainText(/Login with SSO/i)

    await page.getByRole('button', { name: /login with sso/i }).click()
    await page.waitForURL(/\/$/, { timeout: 30000 })

    await expect(page.locator('#user-info')).toContainText(/Demo User/i, { timeout: 30000 })
    const logoutButton = page.getByRole('button', { name: /logout/i })
    await expect(logoutButton).toBeVisible()

    await logoutButton.click()
    await page.waitForURL(/logged-out\.html/i, { timeout: 30000 })
    await expect(page.getByRole('heading', { name: /logged out/i })).toBeVisible({ timeout: 30000 })

    await page.goto('/')
    await expect(page.locator('#login-btn')).toContainText(/Login with SSO/i, { timeout: 30000 })
    await expect(page.locator('#user-info')).not.toContainText(/Demo User/i)
  })
})
