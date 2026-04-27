import { expect, test, type Page, type TestInfo } from '@playwright/test'

type Segment = 'dev' | 'uat' | 'admin'

type Flow = 'oauth2-proxy' | 'headlamp-oidc' | 'keycloak-admin' | 'none'

type Target = {
  name: string
  url: string
  segment: Segment
  flow?: Flow
  postLogin?:
    | 'grafana-launchpad'
    | 'grafana-victoria-logs'
    | 'keycloak-admin-console'
    | 'sentiment-sample-positive'
    | 'subnetcalc-rfc1918-lookup'
    | 'developer-portal'
    | 'developer-portal-api-json'
    | 'hubble-namespace-argocd'
    | 'signoz-logs-and-metrics'
}

function isEnabled(envName: string, defaultValue: boolean) {
  const raw = process.env[envName]
  if (!raw) return defaultValue
  return /^(true|1|yes|y)$/i.test(raw)
}

const INCLUDE_SIGNOZ = isEnabled('SSO_E2E_ENABLE_SIGNOZ', false)
const INCLUDE_HEADLAMP = isEnabled('SSO_E2E_ENABLE_HEADLAMP', false)
const INCLUDE_VICTORIA_LOGS = isEnabled('SSO_E2E_ENABLE_VICTORIA_LOGS', false)
const INCLUDE_BACKSTAGE = isEnabled('SSO_E2E_ENABLE_BACKSTAGE', true)
const VERIFY_APP_ACTIONS = isEnabled('SSO_E2E_VERIFY_APP_ACTIONS', true)
const BASE_SCHEME = process.env.SSO_E2E_SCHEME || 'https'
const BASE_DOMAIN = process.env.SSO_E2E_BASE_DOMAIN || '127.0.0.1.sslip.io'
const BASE_PORT = process.env.SSO_E2E_BASE_PORT ? `:${process.env.SSO_E2E_BASE_PORT}` : ''
const SUITE_NAME = process.env.SSO_E2E_SUITE_NAME || 'platform SSO endpoints: smoke'
const PORTAL_HOSTNAME = `portal.${BASE_DOMAIN}`.toLowerCase()
const PORTAL_API_HOSTNAME = `portal-api.${BASE_DOMAIN}`.toLowerCase()

function platformUrl(hostPrefix: string) {
  return `${BASE_SCHEME}://${hostPrefix}.${BASE_DOMAIN}${BASE_PORT}/`
}

function absolutePlatformUrl(hostPrefix: string, path: string) {
  return new URL(path, platformUrl(hostPrefix)).toString()
}

const OIDC_PROVIDER = (process.env.SSO_E2E_PROVIDER || 'keycloak').toLowerCase()
const KEYCLOAK_REALM = process.env.SSO_E2E_KEYCLOAK_REALM || 'platform'
const OIDC_HOST = new URL(
  OIDC_PROVIDER === 'keycloak'
    ? absolutePlatformUrl('keycloak', `/realms/${KEYCLOAK_REALM}/`)
    : absolutePlatformUrl('dex', '/dex/'),
).host
const KEYCLOAK_ADMIN_CONSOLE_URL = absolutePlatformUrl('keycloak', '/admin/platform/console/#/platform/users')

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function normalizeUrl(value: string) {
  return value.replace(/\/$/, '')
}

const GRAFANA_LAUNCHPAD_APPS = [
  { name: 'Argo CD', url: platformUrl('argocd.admin'), flow: 'oauth2-proxy', segment: 'admin' },
  { name: OIDC_PROVIDER === 'keycloak' ? 'Keycloak' : 'Dex', url: OIDC_PROVIDER === 'keycloak' ? KEYCLOAK_ADMIN_CONSOLE_URL : absolutePlatformUrl('dex', '/dex/'), flow: 'none', segment: 'admin' },
  { name: 'Gitea', url: platformUrl('gitea.admin'), flow: 'oauth2-proxy', segment: 'admin' },
  { name: 'Headlamp', url: platformUrl('headlamp.admin'), flow: 'headlamp-oidc', segment: 'admin' },
  { name: 'Hubble', url: platformUrl('hubble.admin'), flow: 'oauth2-proxy', segment: 'admin' },
  { name: 'Kyverno Policy UI', url: platformUrl('kyverno.admin'), flow: 'none', segment: 'admin' },
  { name: 'Hello Platform DEV', url: platformUrl('hello-platform.dev'), flow: 'oauth2-proxy', segment: 'dev' },
  { name: 'Sentiment DEV', url: platformUrl('sentiment.dev'), flow: 'oauth2-proxy', segment: 'dev' },
  { name: 'SubnetCalc DEV', url: platformUrl('subnetcalc.dev'), flow: 'oauth2-proxy', segment: 'dev' },
  { name: 'Hello Platform UAT', url: platformUrl('hello-platform.uat'), flow: 'oauth2-proxy', segment: 'uat' },
  { name: 'Sentiment UAT', url: platformUrl('sentiment.uat'), flow: 'oauth2-proxy', segment: 'uat' },
  { name: 'SubnetCalc UAT', url: platformUrl('subnetcalc.uat'), flow: 'oauth2-proxy', segment: 'uat' },
] as const

