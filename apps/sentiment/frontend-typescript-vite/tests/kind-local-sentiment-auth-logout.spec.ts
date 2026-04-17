import { expect, type Page, test } from '@playwright/test'

const BASE_URL = process.env.BASE_URL || 'https://sentiment.dev.127.0.0.1.sslip.io'
const USERNAME = process.env.OIDC_USERNAME || process.env.KEYCLOAK_USERNAME || 'demo@dev.test'
const PASSWORD = process.env.OIDC_PASSWORD || process.env.KEYCLOAK_PASSWORD || process.env.PLATFORM_DEMO_PASSWORD || ''
const APP_TITLE = 'Sentiment Analysis (Authenticated UI)'

if (!PASSWORD) {
  throw new Error('Set PLATFORM_DEMO_PASSWORD (or OIDC_PASSWORD / KEYCLOAK_PASSWORD) before running this test')
}

function hasOauth2ProxyCookie(cookies: Array<{ name: string }>) {
  // oauth2-proxy cookie name varies by environment:
  // compose defaults to `_oauth2_proxy`, while kind uses env-scoped names like `kind-sso-dev`.
  return cookies.some((c) => {
    const name = c.name.toLowerCase()
    if (name.includes('csrf')) return false
    return name.includes('_oauth2_proxy') || name.includes('kind-sso-')
  })
}

async function submitIdentityProviderLogin(page: Page) {
  const keycloakUsername = page.locator('#username')
  if (await keycloakUsername.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await keycloakUsername.fill(USERNAME)
    await page.locator('#password').fill(PASSWORD)
    await page.click('#kc-login')
    return
  }

  const dexEmail = page.getByPlaceholder(/email address/i)
  if (await dexEmail.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await dexEmail.fill(USERNAME)
    await page.getByPlaceholder(/^password$/i).fill(PASSWORD)
    await page.getByRole('button', { name: /^login$/i }).click()
    return
  }

  throw new Error(`Unsupported identity-provider login page at ${page.url()}`)
}

async function grantAccessIfPrompted(page: Page) {
  const grantAccessButton = page.getByRole('button', { name: /^grant access$/i })
  if (await grantAccessButton.isVisible({ timeout: 5_000 }).catch(() => false)) {
    await grantAccessButton.click()
  }
}

async function waitForInteractiveLogin(page: Page, timeout: number) {
  const providerButton = page.getByRole('button', { name: /sign in with openid connect/i })
  const keycloakUsername = page.locator('#username')
  const dexEmail = page.getByPlaceholder(/email address/i)

  await expect
    .poll(
      async () =>
        page.url().includes('/oauth2/sign_in') ||
        page.url().includes('/dex/auth/local/login') ||
        page.url().includes('/protocol/openid-connect/logout') ||
        (await providerButton.isVisible().catch(() => false)) ||
        (await keycloakUsername.isVisible().catch(() => false)) ||
        (await dexEmail.isVisible().catch(() => false)),
      { timeout }
    )
    .toBe(true)
}

async function ensureLoggedIn(page: Page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' })

  // If already on the app, nothing to do.
  const appTitle = page.getByText(APP_TITLE)
  if (await appTitle.isVisible().catch(() => false)) return

  // oauth2-proxy sign-in page (provider selection)
  const providerButton = page.getByRole('button', { name: /sign in with openid connect/i })
  if (await providerButton.isVisible().catch(() => false)) {
    await providerButton.click()
  }

  await submitIdentityProviderLogin(page)
  await grantAccessIfPrompted(page)

  await expect(page.getByText(APP_TITLE)).toBeVisible({ timeout: 20_000 })
}

async function completeProviderLogoutIfPrompted(page: Page) {
  if (!page.url().includes('/protocol/openid-connect/logout')) return

  // Some providers present an explicit logout confirmation page.
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

test.describe('kind-local: sentiment authenticated UI logout', () => {
  test.describe.configure({ mode: 'serial' })

  test('logout clears oauth2-proxy session and forces re-login on next visit', async ({ page, context }, testInfo) => {
    // 1) Login
    await ensureLoggedIn(page)

    const cookiesBefore = await context.cookies(BASE_URL)
    await testInfo.attach('cookiesBefore', {
      body: JSON.stringify(
        cookiesBefore.map((c) => ({ name: c.name, domain: c.domain, path: c.path })),
        null,
        2
      ),
      contentType: 'application/json',
    })
    expect(hasOauth2ProxyCookie(cookiesBefore)).toBeTruthy()

    // 2) Logout
    await page.getByRole('button', { name: 'Logout' }).click()

    // oauth2-proxy may return to its sign-in page, go straight to Dex, or hit a provider logout confirmation page.
    await waitForInteractiveLogin(page, 20_000)
    await completeProviderLogoutIfPrompted(page)

    await waitForInteractiveLogin(page, 20_000)

    const cookiesAfter = await context.cookies(BASE_URL)
    await testInfo.attach('cookiesAfterLogout', {
      body: JSON.stringify(
        cookiesAfter.map((c) => ({ name: c.name, domain: c.domain, path: c.path })),
        null,
        2
      ),
      contentType: 'application/json',
    })
    expect(hasOauth2ProxyCookie(cookiesAfter)).toBeFalsy()

    // 3) Visiting the app again should require interactive login (no silent SSO)
    await page.goto('/', { waitUntil: 'domcontentloaded' })

    const cookiesAfterRevisit = await context.cookies(BASE_URL)
    await testInfo.attach('cookiesAfterRevisit', {
      body: JSON.stringify(
        {
          url: page.url(),
          cookies: cookiesAfterRevisit.map((c) => ({ name: c.name, domain: c.domain, path: c.path })),
        },
        null,
        2
      ),
      contentType: 'application/json',
    })

    // We should not land on the app without interacting.
    const appTitleAfterRevisit = page.getByText(APP_TITLE)
    if (await appTitleAfterRevisit.isVisible().catch(() => false)) {
      const snapshot = {
        url: page.url(),
        cookies: (await context.cookies(BASE_URL)).map((c) => ({
          name: c.name,
          domain: c.domain,
          path: c.path,
        })),
      }
      throw new Error(`Unexpected app visible after logout. ${JSON.stringify(snapshot, null, 2)}`)
    }

    // Visiting the app again should still require interactive auth, either via oauth2-proxy sign-in
    // or directly on the Dex password form when the provider button is skipped.
    await waitForInteractiveLogin(page, 20_000)
  })
})
