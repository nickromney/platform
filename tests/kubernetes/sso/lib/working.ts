import { expect, type Page } from '@playwright/test'
import {
  HUBBLE_EMPTY_SERVICE_MAP,
  INCLUDE_SENTIMENT,
  INCLUDE_UAT_APPS,
  INCLUDE_VICTORIA_LOGS,
  TARGETS,
  VERIFY_AUTH_CHAT_MODEL,
  authChatModelReply,
  bodyText,
  chatgptAddMcpOauthConnector,
  completeOidcLogin,
  creds,
  developerPortalWorks,
  fetchHeadlampStatus,
  gotoWithGatewayRetry,
  grafanaBackstageObservabilityDashboardWorks,
  grafanaLaunchpadShowsHealthyTiles,
  grafanaMcpObservabilityDashboardWorks,
  grafanaPlatformNamespaceHealthDashboardWorks,
  grafanaVictoriaLogsDashboardWorks,
  hubbleSelectNamespace,
  hubbleServiceMapHasRenderableData,
  isOauth2ProxyForbiddenPage,
  keycloakAdminConsoleWorks,
  mcpInspectorD2RenderAndExport,
  OIDC_HOST,
  platformUrl,
  portalApiJsonWorks,
  sentimentSamplePositiveAndAnalyze,
  subnetcalcRfc1918Lookup,
  type Target,
  watchBrowserApiTraffic,
  watchPageRuntimeEvents,
} from './harness'

export type WorkingFn = (page: Page, target: Target) => Promise<void>

async function metricValue(page: Page, selector: string) {
  const raw = ((await page.locator(selector).textContent()) ?? '').replace(/,/g, '').trim()
  const parsed = Number.parseInt(raw, 10)
  return Number.isFinite(parsed) ? parsed : -1
}

async function giteaExploreHasRepositories(page: Page, target: Target) {
  await gotoWithGatewayRetry(page, new URL('/explore/repos', target.url).toString())
  await expect(page.locator('body')).toContainText(/explore|repositories|repository/i, { timeout: 60_000 })
  const repoLinks = page.locator('a[href*="/platform/"], a[href*="/explore/repos"], .repo-list a, .flex-item-title a')
  await expect
    .poll(async () => repoLinks.count(), {
      message: 'Gitea explore page did not list any repositories',
      timeout: 60_000,
    })
    .toBeGreaterThan(0)
}

async function argocdApplicationsHaveItems(page: Page, target: Target) {
  await gotoWithGatewayRetry(page, new URL('/applications', target.url).toString())
  const body = page.locator('body')
  await expect(body).toContainText(/applications/i, { timeout: 90_000 })
  await expect(body).not.toContainText(/failed to load|unable to load applications/i)
  await expect
    .poll(async () => bodyText(page), {
      message: 'Argo CD applications page did not show a known synced app',
      timeout: 90_000,
    })
    .toMatch(/cilium|gitea|argocd|platform-gateway|oauth2-proxy|headlamp/i)
}

async function kyvernoPolicyReporterHasPolicies(page: Page) {
  const body = page.locator('body')
  await expect(body).toContainText(/policy reporter|policies|clusterpolic/i, { timeout: 90_000 })
  await expect(body).not.toContainText(/failed to fetch|no connection/i)
  await expect
    .poll(async () => bodyText(page), {
      message: 'Policy Reporter did not show any policy results or counts',
      timeout: 90_000,
    })
    .toMatch(/[1-9]\d*|pass|fail|warn|policy/i)
}

async function apimSimulatorHasGatewaySurface(page: Page) {
  await expect(page.getByRole('heading', { name: /APIM Simulator/i })).toBeVisible({ timeout: 60_000 })
  const connect = page.getByRole('button', { name: /^connect$/i })
  if (await connect.isVisible().catch(() => false)) {
    await connect.click()
  }
  await expect
    .poll(
      async () => {
        const apis = await metricValue(page, '#metric-apis')
        const routes = await metricValue(page, '#metric-routes')
        const products = await metricValue(page, '#metric-products')
        return Math.max(apis, routes, products)
      },
      { message: 'APIM simulator connected but still shows zero APIs, routes, and products', timeout: 60_000 },
    )
    .toBeGreaterThan(0)
  await expect(page.locator('#routes li, #subscriptions li')).not.toHaveCount(0)
}

async function grafanaHomeHasDashboards(page: Page, target: Target) {
  const search = await page.evaluate(async () => {
    const response = await fetch('/api/search?type=dash-db&limit=50', { credentials: 'include' })
    return { status: response.status, body: await response.text() }
  })
  expect(search.status, search.body).toBe(200)
  const payload = JSON.parse(search.body) as Array<{ title?: string; uid?: string }>
  expect(payload.length, search.body).toBeGreaterThan(0)
  expect(payload.some((item) => (item.uid || item.title || '').toLowerCase().includes('platform-launchpad')), search.body).toBe(true)
  if (INCLUDE_VICTORIA_LOGS) {
    await grafanaVictoriaLogsDashboardWorks(page, target.url)
  }
}

