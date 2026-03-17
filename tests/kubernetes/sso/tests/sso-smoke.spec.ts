import { expect, test, type Page, type TestInfo } from '@playwright/test'

type Segment = 'dev' | 'uat' | 'admin'

type Flow = 'oauth2-proxy' | 'headlamp-oidc' | 'none'

type Target = {
  name: string
  url: string
  segment: Segment
  flow?: Flow
  postLogin?:
    | 'grafana-launchpad'
    | 'sentiment-sample-positive'
    | 'subnetcalc-rfc1918-lookup'
    | 'hubble-namespace-argocd'
    | 'signoz-logs-and-metrics'
}

function isEnabled(envName: string, defaultValue: boolean) {
  const raw = process.env[envName]
  if (!raw) return defaultValue
  return /^(true|1|yes|y)$/i.test(raw)
}

const INCLUDE_SIGNOZ = isEnabled('SSO_E2E_ENABLE_SIGNOZ', false)
const INCLUDE_HEADLAMP = isEnabled('SSO_E2E_ENABLE_HEADLAMP', true)
const VERIFY_APP_ACTIONS = isEnabled('SSO_E2E_VERIFY_APP_ACTIONS', true)
const BASE_SCHEME = process.env.SSO_E2E_SCHEME || 'https'
const BASE_DOMAIN = process.env.SSO_E2E_BASE_DOMAIN || '127.0.0.1.sslip.io'
const BASE_PORT = process.env.SSO_E2E_BASE_PORT ? `:${process.env.SSO_E2E_BASE_PORT}` : ''
const SUITE_NAME = process.env.SSO_E2E_SUITE_NAME || 'platform SSO endpoints: smoke'

function platformUrl(hostPrefix: string) {
  return `${BASE_SCHEME}://${hostPrefix}.${BASE_DOMAIN}${BASE_PORT}/`
}

function absolutePlatformUrl(hostPrefix: string, path: string) {
  return new URL(path, platformUrl(hostPrefix)).toString()
}

const DEX_HOST = new URL(absolutePlatformUrl('dex', '/dex/')).host

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function normalizeUrl(value: string) {
  return value.replace(/\/$/, '')
}

const GRAFANA_LAUNCHPAD_APPS = [
  { name: 'Argo CD', url: platformUrl('argocd.admin'), flow: 'oauth2-proxy', segment: 'admin' },
  { name: 'Dex', url: absolutePlatformUrl('dex', '/dex/'), flow: 'none', segment: 'admin' },
  { name: 'Gitea', url: platformUrl('gitea.admin'), flow: 'oauth2-proxy', segment: 'admin' },
  { name: 'Headlamp', url: platformUrl('headlamp.admin'), flow: 'headlamp-oidc', segment: 'admin' },
  { name: 'Hubble', url: platformUrl('hubble.admin'), flow: 'oauth2-proxy', segment: 'admin' },
  { name: 'Kyverno Policy UI', url: platformUrl('kyverno.admin'), flow: 'none', segment: 'admin' },
  { name: 'Sentiment DEV', url: platformUrl('sentiment.dev'), flow: 'oauth2-proxy', segment: 'dev' },
  { name: 'SubnetCalc DEV', url: platformUrl('subnetcalc.dev'), flow: 'oauth2-proxy', segment: 'dev' },
  { name: 'Sentiment UAT', url: platformUrl('sentiment.uat'), flow: 'oauth2-proxy', segment: 'uat' },
  { name: 'SubnetCalc UAT', url: platformUrl('subnetcalc.uat'), flow: 'oauth2-proxy', segment: 'uat' },
] as const