const BASE_TARGETS: Target[] = [
  {
    name: 'hello-platform-uat',
    url: platformUrl('hello-platform.uat'),
    segment: 'uat',
    flow: 'oauth2-proxy',
  },
  {
    name: 'subnetcalc-uat',
    url: platformUrl('subnetcalc.uat'),
    segment: 'uat',
    flow: 'oauth2-proxy',
    postLogin: 'subnetcalc-rfc1918-lookup',
  },
  {
    name: 'sentiment-uat',
    url: platformUrl('sentiment.uat'),
    segment: 'uat',
    flow: 'oauth2-proxy',
    postLogin: 'sentiment-sample-positive',
  },
  {
    name: 'sentiment-dev',
    url: platformUrl('sentiment.dev'),
    segment: 'dev',
    flow: 'oauth2-proxy',
    postLogin: 'sentiment-sample-positive',
  },
  {
    name: 'hello-platform-dev',
    url: platformUrl('hello-platform.dev'),
    segment: 'dev',
    flow: 'oauth2-proxy',
  },
  {
    name: 'subnetcalc-dev',
    url: platformUrl('subnetcalc.dev'),
    segment: 'dev',
    flow: 'oauth2-proxy',
    postLogin: 'subnetcalc-rfc1918-lookup',
  },

  {
    name: OIDC_PROVIDER === 'keycloak' ? 'keycloak' : 'dex',
    url: OIDC_PROVIDER === 'keycloak' ? KEYCLOAK_ADMIN_CONSOLE_URL : absolutePlatformUrl('dex', '/dex/'),
    segment: 'admin',
    flow: OIDC_PROVIDER === 'keycloak' ? 'keycloak-admin' : 'none',
    postLogin: OIDC_PROVIDER === 'keycloak' ? 'keycloak-admin-console' : undefined,
  },
  { name: 'gitea-admin', url: platformUrl('gitea.admin'), segment: 'admin', flow: 'oauth2-proxy' },
  {
    name: 'grafana-admin',
    url: platformUrl('grafana.admin'),
    segment: 'admin',
    flow: 'oauth2-proxy',
    postLogin: INCLUDE_VICTORIA_LOGS ? 'grafana-victoria-logs' : undefined,
  },
  { name: 'argocd-admin', url: platformUrl('argocd.admin'), segment: 'admin', flow: 'oauth2-proxy' },
  { name: 'hubble-admin', url: platformUrl('hubble.admin'), segment: 'admin', flow: 'oauth2-proxy', postLogin: 'hubble-namespace-argocd' },
  { name: 'kyverno-admin', url: platformUrl('kyverno.admin'), segment: 'admin', flow: 'none' },
  {
    name: 'developer-portal-api',
    url: absolutePlatformUrl('portal-api', '/api/v1/runtime'),
    segment: 'dev',
    flow: 'oauth2-proxy',
    postLogin: 'developer-portal-api-json',
  },
]

const TARGETS: Target[] = [...BASE_TARGETS]

if (INCLUDE_BACKSTAGE) {
  TARGETS.push({
    name: 'developer-portal',
    url: platformUrl('portal'),
    segment: 'dev',
    flow: 'oauth2-proxy',
    postLogin: 'developer-portal',
  })
}

if (INCLUDE_SIGNOZ) {
  TARGETS.push({
    name: 'signoz-admin',
    url: platformUrl('signoz.admin'),
    segment: 'admin',
    flow: 'oauth2-proxy',
    postLogin: 'signoz-logs-and-metrics',
  })
}

if (INCLUDE_HEADLAMP) {
  // Headlamp uses its own OIDC client and typically opens the provider in a new tab/popup.
  TARGETS.push({ name: 'headlamp-admin', url: platformUrl('headlamp.admin'), segment: 'admin', flow: 'headlamp-oidc' })
}

function creds(segment: Segment) {
  const sharedPassword = process.env.PLATFORM_DEMO_PASSWORD || ''
  if (segment === 'dev') {
    return {
      login: process.env.OIDC_DEV_LOGIN || process.env.KEYCLOAK_DEV_LOGIN || process.env.DEX_DEV_LOGIN || 'demo@dev.test',
      password: process.env.OIDC_DEV_PASSWORD || process.env.KEYCLOAK_DEV_PASSWORD || process.env.DEX_DEV_PASSWORD || sharedPassword,
    }
  }
  if (segment === 'uat') {
    return {
      login: process.env.OIDC_UAT_LOGIN || process.env.KEYCLOAK_UAT_LOGIN || process.env.DEX_UAT_LOGIN || 'demo@uat.test',
      password: process.env.OIDC_UAT_PASSWORD || process.env.KEYCLOAK_UAT_PASSWORD || process.env.DEX_UAT_PASSWORD || sharedPassword,
    }
  }
  return {
    login: process.env.OIDC_ADMIN_LOGIN || process.env.KEYCLOAK_ADMIN_LOGIN || process.env.DEX_ADMIN_LOGIN || 'demo@admin.test',
    password: process.env.OIDC_ADMIN_PASSWORD || process.env.KEYCLOAK_ADMIN_PASSWORD || process.env.DEX_ADMIN_PASSWORD || sharedPassword,
  }
}

function keycloakConsoleCreds() {
  return {
    login: process.env.KEYCLOAK_CONSOLE_ADMIN_LOGIN || process.env.KEYCLOAK_ADMIN_LOGIN || 'demo@admin.test',
    password: process.env.KEYCLOAK_CONSOLE_ADMIN_PASSWORD || process.env.PLATFORM_DEMO_PASSWORD || '',
  }
}

if (!creds('admin').password || !creds('dev').password || !creds('uat').password) {
  throw new Error('Set PLATFORM_DEMO_PASSWORD, OIDC_*_PASSWORD, KEYCLOAK_*_PASSWORD, or DEX_*_PASSWORD before running the SSO smoke tests')
}
if (OIDC_PROVIDER === 'keycloak' && !keycloakConsoleCreds().password) {
  throw new Error('Set PLATFORM_DEMO_PASSWORD or KEYCLOAK_CONSOLE_ADMIN_PASSWORD before running the Keycloak admin console smoke test')
}

async function maybeClickOauth2ProxyProvider(page: Page) {
  // Some oauth2-proxy templates present a provider selection page at /oauth2/sign_in.
  if (!page.url().includes('/oauth2/sign_in')) return

  const btn = page.getByRole('button', { name: /sign in with openid connect/i })
  if (await btn.isVisible().catch(() => false)) {
    await btn.click()
  }
}

