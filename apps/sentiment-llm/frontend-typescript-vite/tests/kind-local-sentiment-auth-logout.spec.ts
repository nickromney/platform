import { type Page, expect, test } from '@playwright/test'

const BASE_URL = process.env.BASE_URL || 'https://sentiment.dev.127.0.0.1.sslip.io'
const USERNAME = process.env.KEYCLOAK_USERNAME || 'demo'
const PASSWORD = process.env.KEYCLOAK_PASSWORD || 'password123'

function hasOauth2ProxyCookie(cookies: Array<{ name: string }>) {
  // oauth2-proxy cookie name varies by environment (compose defaults to `_oauth2_proxy`,
  // kind uses explicit env-scoped names). Treat anything containing `_oauth2_proxy` as a
  // session cookie, excluding CSRF helper cookies.
  return cookies.some((c) => c.name.includes('_oauth2_proxy') && !c.name.toLowerCase().includes('csrf'))
}

async function ensureLoggedIn(page: Page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' })

  // If already on the app, nothing to do.
  const appTitle = page.getByText('Sentiment Analysis (Authenticated UI)')
  if (await appTitle.isVisible().catch(() => false)) return

  // oauth2-proxy sign-in page (provider selection)
  const providerButton = page.getByRole('button', { name: /sign in with openid connect/i })
  if (await providerButton.isVisible().catch(() => false)) {
    await providerButton.click()
  }

  // Keycloak login form.
  await page.waitForSelector('#username', { timeout: 20000 })
  await page.fill('#username', USERNAME)
  await page.fill('#password', PASSWORD)
  await page.click('#kc-login')

  await expect(page.getByText('Sentiment Analysis (Authenticated UI)')).toBeVisible({ timeout: 20000 })
}

async function completeKeycloakLogoutIfPrompted(page: Page) {
  if (!page.url().includes('/protocol/openid-connect/logout')) return

  // Keycloak logout confirmation page (theme may vary slightly).
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

    // oauth2-proxy may redirect through Keycloak logout confirmation.
    await page.waitForURL(/(oauth2\/sign_in|protocol\/openid-connect\/logout)/, { timeout: 20000 })
    await completeKeycloakLogoutIfPrompted(page)

    await page.waitForURL(/oauth2\/sign_in/, { timeout: 20000 })

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
    const appTitleAfterRevisit = page.getByText('Sentiment Analysis (Authenticated UI)')
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

    // Expect to be back at oauth2-proxy sign-in page.
    const providerButton = page.getByRole('button', { name: /sign in with openid connect/i })
    await expect(providerButton).toBeVisible({ timeout: 20000 })

    // Clicking provider should show Keycloak login (prompt=login enforced).
    await providerButton.click()
    await page.waitForSelector('#username', { timeout: 20000 })
  })
})
