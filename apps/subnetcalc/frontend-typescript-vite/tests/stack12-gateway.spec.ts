import { expect, type Page, test } from '@playwright/test'

const KEYCLOAK_URL_PATTERN = /realms\/subnetcalc\/protocol\/openid-connect\/auth/i
const EXTENDED_TIMEOUT_MS = 30000
const BASE_URL = process.env.BASE_URL || 'http://localhost:3007'
const API_GATEWAY_ORIGIN = process.env.API_GATEWAY_ORIGIN || 'http://localhost:8302'

function escapeRegex(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

const RETURN_HOST_PATTERN = new RegExp(escapeRegex(new URL(BASE_URL).host), 'i')

const demoUser = {
  username: process.env.STACK12_USERNAME || 'demo@dev.test',
  password: process.env.STACK12_PASSWORD || 'demo-password',
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
  test('gateway-protected TypeScript frontend authenticates with Keycloak and keeps APIM calls browser-visible', async ({
    page,
  }, testInfo) => {
    testInfo.setTimeout(testInfo.timeout + EXTENDED_TIMEOUT_MS)

    const apimRequests: Array<{ url: string; headers: Record<string, string> }> = []
    page.on('request', (request) => {
      if (request.url().startsWith(API_GATEWAY_ORIGIN)) {
        apimRequests.push({
          url: request.url(),
          headers: request.headers(),
        })
      }
    })

    await page.goto('/')

    const signInButton = page.getByRole('button', { name: /sign in/i }).first()
    await expect(signInButton).toBeVisible({ timeout: 15000 })
    await signInButton.click()

    await page.waitForURL(KEYCLOAK_URL_PATTERN, { timeout: 15000 })
    await page.locator('input[name="username"]').fill(demoUser.username)
    await page.locator('input[name="password"]').fill(demoUser.password)
    await page.getByRole('button', { name: /sign in|log in/i }).click()

    await page.waitForURL(RETURN_HOST_PATTERN, { timeout: 30000 })
    await expect(page.getByRole('heading', { level: 1, name: /IPv4 Subnet Calculator/i })).toBeVisible({
      timeout: 30000,
    })
    await expect(page.locator('#stack-description')).toContainText('OAuth2 Proxy')
    await expect(page.locator('#api-status')).toContainText('healthy', { timeout: 20000 })

    const logoutButton = page.getByRole('button', { name: /logout/i })
    await expect(logoutButton).toBeVisible({ timeout: 30000 })
    await expect(page.locator('#user-info')).toContainText(/demo user|demo@dev\.test/i)

    await page.locator('#theme-switcher').click()

    const ipInput = page.locator('#ip-address')
    await expect(ipInput).toBeVisible()

    const exampleButtons = page.locator('#example-buttons button')
    await expect(exampleButtons).toHaveCount(4)

    await page.getByRole('button', { name: /RFC1918: 10\.0\.0\.0\/24/i }).click()
    await expect(ipInput).toHaveValue('10.0.0.0/24')
    await page.getByRole('button', { name: /RFC6598: 100\.64\.0\.1/i }).click()
    await expect(ipInput).toHaveValue('100.64.0.1')
    await page.getByRole('button', { name: /Public: 8\.8\.8\.8/i }).click()
    await expect(ipInput).toHaveValue('8.8.8.8')
    await page.getByRole('button', { name: /Cloudflare: 104\.16\.1\.1/i }).click()
    await expect(ipInput).toHaveValue('104.16.1.1')

    await page.locator('#cloud-mode').selectOption('Azure')
    await page.getByRole('button', { name: /Public: 8\.8\.8\.8/i }).click()
    await page.getByRole('button', { name: /lookup/i }).click()

    await expect(page.getByText(/8\.8\.8\.8/)).toBeVisible({ timeout: 30000 })
    await expect(page.getByRole('heading', { name: /Private Address Check/i })).toBeVisible({ timeout: 30000 })

    expect(apimRequests.some((request) => request.url.includes('/api/v1/ipv4/validate'))).toBeTruthy()
    expect(
      apimRequests.some((request) => request.headers['ocp-apim-subscription-key'] === 'dev-subscription-key')
    ).toBeTruthy()

    await logoutButton.click()
    await page.waitForURL(/(logged-out\.html|protocol\/openid-connect\/logout)/, { timeout: 30000 })
    await completeKeycloakLogoutIfPrompted(page)
    await page.waitForURL(/logged-out\.html/, { timeout: 30000 })
    await expect(page.getByRole('heading', { name: /logged out/i })).toBeVisible({ timeout: 30000 })
  })
})