const BASE_TARGETS: Target[] = [
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
    name: 'subnetcalc-dev',
    url: platformUrl('subnetcalc.dev'),
    segment: 'dev',
    flow: 'oauth2-proxy',
    postLogin: 'subnetcalc-rfc1918-lookup',
  },

  { name: 'dex', url: absolutePlatformUrl('dex', '/dex/'), segment: 'admin', flow: 'none' },
  { name: 'gitea-admin', url: platformUrl('gitea.admin'), segment: 'admin', flow: 'oauth2-proxy' },
  { name: 'grafana-admin', url: platformUrl('grafana.admin'), segment: 'admin', flow: 'oauth2-proxy' },
  { name: 'argocd-admin', url: platformUrl('argocd.admin'), segment: 'admin', flow: 'oauth2-proxy' },
  { name: 'hubble-admin', url: platformUrl('hubble.admin'), segment: 'admin', flow: 'oauth2-proxy', postLogin: 'hubble-namespace-argocd' },
  { name: 'kyverno-admin', url: platformUrl('kyverno.admin'), segment: 'admin', flow: 'none' },
]

const TARGETS: Target[] = [...BASE_TARGETS]

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
  // Headlamp uses its own OIDC client and typically opens Dex in a new tab/popup.
  TARGETS.push({ name: 'headlamp-admin', url: platformUrl('headlamp.admin'), segment: 'admin', flow: 'headlamp-oidc' })
}

function creds(segment: Segment) {
  const sharedPassword = process.env.PLATFORM_DEMO_PASSWORD || ''
  if (segment === 'dev') {
    return {
      login: process.env.DEX_DEV_LOGIN || 'demo@dev.test',
      password: process.env.DEX_DEV_PASSWORD || sharedPassword,
    }
  }
  if (segment === 'uat') {
    return {
      login: process.env.DEX_UAT_LOGIN || 'demo@uat.test',
      password: process.env.DEX_UAT_PASSWORD || sharedPassword,
    }
  }
  return {
    login: process.env.DEX_ADMIN_LOGIN || 'demo@admin.test',
    password: process.env.DEX_ADMIN_PASSWORD || sharedPassword,
  }
}