async function completeDexLocalLogin(page: Page, login: string, password: string) {
  // Dex local login form.
  await page.waitForSelector('#login', { timeout: 60_000 })
  await page.fill('#login', login)
  await page.fill('#password', password)
  await page.click('#submit-login')
}

async function completeKeycloakLogin(page: Page, login: string, password: string) {
  await page.waitForSelector('#username', { timeout: 60_000 })
  await page.fill('#username', login)
  await page.fill('#password', password)
  await page.click('#kc-login')
}

async function completeOidcLogin(page: Page, login: string, password: string) {
  if (OIDC_PROVIDER === 'keycloak') {
    await completeKeycloakLogin(page, login, password)
    return
  }
  await completeDexLocalLogin(page, login, password)
  await maybeGrantDexAccess(page)
}

async function maybeGrantDexAccess(page: Page) {
  // oauth2-proxy requests include `approval_prompt=force`, so Dex will show consent even if
  // skipApprovalScreen=true. Click through if present.
  const grant = page.getByRole('button', { name: /^grant access$/i })
  if (await grant.isVisible().catch(() => false)) {
    await grant.click()
  }
}

async function ensureOnTargetOrOidc(page: Page, targetUrl: string) {
  const host = new URL(targetUrl).host
  await page.waitForURL((u) => u.host === host || u.host === OIDC_HOST, { timeout: 60_000 })
}

async function gotoWithGatewayRetry(page: Page, url: string) {
  const maxAttempts = Number(process.env.SSO_E2E_GOTO_RETRIES || 10)
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      const resp = await page.goto(url, { waitUntil: 'domcontentloaded' })
      const status = resp?.status() ?? 0

      // NGINX gateway error pages when upstreams are still coming up.
      const gatewayErrorHeading = page.getByRole('heading', { name: /(502 Bad Gateway|503 Service Unavailable|504 Gateway Time-out)/i })
      const isGatewayError = (status >= 500 && status < 600) || (await gatewayErrorHeading.isVisible().catch(() => false))

      if (!isGatewayError) return
    } catch {
      // Network/navigation hiccup; retry below.
    }

    if (attempt === maxAttempts) break
    await page.waitForTimeout(1500 * attempt)
  }

  throw new Error(`Failed to load ${url} without gateway errors after ${maxAttempts} attempts`)
}

async function isGatewayErrorPage(page: Page) {
  const heading = page.getByRole('heading', { name: /(502 Bad Gateway|503 Service Unavailable|504 Gateway Time-out)/i })
  if (await heading.isVisible().catch(() => false)) return true
  const bodyText = page.locator('body')
  // Some nginx error pages don't expose a heading role reliably; fall back to text checks.
  if (await bodyText.getByText(/502 Bad Gateway|503 Service Unavailable|504 Gateway Time-out/i).isVisible().catch(() => false)) return true
  return false
}

async function isOauth2ProxyErrorPage(page: Page) {
  const heading = page.getByRole('heading', { name: /Internal Server Error/i })
  if (!(await heading.isVisible().catch(() => false))) return false
  return page.getByText(/Secured with\s+OAuth2 Proxy/i).isVisible().catch(() => false)
}

async function isOauth2ProxyForbiddenPage(page: Page) {
  const body = page.locator('body')
  return body.getByText(/Forbidden|Invalid authentication via OAuth2|unauthorized/i).isVisible().catch(() => false)
}

async function assertNoGatewayErrorWithReloads(page: Page, name: string) {
  const maxAttempts = Number(process.env.SSO_E2E_POSTLOGIN_RETRIES || 3)
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    if (!(await isGatewayErrorPage(page))) return
    if (attempt === maxAttempts) break
    await page.reload({ waitUntil: 'domcontentloaded' }).catch(() => undefined)
    await page.waitForTimeout(1000 * attempt)
  }
  throw new Error(`Post-login page for ${name} appears to be an nginx gateway error (5xx). url=${page.url()}`)
}

async function loginViaOauth2ProxyRedirectOnce(page: Page, target: Target) {
  const { login, password } = creds(target.segment)
  const targetHost = new URL(target.url).host
  const isTargetAppUrl = (url: URL) => url.host === targetHost && !url.pathname.startsWith('/oauth2/')

  await gotoWithGatewayRetry(page, target.url)
  await ensureOnTargetOrOidc(page, target.url)

  // If we landed on the target host, we may already be authenticated.
  if (isTargetAppUrl(new URL(page.url()))) return

  await maybeClickOauth2ProxyProvider(page)
  if (OIDC_PROVIDER === 'keycloak') {
    await page.waitForURL(/protocol\/openid-connect\/auth/, { timeout: 60_000 })
  } else {
    await page.waitForURL(/dex\/auth/, { timeout: 60_000 })
    if (!page.url().includes('/dex/auth/local/login')) {
      await page.waitForURL(/dex\/auth\/local\/login/, { timeout: 60_000 })
    }
  }

  await completeOidcLogin(page, login, password)

  // After login we should come back to the target host.
  if (isTargetAppUrl(new URL(page.url()))) return
  await page.waitForURL((u) => isTargetAppUrl(u), { timeout: 60_000 })
}

async function loginViaOauth2ProxyRedirect(page: Page, target: Target) {
  const maxAttempts = 2
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      await loginViaOauth2ProxyRedirectOnce(page, target)
      await page.waitForLoadState('domcontentloaded', { timeout: 30_000 }).catch(() => undefined)
      if (!(await isOauth2ProxyErrorPage(page))) return
    } catch (err) {
      if (attempt === maxAttempts) throw err
    }

    if (attempt === maxAttempts) break
    await page.context().clearCookies()
    await page.goto('about:blank').catch(() => undefined)
  }

  throw new Error(`OAuth2 proxy returned an internal error during login for ${target.name}`)
}

