import { expect, test } from '@playwright/test'

test.describe('Proxy runtime configuration', () => {
  test('forces relative API calls when API_PROXY_ENABLED is true', async ({ page }) => {
    const interceptedRequests: string[] = []

    await page.addInitScript((runtimeConfig) => {
      window.RUNTIME_CONFIG = runtimeConfig
    }, {
      API_PROXY_ENABLED: 'true',
      API_BASE_URL: 'https://should-not-be-called.test',
      AUTH_METHOD: 'easyauth',
    })

    page.on('request', (request) => {
      const url = request.url()
      if (url.includes('/api/')) {
        interceptedRequests.push(url)
      }
    })

    await page.route('**/api/v1/health', (route) => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({ status: 'ok' }),
      })
    })

    await page.goto('/')
    await page.waitForRequest((request) => request.url().includes('/api/'), { timeout: 5000 })

    expect(interceptedRequests.length).toBeGreaterThan(0)
    interceptedRequests.forEach((url) => {
      expect(url.startsWith('http://localhost:5173/api/')).toBeTruthy()
      expect(url.includes('should-not-be-called.test')).toBeFalsy()
    })
  })
})
