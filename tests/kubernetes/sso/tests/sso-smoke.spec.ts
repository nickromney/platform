import { expect, test } from '@playwright/test'
import {
  INCLUDE_MCP,
  INCLUDE_SUBNETCALC,
  OIDC_HOST,
  TARGETS,
  VERIFY_APP_ACTIONS,
  assertNoGatewayErrorWithReloads,
  attachLoggedInScreenshotIfEnabled,
  authChatModelReply,
  chatgptAddMcpOauthConnector,
  developerPortalWorks,
  expectLightweightAppAccessible,
  gotoWithGatewayRetry,
  grafanaBackstageObservabilityDashboardWorks,
  grafanaLaunchpadShowsHealthyTiles,
  grafanaMcpObservabilityDashboardWorks,
  grafanaPlatformNamespaceHealthDashboardWorks,
  grafanaVictoriaLogsDashboardWorks,
  hubbleChooseNamespaceArgocd,
  isLightweightPlatformApp,
  keycloakAdminConsoleWorks,
  loginToTarget,
  loginViaOauth2ProxyRedirect,
  mcpInspectorD2RenderAndExport,
  platformUrl,
  portalApiJsonWorks,
  sentimentSamplePositiveAndAnalyze,
  subnetcalcRfc1918Lookup,
  type Target,
  watchBrowserApiTraffic,
  watchPageRuntimeEvents,
} from '../lib/harness'

const SUITE_NAME = process.env.SSO_E2E_SUITE_NAME || 'platform SSO endpoints: smoke'

test.describe(SUITE_NAME, () => {
  test.describe.configure({ mode: 'serial' })

  for (const t of TARGETS) {
    test(`${t.name}: load and login`, async ({ page }, testInfo) => {
      test.setTimeout(180_000)
      const browserApiTraffic = t.postLogin === 'developer-portal' ? watchBrowserApiTraffic(page) : undefined
      const runtimeEvents = t.name === 'chatgpt-sim' ? watchPageRuntimeEvents(page) : undefined

      await loginToTarget(page, t)

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
        if (t.postLogin === 'auth-chat-model-reply') {
          await authChatModelReply(page)
        }
        if (t.postLogin === 'chatgpt-add-mcp-oauth') {
          await chatgptAddMcpOauthConnector(page, runtimeEvents)
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
        if (t.postLogin === 'grafana-platform-namespace-health') {
          await grafanaPlatformNamespaceHealthDashboardWorks(page)
        }
        if (t.postLogin === 'grafana-mcp-observability') {
          await grafanaMcpObservabilityDashboardWorks(page)
        }
        if (t.postLogin === 'grafana-backstage-observability') {
          await grafanaBackstageObservabilityDashboardWorks(page)
        }
        if (t.postLogin === 'keycloak-admin-console') {
          await keycloakAdminConsoleWorks(page)
        }
        if (t.postLogin === 'mcp-inspector-d2-render-export') {
          await mcpInspectorD2RenderAndExport(page)
        }
      }

      if (isLightweightPlatformApp(t)) {
        await expectLightweightAppAccessible(page, t)
      }

      await attachLoggedInScreenshotIfEnabled(page, testInfo, t.name)

      // Common assertion: we should not be sitting on the OIDC login form.
      await expect(page.locator('#login')).toHaveCount(0)
      await expect(page.locator('#username')).toHaveCount(0)
      const finalUrl = new URL(page.url())
      if (t.name !== 'keycloak') {
        expect(finalUrl.host === OIDC_HOST).toBe(false)
      }
    })
  }

  test('subnetcalc-dev: sign out clears Keycloak SSO session used by chatgpt-dev', async ({ page }) => {
    test.setTimeout(180_000)
    test.skip(!INCLUDE_SUBNETCALC || !INCLUDE_MCP, 'requires chatgpt-sim and subnetcalc dev apps')

    const chatgptTarget: Target = {
      name: 'chatgpt-sim',
      url: platformUrl('chatgpt.dev'),
      segment: 'dev',
      flow: 'oauth2-proxy',
    }
    const subnetcalcTarget: Target = {
      name: 'subnetcalc-dev',
      url: platformUrl('subnetcalc.dev'),
      segment: 'dev',
      flow: 'oauth2-proxy',
    }

    await loginViaOauth2ProxyRedirect(page, chatgptTarget)
    await assertNoGatewayErrorWithReloads(page, chatgptTarget.name)

    await gotoWithGatewayRetry(page, subnetcalcTarget.url)
    await page.waitForURL((u) => u.host === new URL(subnetcalcTarget.url).host, { timeout: 60_000 })
    await expect(page.getByRole('button', { name: /^sign out$/i })).toBeVisible({ timeout: 30_000 })
    const subnetcalcHost = new URL(subnetcalcTarget.url).host
    await Promise.all([
      page.waitForURL((u) => {
        if (u.host === subnetcalcHost && u.pathname === '/signed-out.html') {
          return true
        }
        return u.host === OIDC_HOST && (u.searchParams.get('state') || '').endsWith(':/signed-out.html')
      }, { timeout: 60_000, waitUntil: 'domcontentloaded' }),
      page.getByRole('button', { name: /^sign out$/i }).click(),
    ])
    if (new URL(page.url()).host === subnetcalcHost) {
      await expect(page.getByRole('heading', { name: /^signed out$/i })).toBeVisible()
    }

    await gotoWithGatewayRetry(page, subnetcalcTarget.url)
    await page.waitForURL((u) => u.host === OIDC_HOST, { timeout: 60_000 })
    await expect(page.locator('#username')).toBeVisible({ timeout: 30_000 })
  })

  test('chatgpt-dev: sign out clears Keycloak SSO session used by subnetcalc-dev', async ({ page }) => {
    test.setTimeout(180_000)
    test.skip(!INCLUDE_SUBNETCALC || !INCLUDE_MCP, 'requires chatgpt-sim and subnetcalc dev apps')

    const chatgptTarget: Target = {
      name: 'chatgpt-sim',
      url: platformUrl('chatgpt.dev'),
      segment: 'dev',
      flow: 'oauth2-proxy',
    }
    const subnetcalcTarget: Target = {
      name: 'subnetcalc-dev',
      url: platformUrl('subnetcalc.dev'),
      segment: 'dev',
      flow: 'oauth2-proxy',
    }

    await loginViaOauth2ProxyRedirect(page, subnetcalcTarget)
    await assertNoGatewayErrorWithReloads(page, subnetcalcTarget.name)

    await gotoWithGatewayRetry(page, chatgptTarget.url)
    await page.waitForURL((u) => u.host === new URL(chatgptTarget.url).host, { timeout: 60_000 })
    await expect(page.getByRole('button', { name: /^sign out$/i })).toBeVisible({ timeout: 30_000 })
    const chatgptHost = new URL(chatgptTarget.url).host
    await Promise.all([
      page.waitForURL((u) => {
        if (u.host === chatgptHost && u.pathname === '/signed-out.html') {
          return true
        }
        return u.host === OIDC_HOST && (u.searchParams.get('state') || '').endsWith(':/signed-out.html')
      }, { timeout: 60_000, waitUntil: 'domcontentloaded' }),
      page.getByRole('button', { name: /^sign out$/i }).click(),
    ])
    if (new URL(page.url()).host === chatgptHost) {
      await expect(page.getByRole('heading', { name: /^signed out$/i })).toBeVisible()
    }

    await gotoWithGatewayRetry(page, chatgptTarget.url)
    await page.waitForURL((u) => u.host === OIDC_HOST, { timeout: 60_000 })
    await expect(page.locator('#username')).toBeVisible({ timeout: 30_000 })
  })
})