async function loadWithoutLogin(page: Page, target: Target) {
  const targetUrl = new URL(target.url)

  await gotoWithGatewayRetry(page, target.url)
  await page.waitForURL((u) => u.host === targetUrl.host, { timeout: 60_000 })
}

async function loginHeadlampPopupFlow(page: Page, target: Target) {
  const { login, password } = creds(target.segment)
  const targetHost = new URL(target.url).host

  await gotoWithGatewayRetry(page, target.url)
  await page.waitForLoadState('networkidle', { timeout: 60_000 }).catch(() => undefined)

  if (await isHeadlampAuthenticated(page, targetHost)) return

  const signIn = await findHeadlampSignIn(page)
  expect(signIn, 'Headlamp did not expose a sign-in action before OIDC login').not.toBeNull()
  if (!signIn) return

  const popupPromise = page.waitForEvent('popup').catch(() => null)
  await signIn.click()

  const popup = await popupPromise
  if (popup) {
    await popup.waitForLoadState('domcontentloaded')
    await popup.waitForURL((u) => u.host === targetHost || u.host === OIDC_HOST, { timeout: 60_000 })

    if (new URL(popup.url()).host !== targetHost) {
      await popup
        .waitForURL((u) => u.host === targetHost || u.host === OIDC_HOST, { timeout: 60_000 })
        .catch(() => undefined)
    }

    if ((await popup.locator('#login').isVisible().catch(() => false)) || (await popup.locator('#username').isVisible().catch(() => false))) {
      await completeOidcLogin(popup, login, password)
    }

    // Some flows close the popup, others redirect it back to Headlamp.
    await Promise.race([
      popup.waitForEvent('close').catch(() => undefined),
      popup.waitForURL(new RegExp(new URL(target.url).host.replaceAll('.', '\\\\.')), { timeout: 60_000 }).catch(() => undefined),
    ])
  } else {
    // If no popup, it might be a same-tab redirect to the OIDC provider.
    await page.waitForURL((u) => u.host === OIDC_HOST, { timeout: 60_000 })
    await completeOidcLogin(page, login, password)
    await page.waitForURL((u) => u.host === new URL(target.url).host, { timeout: 60_000 })
  }

  const candidates = [popup, page].filter((candidate): candidate is Page => Boolean(candidate))

  for (const candidate of candidates) {
    await candidate.waitForLoadState('domcontentloaded', { timeout: 15_000 }).catch(() => undefined)
    if (candidate === page) {
      await page.goto(target.url, { waitUntil: 'domcontentloaded' }).catch(() => undefined)
    }

    try {
      await waitForHeadlampAuthenticated(candidate, targetHost, 15_000)

      if (candidate !== page) {
        await page.goto(target.url, { waitUntil: 'domcontentloaded' }).catch(() => undefined)
        await waitForHeadlampAuthenticated(page, targetHost, 15_000).catch(() => undefined)
      }
      return
    } catch {
      // Try the next candidate page.
    }
  }

  await page.goto(target.url, { waitUntil: 'domcontentloaded' }).catch(() => undefined)
  await waitForHeadlampAuthenticated(page, targetHost)
}

async function findHeadlampSignIn(page: Page) {
  const signInCandidates = [
    page.getByRole('button', { name: /^sign in$/i }),
    page.getByRole('button', { name: /^log in$/i }),
    page.getByRole('link', { name: /^sign in$/i }),
    page.getByRole('link', { name: /^log in$/i }),
  ]

  for (const candidate of signInCandidates) {
    if (await candidate.isVisible().catch(() => false)) return candidate
  }

  return null
}

async function fetchHeadlampStatus(page: Page, path: string) {
  return page.evaluate(async (resourcePath) => {
    try {
      const response = await fetch(resourcePath, { credentials: 'include' })
      return response.status
    } catch {
      return -1
    }
  }, path)
}

async function isHeadlampAuthenticated(page: Page, targetHost: string) {
  const current = new URL(page.url())
  if (current.host !== targetHost) return false
  if (current.pathname === '/c/main/login') return false

  const [meStatus, healthStatus] = await Promise.all([
    fetchHeadlampStatus(page, '/clusters/main/me'),
    fetchHeadlampStatus(page, '/clusters/main/healthz'),
  ])

  return meStatus === 200 && healthStatus === 200
}

async function waitForHeadlampAuthenticated(page: Page, targetHost: string, timeout = 60_000) {
  await expect.poll(
    async () => isHeadlampAuthenticated(page, targetHost),
    {
      message: 'Headlamp did not establish an authenticated Kubernetes session',
      timeout,
    },
  ).toBe(true)

  await expect(page).not.toHaveURL(/\/c\/main\/login(?:\?|$)/)
  expect(await findHeadlampSignIn(page)).toBeNull()
}

