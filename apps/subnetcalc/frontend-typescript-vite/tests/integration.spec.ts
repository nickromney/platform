import { expect, test } from '@playwright/test'

/**
 * Integration Tests - Real Container Stack
 *
 * These tests run against REAL containerized backends:
 * - Stack 5: TypeScript + Azure Function (JWT auth) - http://localhost:3001
 * - Stack 4: TypeScript + Container App (no auth) - http://localhost:3000
 *
 * NO MOCKING - validates actual JWT authentication and API responses
 *
 * Prerequisites:
 *   podman-compose up api-fastapi-azure-function frontend-typescript-vite-jwt
 *   OR
 *   podman-compose up api-fastapi-container-app frontend-typescript-vite
 */

test.describe('Integration Tests - Real API', () => {
  test('01 - page loads and connects to real API', async ({ page }) => {
    await page.goto('/')

    // Wait for API health check to complete
    await page.waitForSelector('#api-status', { state: 'visible', timeout: 10000 })

    // Check API status shows healthy
    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toContainText('API Status')
    await expect(apiStatus).toContainText('healthy')

    // Verify backend service name appears
    const apiStatusText = await apiStatus.textContent()
    expect(apiStatusText).toMatch(/Subnet Calculator API/)
  })

  test('02 - JWT authentication works (if enabled)', async ({ page }) => {
    // Listen for all network requests
    const requests: { url: string; method: string; status: number }[] = []

    page.on('response', (response) => {
      requests.push({
        url: response.url(),
        method: response.request().method(),
        status: response.status(),
      })
    })

    await page.goto('/')

    // Wait for API health check
    await page.waitForSelector('#api-status', { state: 'visible', timeout: 10000 })

    // Check if JWT login occurred (only for Stack 5)
    const loginRequests = requests.filter((r) => r.url.includes('/auth/login'))

    if (loginRequests.length > 0) {
      // JWT auth is enabled - verify login succeeded
      const successfulLogin = loginRequests.find((r) => r.status === 200)
      expect(successfulLogin).toBeDefined()
      console.log('✓ JWT authentication successful')
    } else {
      // No JWT auth (Stack 4)
      console.log('✓ No JWT authentication (Stack 4 - no auth mode)')
    }
  })

  test('03 - real IPv4 validation via API', async ({ page }) => {
    await page.goto('/')

    // Wait for page to be ready
    await page.waitForSelector('#api-status', { state: 'visible' })

    // Enter a valid IPv4 address
    await page.fill('input[name="address"]', '192.168.1.1')
    await page.selectOption('select[name="mode"]', 'Azure')

    // Submit form
    await page.click('button[type="submit"]')

    // Wait for real API response
    await page.waitForSelector('#results', { state: 'visible', timeout: 15000 })

    // Verify results from real API
    const results = page.locator('#results')
    await expect(results).toContainText('Validation')
    await expect(results).toContainText('192.168.1.1')
    await expect(results).toContainText('✓ Yes') // Valid
  })

  test('04 - real RFC1918 private check via API', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('#api-status', { state: 'visible' })

    // Submit RFC1918 private address
    await page.fill('input[name="address"]', '10.0.0.1')
    await page.click('button[type="submit"]')

    // Wait for results
    await page.waitForSelector('#results', { state: 'visible', timeout: 15000 })

    const results = page.locator('#results')
    await expect(results).toContainText('Private Address Check')
    await expect(results).toContainText('RFC1918') // Should show RFC1918 match
  })

  test('05 - real subnet calculation via API', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('#api-status', { state: 'visible' })

    // Submit CIDR network
    await page.fill('input[name="address"]', '10.0.0.0/24')
    await page.selectOption('select[name="mode"]', 'Azure')
    await page.click('button[type="submit"]')

    // Wait for results
    await page.waitForSelector('#results', { state: 'visible', timeout: 15000 })

    const results = page.locator('#results')
    await expect(results).toContainText('Subnet Information')
    await expect(results).toContainText('Azure Mode')
    await expect(results).toContainText('10.0.0.0/24')
    await expect(results).toContainText('Usable Addresses')
  })

  test('06 - real Cloudflare check via API', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('#api-status', { state: 'visible' })

    // Submit Cloudflare IP
    await page.fill('input[name="address"]', '104.16.1.1')
    await page.click('button[type="submit"]')

    // Wait for results
    await page.waitForSelector('#results', { state: 'visible', timeout: 15000 })

    const results = page.locator('#results')
    await expect(results).toContainText('Cloudflare Check')
    await expect(results).toContainText('✓ Yes') // Is Cloudflare
  })

  test('07 - multiple API calls with cached JWT token', async ({ page }) => {
    const apiCalls: { url: string; method: string }[] = []

    page.on('request', (request) => {
      const url = request.url()
      if (url.includes('/api/v1/')) {
        apiCalls.push({
          url,
          method: request.method(),
        })
      }
    })

    await page.goto('/')
    await page.waitForSelector('#api-status', { state: 'visible' })

    // First calculation
    await page.fill('input[name="address"]', '192.168.1.0/24')
    await page.click('button[type="submit"]')
    await page.waitForSelector('#results', { state: 'visible' })

    // Second calculation (should reuse JWT token if auth enabled)
    await page.fill('input[name="address"]', '10.0.0.0/16')
    await page.click('button[type="submit"]')
    await page.waitForSelector('#results', { state: 'visible' })

    // Count login calls - should be 0 or 1 (not 2)
    const loginCalls = apiCalls.filter((c) => c.url.includes('/auth/login'))
    expect(loginCalls.length).toBeLessThanOrEqual(1)

    if (loginCalls.length === 1) {
      console.log('✓ JWT token cached and reused')
    }
  })

  test('08 - network tab shows real Authorization headers (Stack 5 only)', async ({ page }) => {
    const authHeaders: string[] = []

    page.on('request', (request) => {
      const url = request.url()
      const authHeader = request.headers().authorization

      if (url.includes('/api/v1/') && authHeader) {
        authHeaders.push(authHeader)
      }
    })

    await page.goto('/')
    await page.waitForSelector('#api-status', { state: 'visible' })

    // Make an API call
    await page.fill('input[name="address"]', '192.168.1.1')
    await page.click('button[type="submit"]')
    await page.waitForSelector('#results', { state: 'visible' })

    // Check if Authorization headers were sent (Stack 5 with JWT)
    if (authHeaders.length > 0) {
      // Verify Bearer token format
      expect(authHeaders[0]).toMatch(/^Bearer /)
      console.log('✓ Authorization headers sent with Bearer token')
    } else {
      console.log('✓ No Authorization headers (Stack 4 - no auth mode)')
    }
  })
})
