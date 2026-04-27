import { expect, test, type Page } from '@playwright/test'

test.skip(process.env.COMPOSE_BACKSTAGE_E2E !== '1', 'Compose Backstage smoke runs only from docker/compose test-backstage')

const PORTAL_URL = process.env.COMPOSE_BACKSTAGE_URL || 'https://portal.compose.127.0.0.1.sslip.io:8443/'
const DEX_HOST = new URL(process.env.COMPOSE_DEX_URL || 'https://dex.compose.127.0.0.1.sslip.io:8443/dex/').host
const LOGIN = process.env.COMPOSE_DEX_LOGIN || 'demo@dev.test'
const PASSWORD = process.env.COMPOSE_DEX_PASSWORD || process.env.PLATFORM_DEMO_PASSWORD || 'password123'

async function maybeGrantDexAccess(page: Page) {
  const grant = page.getByRole('button', { name: /^grant access$/i })
  if (await grant.isVisible().catch(() => false)) {
    await grant.click()
  }
}

async function completeDexLogin(page: Page) {
  await page.waitForSelector('#login', { timeout: 60_000 })
  await page.fill('#login', LOGIN)
  await page.fill('#password', PASSWORD)
  await page.click('#submit-login')
  await maybeGrantDexAccess(page)
}

async function isOauth2ProxyForbiddenPage(page: Page) {
  const body = page.locator('body')
  return body.getByText(/Forbidden|Invalid authentication via OAuth2|unauthorized/i).isVisible().catch(() => false)
}

async function isGatewayErrorPage(page: Page) {
  const body = page.locator('body')
  return body.getByText(/502 Bad Gateway|503 Service Unavailable|504 Gateway Time-out/i).isVisible().catch(() => false)
}

test.describe('compose Backstage portal', () => {
  test('completes Dex login and renders the Backstage catalog', async ({ page }) => {
    test.setTimeout(120_000)

    const portalHost = new URL(PORTAL_URL).host
    await page.goto(PORTAL_URL, { waitUntil: 'domcontentloaded' })

    await page.waitForURL((url) => url.host === portalHost || url.host === DEX_HOST, { timeout: 60_000 })
    if (new URL(page.url()).host === DEX_HOST) {
      await completeDexLogin(page)
    }

    await page.waitForURL((url) => url.host === portalHost && !url.pathname.startsWith('/oauth2/'), { timeout: 60_000 })
    await page.waitForLoadState('domcontentloaded', { timeout: 30_000 }).catch(() => undefined)

    expect(await isGatewayErrorPage(page), `Backstage compose page is a gateway error: ${page.url()}`).toBe(false)
    expect(await isOauth2ProxyForbiddenPage(page), `Backstage compose login was rejected: ${page.url()}`).toBe(false)
    await expect(page.locator('#login')).toHaveCount(0)

    await expect(page.getByRole('heading', { name: 'Catalog' })).toBeVisible({ timeout: 30_000 })
    await expect(page.getByText('Developer Portal', { exact: true })).toBeVisible({ timeout: 60_000 })
    await expect(page.getByText('Hello Platform', { exact: true })).toBeVisible()
  })
})