async function loginKeycloakAdminConsole(page: Page, target: Target) {
  const { login, password } = keycloakConsoleCreds()
  await gotoWithGatewayRetry(page, target.url)
  await page.waitForURL(/\/admin\/platform\/console\//, { timeout: 60_000 })

  const username = page.locator('#username')
  await expect(username).toBeVisible({ timeout: 60_000 })
  if (await username.isVisible().catch(() => false)) {
    await username.fill(login)
    await page.locator('#password').fill(password)
    await page.locator('#kc-login').click()
  }

  await page.waitForURL(/\/admin\/platform\/console\//, { timeout: 120_000 })
}

async function keycloakAdminConsoleWorks(page: Page) {
  await expect(page.locator('body')).not.toContainText(/Timeout when waiting for 3rd party check iframe message/i, { timeout: 10_000 })
  await expect(page.locator('body')).not.toContainText(/Something went wrong/i, { timeout: 10_000 })
  await expect(page.locator('body')).not.toContainText(/temporary admin user/i, { timeout: 10_000 })
  await expect(page.locator('#username')).toHaveCount(0)
  await expect(page).toHaveURL(/\/admin\/platform\/console\/#\/platform\/users/)
  await expect(page.locator('body')).toContainText(/Realm|Users|Clients|Groups/i, { timeout: 120_000 })
}

async function sentimentSamplePositiveAndAnalyze(page: Page) {
  // Try to align with the existing sentiment Playwright tests in apps/sentiment.
  // Be tolerant to minor UI changes; prefer role/name selectors.
  const heading = page.getByText('Sentiment Analysis (Authenticated UI)')
  await expect(heading).toBeVisible({ timeout: 60_000 })

  const samplePositive = page.getByRole('button', { name: 'Sample: Positive' })
  const analyzeButton = page.getByRole('button', { name: 'Analyze' })

  await expect(samplePositive).toBeVisible({ timeout: 60_000 })
  await samplePositive.click()

  // Analyze and wait for backend response (handles slow models).
  // This stack can be intermittently slow/flaky during warmup; retry a few times on 5xx.
  const maxAttempts = Number(process.env.SSO_E2E_SENTIMENT_ANALYZE_RETRIES || 3)
  const errors: Array<{ attempt: number; status: number; body: string }> = []
  let postResponseBody = ''

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    await expect(analyzeButton).toBeEnabled({ timeout: 60_000 })

    const post = page.waitForResponse((r) => r.url().includes('/api/v1/comments') && r.request().method() === 'POST', {
      timeout: 180_000,
    })

    await analyzeButton.click()
    const postResponse = await post
    const status = postResponse.status()
    postResponseBody = await postResponse.text().catch(() => '')

    if (status === 200) break

    errors.push({ attempt, status, body: postResponseBody.slice(0, 2000) })
    if (attempt === maxAttempts) {
      throw new Error(`Sentiment analyze failed after ${maxAttempts} attempts. ${JSON.stringify(errors, null, 2)}`)
    }

    // Give the backend a chance to recover and try again.
    await page.waitForTimeout(1500 * attempt)
  }

  const postResponseJson = postResponseBody ? JSON.parse(postResponseBody) : null
  expect(typeof postResponseJson?.label).toBe('string')
  expect(['positive', 'negative', 'neutral']).toContain(postResponseJson?.label)
  expect(typeof postResponseJson?.confidence).toBe('number')

  // UI result: classification should render, with confidence/latency visible.
  const lastResultValue = page.locator('.status .value')
  await expect(lastResultValue).toContainText(/positive|negative|neutral/i, { timeout: 60_000 })
  await expect(page.locator('.status .footnote')).toContainText(/Confidence:/i, { timeout: 60_000 })
  await expect(page.locator('.status .footnote')).toContainText(/Latency:/i, { timeout: 60_000 })

  const statusStrong = page.locator('.status .tag strong')
  await expect(statusStrong).toContainText(/ok/i, { timeout: 60_000 })
}

async function subnetcalcRfc1918Lookup(page: Page) {
  const maxAttempts = Number(process.env.SSO_E2E_SUBNETCALC_LOOKUP_RETRIES || 3)
  const errors: Array<{ attempt: number; message: string; body: string }> = []

  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    const rfcBtn = page.getByRole('button', { name: /RFC1918:\s*10\.0\.0\.0\/24/i })
    await expect(rfcBtn).toBeVisible({ timeout: 60_000 })
    await rfcBtn.click()

    const lookup = page.getByRole('button', { name: /^lookup$/i })
    await expect(lookup).toBeVisible({ timeout: 60_000 })
    await lookup.click()

    const results = page.locator('#results')

    try {
      await expect(results).toBeVisible({ timeout: 30_000 })
      await expect(results).toContainText(/Results/i)

      // Validate a few stable fields (use table structure; the rendered text has no whitespace boundaries).
      const validation = results.locator('article').filter({ has: page.getByRole('heading', { name: /^Validation$/i }) })
      await expect(validation).toBeVisible({ timeout: 60_000 })
      await expect(validation.locator('tr', { hasText: 'Valid' }).locator('td').nth(0)).toHaveText(/Yes/i)
      await expect(validation.locator('tr', { hasText: 'Address' }).locator('td').nth(0)).toHaveText(/10\.0\.0\.0\/24/i)

      const rfc1918 = results
        .locator('article')
        .filter({ has: page.getByRole('heading', { name: /^(RFC1918 )?Private Address Check$/i }) })
      await expect(rfc1918).toBeVisible({ timeout: 60_000 })
      await expect(rfc1918.locator('tr', { hasText: /RFC1918/i }).locator('td').nth(0)).toHaveText(/Yes/i)

      const performanceTiming = results
        .locator('article')
        .filter({ has: page.getByRole('heading', { name: /^Performance( Timing| - Overall)$/i }) })
      await expect(performanceTiming).toBeVisible({ timeout: 60_000 })
      await expect(performanceTiming.locator('tr', { hasText: 'Total Response Time' }).locator('td').nth(0)).toContainText(
        /\d+ms\s+\(\d+\.\d{3}s\)/i,
      )

      const expectedTimedArticles = ['Validation', 'Private Address Check', 'Cloudflare Check', /^Subnet Information/i]
      for (const heading of expectedTimedArticles) {
        const article = results.locator('article').filter({ has: page.getByRole('heading', { name: heading }) })
        const apiCallDetails = article.locator('details').filter({ hasText: /API Call Timing/i })
        await expect(apiCallDetails, `Missing subnetcalc API call timing for ${heading.toString()}`).toBeVisible({ timeout: 60_000 })
        await apiCallDetails.locator('summary').click()
        await expect(apiCallDetails.locator('tr', { hasText: 'Duration' }).locator('td').nth(0)).toContainText(/\d+ms/i)
        await expect(apiCallDetails.locator('tr', { hasText: 'Request (UTC)' }).locator('td').nth(0)).not.toHaveText(/^$/)
        await expect(apiCallDetails.locator('tr', { hasText: 'Response (UTC)' }).locator('td').nth(0)).not.toHaveText(/^$/)
      }

      return
    } catch (error) {
      errors.push({
        attempt,
        message: error instanceof Error ? error.message : String(error),
        body: (((await page.locator('body').textContent()) ?? '').replace(/\s+/g, ' ')).slice(0, 2000),
      })
      if (attempt === maxAttempts) {
        throw new Error(`Subnetcalc RFC1918 lookup failed after ${maxAttempts} attempts. ${JSON.stringify(errors, null, 2)}`)
      }

      await page.reload({ waitUntil: 'domcontentloaded' }).catch(() => undefined)
      await assertNoGatewayErrorWithReloads(page, 'subnetcalc-rfc1918-lookup')
    }
  }
}

async function hubbleChooseNamespaceArgocd(page: Page, baseUrl: string) {
  // Navigate to a URL that should show argocd selected, then (if present) exercise the UI picker.
  const u = new URL(baseUrl)
  u.searchParams.set('namespace', 'argocd')
  await gotoWithGatewayRetry(page, u.toString())

  const chooseBtn = page.getByRole('button', { name: /choose namespace/i })
  if (await chooseBtn.isVisible().catch(() => false)) {
    await chooseBtn.click()

    // Blueprint/Popper menus often render as menuitems.
    const menuItem = page.getByRole('menuitem', { name: /^argocd$/i })
    if (await menuItem.isVisible().catch(() => false)) {
      await menuItem.click()
    } else {
      // Fallback: plain text item.
      const textItem = page.getByText(/^argocd$/i).first()
      if (await textItem.isVisible().catch(() => false)) {
        await textItem.click()
      }
    }
  }

  await page.waitForTimeout(500)
  expect(page.url()).toContain('namespace=argocd')
}

async function grafanaLaunchpadShowsHealthyTiles(page: Page) {
  const maxLaunchpadAttempts = Number(process.env.SSO_E2E_GRAFANA_LAUNCHPAD_RETRIES || 24)
  const body = page.locator('body')
  let launchpadBodyText = ''

  for (let attempt = 1; attempt <= maxLaunchpadAttempts; attempt++) {
    launchpadBodyText = (await body.textContent().catch(() => ''))?.replace(/\s+/g, ' ').trim() ?? ''
    if (/Platform Launchpad/i.test(launchpadBodyText)) {
      break
    }

    if (attempt < maxLaunchpadAttempts) {
      await page.waitForTimeout(5_000)
      await page.reload({ waitUntil: 'domcontentloaded' }).catch(() => undefined)
    }
  }

  expect(launchpadBodyText, 'Grafana launchpad dashboard did not render').toMatch(/Platform Launchpad/i)

  for (const app of GRAFANA_LAUNCHPAD_APPS) {
    const region = page.getByRole('region', { name: app.name })
    await expect(region, `Grafana launchpad region missing for ${app.name}`).toBeVisible({ timeout: 120_000 })
    let healthy = false
    let lastRegionText = ''

    for (let attempt = 1; attempt <= maxLaunchpadAttempts; attempt++) {
      lastRegionText = (await region.textContent().catch(() => ''))?.replace(/\s+/g, ' ').trim() ?? ''
      if (/Healthy|Up/i.test(lastRegionText)) {
        healthy = true
        break
      }

      if (attempt < maxLaunchpadAttempts) {
        await page.waitForTimeout(5_000)
        await page.reload({ waitUntil: 'domcontentloaded' }).catch(() => undefined)
        await expect(page.locator('body')).toContainText(/Platform Launchpad/i, { timeout: 120_000 })
      }
    }

    expect(healthy, `Grafana launchpad tile for ${app.name} is not healthy: ${lastRegionText}`).toBe(true)

    const openLink = region.getByRole('link', { name: new RegExp(`^Open\\s+${escapeRegExp(app.name)}$`, 'i') })
    await expect(openLink, `Grafana launchpad link missing for ${app.name}`).toBeVisible({ timeout: 120_000 })

    await expect
      .poll(
        async () => {
          const href = await openLink.getAttribute('href')
          return normalizeUrl(new URL(href ?? '', page.url()).toString())
        },
        {
          message: `Grafana launchpad link href mismatch for ${app.name}`,
          timeout: 30_000,
        },
      )
      .toBe(normalizeUrl(app.url))
  }
}

async function grafanaVictoriaLogsDashboardWorks(page: Page, baseUrl: string) {
  const plugin = await page.evaluate(async () => {
    const response = await fetch('/api/plugins/victoriametrics-logs-datasource/settings', { credentials: 'include' })
    const body = await response.text()
    return { status: response.status, body }
  })
  expect(plugin.status, plugin.body).toBe(200)
  expect(plugin.body).toContain('victoriametrics-logs-datasource')

  const datasource = await page.evaluate(async () => {
    const response = await fetch('/api/datasources/uid/victorialogs', { credentials: 'include' })
    const body = await response.text()
    return { status: response.status, body }
  })
  expect(datasource.status, datasource.body).toBe(200)
  expect(datasource.body).toContain('"type":"victoriametrics-logs-datasource"')

  const dashboardUrl = new URL('/d/platform-logs/platform-logs?orgId=1&from=now-6h&to=now&timezone=browser&refresh=30s', baseUrl)
  await gotoWithGatewayRetry(page, dashboardUrl.toString())
  await page.waitForLoadState('domcontentloaded', { timeout: 60_000 }).catch(() => undefined)
  await assertNoGatewayErrorWithReloads(page, 'grafana-victoria-logs')

  const body = page.locator('body')
  await expect(body).toContainText(/Platform Logs/i, { timeout: 120_000 })
  await expect(body).toContainText(/Logs by Namespace/i, { timeout: 120_000 })
  await expect(body).toContainText(/Error Logs by Namespace/i, { timeout: 120_000 })
  await expect(body).toContainText(/Recent Error Logs/i, { timeout: 120_000 })
  await expect(body).not.toContainText(/Datasource victorialogs was not found/i)
  await expect(body).not.toContainText(/Could not find plugin definition for data source/i)
}

async function signozLogsExplorerHasContent(page: Page, baseUrl: string) {
  const u = new URL('/logs/logs-explorer', baseUrl)
  await gotoWithGatewayRetry(page, u.toString())
  await assertNoGatewayErrorWithReloads(page, 'signoz-logs')

  await expect(page.locator('.logs-explorer-views-container')).toBeVisible({ timeout: 120_000 })

  // SigNoz may show an onboarding modal that can block interactions.
  const quickFiltersOkay = page.getByRole('button', { name: /^okay$/i })
  if (await quickFiltersOkay.isVisible().catch(() => false)) {
    await quickFiltersOkay.click()
  }

  // Logs explorer often needs an explicit query execution.
  // DOM rendering is virt-scroller based and can be flaky; assert against the query API response.
  const runQuery = page.getByRole('button', { name: /run query/i })
  await runQuery.waitFor({ state: 'visible', timeout: 30_000 })

  const deadline = Date.now() + 120_000
  let lastRowCount = 0
  while (Date.now() < deadline) {
    const remainingMs = deadline - Date.now()

    const respPromise = page.waitForResponse(
      (resp) => resp.url().includes('/api/v5/query_range') && resp.request().method() === 'POST',
      { timeout: Math.min(30_000, remainingMs) },
    )

    await runQuery.click()

    let resp
    try {
      resp = await respPromise
    } catch {
      await page.waitForTimeout(1000)
      continue
    }

    if (resp.status() !== 200) {
      await page.waitForTimeout(1000)
      continue
    }

    const body: any = await resp.json().catch(() => null)
    const results = body?.data?.data?.results
    const rows = Array.isArray(results) ? results.flatMap((r: any) => (Array.isArray(r?.rows) ? r.rows : [])) : []
    lastRowCount = rows.length
    if (lastRowCount > 0) return

    await page.waitForTimeout(2000)
  }

  throw new Error(`SigNoz logs query returned 0 rows after retries (lastRowCount=${lastRowCount})`)
}

async function signozMetricsExplorerSummaryHasContent(page: Page, baseUrl: string) {
  const u = new URL('/metrics-explorer/summary', baseUrl)
  await gotoWithGatewayRetry(page, u.toString())
  await assertNoGatewayErrorWithReloads(page, 'signoz-metrics')

  // SigNoz metrics summary renders a table; ensure it has data rows.
  const rows = page.locator('table tbody tr')
  await expect.poll(async () => rows.count(), { timeout: 120_000 }).toBeGreaterThan(0)
}

async function signozVerifyLogsAndMetrics(page: Page, baseUrl: string) {
  await signozLogsExplorerHasContent(page, baseUrl)
  await signozMetricsExplorerSummaryHasContent(page, baseUrl)
}

type BrowserApiTraffic = {
  requestUrls: string[]
  responses: Array<{ url: string; status: number }>
}

function isBrowserApiUrl(value: string) {
  try {
    return new URL(value).pathname.startsWith('/api/')
  } catch {
    return false
  }
}

function isLoopbackApiTarget(value: string) {
  const hostname = new URL(value).hostname.toLowerCase()
  return hostname === 'localhost' || hostname === '127.0.0.1' || hostname === '::1'
}

function usesPortalApiHost(value: string) {
  return new URL(value).hostname === PORTAL_API_HOSTNAME
}

function isBackstageCatalogApiResponse(response: { url: string; status: number }) {
  const url = new URL(response.url)
  return url.hostname === PORTAL_HOSTNAME && url.pathname.startsWith('/api/catalog/') && response.status >= 200 && response.status < 400
}

function watchBrowserApiTraffic(page: Page): BrowserApiTraffic {
  const traffic: BrowserApiTraffic = {
    requestUrls: [],
    responses: [],
  }

  page.on('request', (request) => {
    const url = request.url()
    if (isBrowserApiUrl(url)) {
      traffic.requestUrls.push(url)
    }
  })

  page.on('response', (response) => {
    const url = response.url()
    if (isBrowserApiUrl(url)) {
      traffic.responses.push({ url, status: response.status() })
    }
  })

  return traffic
}

async function bodyText(page: Page) {
  return ((await page.locator('body').textContent().catch(() => '')) ?? '').replace(/\s+/g, ' ').trim()
}

async function expectBodyToContain(page: Page, pattern: RegExp, message: string) {
  await expect.poll(() => bodyText(page), { message, timeout: 120_000 }).toMatch(pattern)
}

async function developerPortalWorks(page: Page, traffic: BrowserApiTraffic) {
  await expect(page).toHaveURL((u) => u.hostname === PORTAL_HOSTNAME && !u.pathname.startsWith('/oauth2/'))
  await expect(page).toHaveURL((u) => u.pathname === '/' || u.pathname.startsWith('/catalog'))

  const body = page.locator('body')
  await expect(body).not.toContainText(/sign in as guest|continue as guest|guest sign[- ]?in/i, { timeout: 10_000 })
  await expect(page.getByRole('button', { name: /guest/i })).toHaveCount(0)
  await expect(page.getByRole('link', { name: /guest/i })).toHaveCount(0)

  await expectBodyToContain(page, /Platform Engineering Catalog|Catalog/i, 'Backstage catalog shell did not render after edge SSO login')
  const allComponentsFilter = page.getByRole('menuitem', { name: /All\s+5/i })
  await expect(allComponentsFilter, 'Backstage catalog did not expose the full platform catalog filter').toBeVisible({ timeout: 30_000 })
  await allComponentsFilter.click()
  await expectBodyToContain(page, /Developer Portal/i, 'Backstage catalog did not expose the Backstage portal component')
  await expectBodyToContain(page, /Portal API/i, 'Backstage catalog did not expose the IDP API component')
  await expectBodyToContain(page, /Hello Platform/i, 'Backstage catalog did not expose workload catalog content')

  await expect
    .poll(() => traffic.responses.some(isBackstageCatalogApiResponse), {
      message: 'Developer portal did not load Backstage catalog content through the portal host',
      timeout: 60_000,
    })
    .toBe(true)

  const loopbackApiUrls = traffic.requestUrls.filter(isLoopbackApiTarget)
  expect(loopbackApiUrls, 'Developer portal browser API calls must not target localhost or raw loopback').toEqual([])
}

async function fetchJsonThroughBrowser(page: Page, path: string) {
  const result = await page.evaluate(async (resourcePath) => {
    const response = await fetch(resourcePath, {
      credentials: 'include',
      headers: { accept: 'application/json' },
    })
    const text = await response.text()
    let json: any = null
    try {
      json = JSON.parse(text)
    } catch {
      // Return the raw body below so the assertion explains non-JSON responses.
    }

    return {
      body: text.slice(0, 2000),
      contentType: response.headers.get('content-type') ?? '',
      json,
      status: response.status,
      url: response.url,
    }
  }, path)

  expect(result.status, result.body).toBe(200)
  expect(result.contentType).toMatch(/application\/json/i)
  expect(result.json, result.body).not.toBeNull()
  expect(usesPortalApiHost(result.url), `Portal API response URL should use ${PORTAL_API_HOSTNAME}: ${result.url}`).toBe(true)

  return result.json
}

async function portalApiJsonWorks(page: Page) {
  const runtime = await fetchJsonThroughBrowser(page, '/api/v1/runtime')
  expect(typeof runtime?.active_runtime?.name).toBe('string')
  expect(['generic_kubernetes', 'kind', 'lima']).toContain(runtime.active_runtime.name)

  const catalog = await fetchJsonThroughBrowser(page, '/api/v1/catalog/apps')
  expect(Array.isArray(catalog?.applications)).toBe(true)
  expect(catalog.applications.some((app: any) => app?.name === 'backstage')).toBe(true)
  expect(catalog.applications.some((app: any) => app?.name === 'idp-core')).toBe(true)
  expect(catalog.applications.some((app: any) => app?.name === 'hello-platform')).toBe(true)
}

async function attachLoggedInScreenshotIfEnabled(page: Page, testInfo: TestInfo, name: string) {
  if (process.env.SSO_E2E_CAPTURE !== '1') return

  await testInfo.attach(`${name}-after-login`, {
    body: await page.screenshot({ fullPage: true }),
    contentType: 'image/png',
  })
}

test.describe(SUITE_NAME, () => {
  test.describe.configure({ mode: 'serial' })

  for (const t of TARGETS) {
    test(`${t.name}: load and login`, async ({ page }, testInfo) => {
      test.setTimeout(180_000)
      const browserApiTraffic = t.postLogin === 'developer-portal' ? watchBrowserApiTraffic(page) : undefined

      if (t.flow === 'headlamp-oidc') {
        await loginHeadlampPopupFlow(page, t)
      } else if (t.flow === 'keycloak-admin') {
        await loginKeycloakAdminConsole(page, t)
      } else if (t.flow === 'none') {
        await loadWithoutLogin(page, t)
      } else {
        await loginViaOauth2ProxyRedirect(page, t)
      }

      // If the upstream is broken, we want a hard failure (e.g. SigNoz 502 after login).
      await assertNoGatewayErrorWithReloads(page, t.name)
      expect(await isOauth2ProxyForbiddenPage(page), `OAuth2 proxy rejected post-login access for ${t.name}; url=${page.url()}`).toBe(false)

      if (VERIFY_APP_ACTIONS) {
        if (t.postLogin === 'sentiment-sample-positive') {
          await sentimentSamplePositiveAndAnalyze(page)
        }
        if (t.postLogin === 'subnetcalc-rfc1918-lookup') {
          await subnetcalcRfc1918Lookup(page)
        }
        if (t.postLogin === 'developer-portal') {
          await developerPortalWorks(page, browserApiTraffic ?? watchBrowserApiTraffic(page))
        }
        if (t.postLogin === 'developer-portal-api-json') {
          await portalApiJsonWorks(page)
        }
        if (t.postLogin === 'hubble-namespace-argocd') {
          await hubbleChooseNamespaceArgocd(page, t.url)
        }
        if (t.postLogin === 'grafana-launchpad') {
          await grafanaLaunchpadShowsHealthyTiles(page)
        }
        if (t.postLogin === 'grafana-victoria-logs') {
          await grafanaVictoriaLogsDashboardWorks(page, t.url)
        }
        if (t.postLogin === 'keycloak-admin-console') {
          await keycloakAdminConsoleWorks(page)
        }
        if (t.postLogin === 'signoz-logs-and-metrics') {
          await signozVerifyLogsAndMetrics(page, t.url)
        }
      }

      await attachLoggedInScreenshotIfEnabled(page, testInfo, t.name)

      // Common assertion: we should not be sitting on the OIDC login form.
      await expect(page.locator('#login')).toHaveCount(0)
      await expect(page.locator('#username')).toHaveCount(0)
      const finalUrl = new URL(page.url())
      if (t.name !== 'keycloak' && t.name !== 'dex') {
        expect(finalUrl.host === OIDC_HOST).toBe(false)
      }
    })
  }
})