if (!creds('admin').password || !creds('dev').password || !creds('uat').password) {
  throw new Error('Set PLATFORM_DEMO_PASSWORD or the DEX_*_PASSWORD variables before running the SSO smoke tests')
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

async function maybeGrantDexAccess(page: Page) {
  // oauth2-proxy requests include `approval_prompt=force`, so Dex will show consent even if
  // skipApprovalScreen=true. Click through if present.
  const grant = page.getByRole('button', { name: /^grant access$/i })
  if (await grant.isVisible().catch(() => false)) {
    await grant.click()
  }
}

async function ensureOnTargetOrDex(page: Page, targetUrl: string) {
  const host = new URL(targetUrl).host
  await page.waitForURL((u) => u.host === host || u.host === DEX_HOST, { timeout: 60_000 })
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

async function loginViaOauth2ProxyRedirect(page: Page, target: Target) {
  const { login, password } = creds(target.segment)
  const targetHost = new URL(target.url).host

  await gotoWithGatewayRetry(page, target.url)
  await ensureOnTargetOrDex(page, target.url)

  // If we landed on the target host, we may already be authenticated.
  if (new URL(page.url()).host === targetHost) return

  await maybeClickOauth2ProxyProvider(page)
  await page.waitForURL(/dex\/auth/, { timeout: 60_000 })

  // Dex may choose /local/login directly when password DB is enabled.
  if (!page.url().includes('/dex/auth/local/login')) {
    await page.waitForURL(/dex\/auth\/local\/login/, { timeout: 60_000 })
  }

  await completeDexLocalLogin(page, login, password)
  await maybeGrantDexAccess(page)

  // After login we should come back to the target host.
  if (new URL(page.url()).host === targetHost) return
  await page.waitForURL((u) => u.host === targetHost, { timeout: 60_000 })
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
    await popup.waitForURL((u) => u.host === targetHost || u.host === DEX_HOST, { timeout: 60_000 })

    if (new URL(popup.url()).host !== targetHost) {
      await popup
        .waitForURL((u) => u.host === targetHost || (u.host === DEX_HOST && /dex\/auth\/local\/login/.test(u.pathname)), { timeout: 60_000 })
        .catch(() => undefined)
    }

    if (await popup.locator('#login').isVisible().catch(() => false)) {
      await completeDexLocalLogin(popup, login, password)
      await maybeGrantDexAccess(popup)
    }

    // Some flows close the popup, others redirect it back to Headlamp.
    await Promise.race([
      popup.waitForEvent('close').catch(() => undefined),
      popup.waitForURL(new RegExp(new URL(target.url).host.replaceAll('.', '\\\\.')), { timeout: 60_000 }).catch(() => undefined),
    ])
  } else {
    // If no popup, it might be a same-tab redirect to Dex.
    await page.waitForURL(/dex\/auth\/local\/login/, { timeout: 60_000 })
    await completeDexLocalLogin(page, login, password)
    await maybeGrantDexAccess(page)
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
  const errors: Array<{ attempt: number; body: string }> = []

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
      await expect(validation.locator('tr', { hasText: 'Valid' }).locator('td').nth(1)).toHaveText(/Yes/i)
      await expect(validation.locator('tr', { hasText: 'Address' }).locator('td').nth(1)).toHaveText(/10\.0\.0\.0\/24/i)

      const rfc1918 = results
        .locator('article')
        .filter({ has: page.getByRole('heading', { name: /^RFC1918 Private Address Check$/i }) })
      await expect(rfc1918).toBeVisible({ timeout: 60_000 })
      await expect(rfc1918.locator('tr', { hasText: 'Is RFC1918' }).locator('td').nth(1)).toHaveText(/Yes/i)

      const performanceTiming = results
        .locator('article')
        .filter({ has: page.getByRole('heading', { name: /^Performance Timing$/i }) })
      await expect(performanceTiming).toBeVisible({ timeout: 60_000 })
      await expect(performanceTiming.locator('tr', { hasText: 'Total Response Time' }).locator('td').nth(1)).toContainText(
        /\d+ms\s+\(\d+\.\d{3}s\)/i,
      )

      const apiCallDetails = performanceTiming.locator('details')
      await expect(apiCallDetails).toBeVisible({ timeout: 60_000 })
      await apiCallDetails.locator('summary').click()

      const expectedCalls = ['validate', 'checkPrivate', 'checkCloudflare', 'subnetInfo']
      for (const call of expectedCalls) {
        const row = apiCallDetails.locator('tbody tr').filter({ hasText: new RegExp(`^\\s*${escapeRegExp(call)}\\s*`, 'i') })
        await expect(row, `Missing subnetcalc API call row for ${call}`).toHaveCount(1, { timeout: 60_000 })
        await expect(row.locator('td').nth(1)).toContainText(/\d+ms/i)
        await expect(row.locator('td').nth(2)).not.toHaveText(/^$/)
        await expect(row.locator('td').nth(3)).not.toHaveText(/^$/)
      }

      return
    } catch {
      errors.push({
        attempt,
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

      if (t.flow === 'headlamp-oidc') {
        await loginHeadlampPopupFlow(page, t)
      } else if (t.flow === 'none') {
        await loadWithoutLogin(page, t)
      } else {
        await loginViaOauth2ProxyRedirect(page, t)
      }

      // If the upstream is broken, we want a hard failure (e.g. SigNoz 502 after login).
      await assertNoGatewayErrorWithReloads(page, t.name)

      if (VERIFY_APP_ACTIONS) {
        if (t.postLogin === 'sentiment-sample-positive') {
          await sentimentSamplePositiveAndAnalyze(page)
        }
        if (t.postLogin === 'subnetcalc-rfc1918-lookup') {
          await subnetcalcRfc1918Lookup(page)
        }
        if (t.postLogin === 'hubble-namespace-argocd') {
          await hubbleChooseNamespaceArgocd(page, t.url)
        }
        if (t.postLogin === 'grafana-launchpad') {
          await grafanaLaunchpadShowsHealthyTiles(page)
        }
        if (t.postLogin === 'signoz-logs-and-metrics') {
          await signozVerifyLogsAndMetrics(page, t.url)
        }
      }

      await attachLoggedInScreenshotIfEnabled(page, testInfo, t.name)

      // Common assertion: we should not be sitting on the Dex login form.
      await expect(page.locator('#login')).toHaveCount(0)
      const finalUrl = new URL(page.url())
      expect(finalUrl.host === DEX_HOST && /^\/dex\/auth\/local\/login(?:\/|$)/.test(finalUrl.pathname)).toBe(false)
    })
  }
})
