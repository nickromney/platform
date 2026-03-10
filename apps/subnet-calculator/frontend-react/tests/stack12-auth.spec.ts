import { type Page, expect, test } from '@playwright/test'

const KEYCLOAK_URL_PATTERN = /realms\/subnet-calculator\/protocol\/openid-connect\/auth/i
const EXTENDED_TIMEOUT_MS = 30000

const BASE_URL = process.env.BASE_URL || 'http://localhost:3007'

function escapeRegex(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

const RETURN_HOST_PATTERN = new RegExp(escapeRegex(new URL(BASE_URL).host), 'i')

const demoUser = {
  username: process.env.STACK12_USERNAME || 'demo',
  password: process.env.STACK12_PASSWORD || 'password123',
}

async function completeKeycloakLogoutIfPrompted(page: Page) {
  if (!page.url().includes('/protocol/openid-connect/logout')) return

  const logoutButton = page.locator('#kc-logout')
  if (await logoutButton.count()) {
    await logoutButton.click()
    return
  }

  const buttonByRole = page.getByRole('button', { name: /log out/i })
  if (await buttonByRole.count()) {
    await buttonByRole.click()
  }
}

test.describe('Stack 12 - OAuth2 Proxy + APIM simulator', () => {
  test('user must authenticate before accessing frontend; UI buttons work; API calls succeed', async ({ page }, testInfo) => {
    testInfo.setTimeout(testInfo.timeout + EXTENDED_TIMEOUT_MS)
    page.on('console', (message) => {
      // eslint-disable-next-line no-console
      console.log('[browser]', message.text())
    })
    await page.goto('/')

    // OAuth2 Proxy shows a sign-in interstitial before redirecting to Keycloak
    const signInButton = page.getByRole('button', { name: /sign in/i }).first()
    await expect(signInButton).toBeVisible({ timeout: 15000 })
    await signInButton.click()

    await page.waitForURL(KEYCLOAK_URL_PATTERN, { timeout: 15000 })

    await page.locator('input[name="username"]').fill(demoUser.username)
    await page.locator('input[name="password"]').fill(demoUser.password)
    await page.getByRole('button', { name: /sign in|log in/i }).click()

    // Redirect back to the protected frontend via OAuth2 Proxy
    await page.waitForURL(RETURN_HOST_PATTERN, { timeout: 30000 })
    const heading = page.getByRole('heading', { level: 1, name: /IPv4 Subnet Calculator/i })
    await expect(heading).toBeVisible({ timeout: 30000 })

    // API health widget should surface backend state (APIM simulator -> FastAPI)
    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible({ timeout: 20000 })

    // Auto-login should complete and show logout button
    const logoutButton = page.getByRole('button', { name: /logout/i })
    await expect(logoutButton).toBeVisible({ timeout: 30000 })

    // "Press all the buttons": theme, example buttons, cloud-mode selector
    const themeSwitcher = page.locator('#theme-switcher')
    await expect(themeSwitcher).toBeVisible()
    await themeSwitcher.click()

    const ipInput = page.getByLabel(/IP Address or CIDR Range/i)
    await expect(ipInput).toBeVisible()

    const exampleButtons = page.locator('#example-buttons button')
    await expect(exampleButtons).toHaveCount(4)

    // Click each example button and verify input updates.
    await page.getByRole('button', { name: /RFC1918: 10\.0\.0\.0\/24/i }).click()
    await expect(ipInput).toHaveValue('10.0.0.0/24')
    await page.getByRole('button', { name: /RFC6598: 100\.64\.0\.1/i }).click()
    await expect(ipInput).toHaveValue('100.64.0.1')
    await page.getByRole('button', { name: /Public: 8\.8\.8\.8/i }).click()
    await expect(ipInput).toHaveValue('8.8.8.8')
    await page.getByRole('button', { name: /Cloudflare: 104\.16\.1\.1/i }).click()
    await expect(ipInput).toHaveValue('104.16.1.1')

    // Change cloud-mode selector (exercise dropdown).
    const cloudMode = page.locator('#cloud-mode')
    await expect(cloudMode).toBeVisible()
    await cloudMode.selectOption('Azure')

    // Perform a full lookup that requires hitting the APIM simulator on :8302
    await page.getByRole('button', { name: /Public: 8\.8\.8\.8/i }).click()

    await page.getByRole('button', { name: /lookup|calculate/i }).click()

    await expect(page.getByText(/8\.8\.8\.8/)).toBeVisible({ timeout: 30000 })
    await expect(page.getByText(/RFC1918 Private Address Check/i)).toBeVisible({ timeout: 30000 })

    // Logout button should work end-to-end.
    await logoutButton.click()
    await page.waitForURL(/(logged-out\.html|protocol\/openid-connect\/logout)/, { timeout: 30000 })
    await completeKeycloakLogoutIfPrompted(page)
    await page.waitForURL(/logged-out\.html/, { timeout: 30000 })
    await expect(page.getByRole('heading', { name: /logged out/i })).toBeVisible({ timeout: 30000 })
  })
})
