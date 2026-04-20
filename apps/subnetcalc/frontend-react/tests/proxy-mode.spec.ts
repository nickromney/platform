import { expect, test } from '@playwright/test'

test.describe('Proxy runtime configuration', () => {
  test('forces relative API calls when API_PROXY_ENABLED is true', async ({ page }) => {
    const interceptedRequests: string[] = []

    await page.addInitScript((runtimeConfig) => {
      window.RUNTIME_CONFIG = runtimeConfig
    }, {
      API_PROXY_ENABLED: 'true',
      API_BASE_URL: 'https://should-not-be-called.test',
      AUTH_METHOD: 'none',
    })

    page.on('request', (request) => {
      const url = request.url()
      if (request.resourceType() === 'fetch' && url.includes('/api/v1/')) {
        interceptedRequests.push(url)
      }
    })

    await page.route('**/api/v1/health', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ status: 'ok', service: 'proxy-mode', version: 'test' }),
      })
    })

    await page.goto('/')
    await page.waitForRequest(
      (request) => request.resourceType() === 'fetch' && request.url().includes('/api/v1/'),
      { timeout: 5000 }
    )

    expect(interceptedRequests.length).toBeGreaterThan(0)
    interceptedRequests.forEach((url) => {
      expect(new URL(url).pathname.startsWith('/api/')).toBeTruthy()
      expect(url.includes('should-not-be-called.test')).toBeFalsy()
    })
  })

  test('preserves empty runtime API_BASE_URL for same-origin API calls', async ({ page }) => {
    const interceptedRequests: string[] = []

    await page.addInitScript((runtimeConfig) => {
      window.RUNTIME_CONFIG = runtimeConfig
    }, {
      API_PROXY_ENABLED: 'false',
      API_BASE_URL: '',
      AUTH_METHOD: 'none',
    })

    page.on('request', (request) => {
      const url = request.url()
      if (request.resourceType() === 'fetch' && url.includes('/api/v1/')) {
        interceptedRequests.push(url)
      }
    })

    await page.route('**/api/v1/health', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ status: 'ok', service: 'same-origin', version: 'test' }),
      })
    })

    await page.goto('/')
    await page.waitForRequest(
      (request) => request.resourceType() === 'fetch' && request.url().includes('/api/v1/health'),
      { timeout: 5000 }
    )

    const expectedOrigin = new URL(page.url()).origin
    expect(interceptedRequests.length).toBeGreaterThan(0)
    interceptedRequests.forEach((url) => {
      const parsed = new URL(url)
      expect(parsed.origin).toBe(expectedOrigin)
      expect(url.includes('localhost:7071')).toBeFalsy()
    })
  })
})