async function headlampShowsClusterNamespaces(page: Page, target: Target) {
  const targetHost = new URL(target.url).host
  await gotoWithGatewayRetry(page, new URL('/c/main/namespaces', target.url).toString())
  const namespacesStatus = await fetchHeadlampStatus(page, '/clusters/main/api/v1/namespaces')
  expect(namespacesStatus, 'Headlamp namespace list API did not return 200').toBe(200)
  const podsStatus = await fetchHeadlampStatus(page, '/clusters/main/api/v1/namespaces/uat/pods')
  expect(podsStatus, 'Headlamp could not list pods in uat').toBe(200)
  await expect(page.locator('body')).not.toContainText(/you don't have permissions to view this resource/i)
  expect(new URL(page.url()).host).toBe(targetHost)
}

async function authChatShellWorks(page: Page) {
  await expect(page.getByRole('heading', { name: /^Auth Chat$/i })).toBeVisible({ timeout: 60_000 })
  await expect(page.locator('#conversation-status')).toContainText(/ready/i, { timeout: 60_000 })
  await expect(page.locator('#message')).toBeVisible()
  await expect(page.locator('#auth-user')).not.toHaveText(/loading/i, { timeout: 60_000 })
  if (VERIFY_AUTH_CHAT_MODEL) {
    await authChatModelReply(page)
  }
}

async function generateUatWorkloadTraffic(page: Page) {
  const sentiment = {
    name: 'sentiment-uat',
    url: platformUrl('sentiment.uat'),
    segment: 'uat' as const,
    flow: 'oauth2-proxy' as const,
  }
  await gotoWithGatewayRetry(page, sentiment.url)
  if (page.url().includes('/oauth2/sign_in')) {
    const btn = page.getByRole('button', { name: /sign in with openid connect/i })
    if (await btn.isVisible().catch(() => false)) {
      await btn.click()
    }
  }
  if (new URL(page.url()).host === OIDC_HOST || (await page.locator('#username').isVisible().catch(() => false))) {
    const user = creds('admin')
    await completeOidcLogin(page, user.login, user.password)
    await page.waitForURL((u) => u.host === new URL(sentiment.url).host, { timeout: 60_000 })
  }
  expect(await isOauth2ProxyForbiddenPage(page), `Could not open Sentiment UAT to generate Hubble traffic; url=${page.url()}`).toBe(false)
  await page.reload({ waitUntil: 'domcontentloaded' }).catch(() => undefined)
}

export async function hubbleUatServiceMapWorks(page: Page, target: Target) {
  await hubbleSelectNamespace(page, target.url, 'uat')
  const trafficPage = await page.context().newPage()
  try {
    await expect
      .poll(
        async () => {
          if (INCLUDE_SENTIMENT && INCLUDE_UAT_APPS) {
            await generateUatWorkloadTraffic(trafficPage)
          }
          if (await hubbleServiceMapHasRenderableData(page)) return 'map'
          const text = await bodyText(page)
          return HUBBLE_EMPTY_SERVICE_MAP.test(text) ? 'empty' : 'pending'
        },
        {
          message:
            'Hubble UI for namespace=uat still has no service map. Cilium Gateway traffic is reserved:host and hidden; in-namespace router/API hops should still appear after Sentiment UAT is loaded.',
          timeout: 120_000,
        },
      )
      .toBe('map')
  } finally {
    await trafficPage.close().catch(() => undefined)
  }
  await expect(page.locator('body')).not.toContainText(HUBBLE_EMPTY_SERVICE_MAP)
}

const WORKING_BY_NAME: Record<string, WorkingFn> = {
  'subnetcalc-uat': subnetcalcRfc1918Lookup,
  'sentiment-uat': sentimentSamplePositiveAndAnalyze,
  'sentiment-dev': sentimentSamplePositiveAndAnalyze,
  'subnetcalc-dev': subnetcalcRfc1918Lookup,
  keycloak: async (page) => keycloakAdminConsoleWorks(page),
  'gitea-admin': giteaExploreHasRepositories,
  'grafana-admin': grafanaHomeHasDashboards,
  'grafana-launchpad': async (page) => grafanaLaunchpadShowsHealthyTiles(page),
  'argocd-admin': argocdApplicationsHaveItems,
  'hubble-admin': hubbleUatServiceMapWorks,
  'kyverno-admin': async (page) => kyvernoPolicyReporterHasPolicies(page),
  'apim-admin': async (page) => apimSimulatorHasGatewaySurface(page),
  'developer-portal-api': async (page) => portalApiJsonWorks(page),
  'developer-portal': async (page) => developerPortalWorks(page, watchBrowserApiTraffic(page)),
  'auth-chat': async (page) => authChatShellWorks(page),
  'chatgpt-sim': async (page) => chatgptAddMcpOauthConnector(page, watchPageRuntimeEvents(page)),
  'mcp-console': async (page) => mcpInspectorD2RenderAndExport(page),
  'grafana-platform-namespace-health': async (page) => grafanaPlatformNamespaceHealthDashboardWorks(page),
  'grafana-mcp-observability': async (page) => grafanaMcpObservabilityDashboardWorks(page),
  'grafana-backstage-observability': async (page) => grafanaBackstageObservabilityDashboardWorks(page),
  'headlamp-admin': headlampShowsClusterNamespaces,
}

export function missingWorkingContracts(targets = TARGETS) {
  return targets.filter((target) => !WORKING_BY_NAME[target.name]).map((target) => target.name)
}

export function workingAssertion(target: Target): WorkingFn {
  const fn = WORKING_BY_NAME[target.name]
  if (!fn) {
    throw new Error(`SSO working suite has no contract for ${target.name}`)
  }
  return fn
}
