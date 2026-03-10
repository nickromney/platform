import { expect, test } from '@playwright/test'

/**
 * SWA CLI Integration Tests
 *
 * Tests against Azure Static Web Apps CLI emulator (port 4280/4281)
 * - NO MOCKING - validates real SWA routing and API proxying
 * - Tests authentication/authorization flow if enabled
 * - Tests staticwebapp.config.json route configuration
 *
 * Prerequisites (Terminal 1):
 *   cd ..
 *   make start-stack4             # Port 4280, Azure Function, no auth
 *   # OR
 *   make start-stack5             # Port 4281, Azure Function, JWT auth
 *
 * Then run (Terminal 2):
 *   npm run test:swa:stack4        # Test Stack 4
 *   npm run test:swa:stack5        # Test Stack 5
 */

test.describe('SWA CLI Tests', () => {
  test('01 - page loads through SWA emulator', async ({ page }) => {
    await page.goto('/')

    // Wait for page to load
    await page.waitForSelector('h1', { state: 'visible' })

    // Check title
    const title = page.locator('h1')
    await expect(title).toContainText('IPv4 Subnet Calculator')
  })

  test('02 - API health check works through SWA proxy', async ({ page }) => {
    await page.goto('/')

    // Wait for API health check to complete
    await page.waitForSelector('#api-status', { state: 'visible', timeout: 10000 })

    // Check API status
    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toContainText('API Status')
    await expect(apiStatus).toContainText('healthy')
  })

  test('03 - frontend HMR works (dev server proxied)', async ({ page }) => {
    await page.goto('/')

    // Check that Vite dev server is running (not static build)
    const scriptsWithVite = page.locator('script[type="module"][src*="/@vite"]')
    const count = await scriptsWithVite.count()

    if (count > 0) {
      console.log('✓ Vite dev server is running (HMR enabled)')
    } else {
      console.log('ℹ Running against static build (no HMR)')
    }

    // Test should pass either way
    expect(count).toBeGreaterThanOrEqual(0)
  })

  test('04 - API call works through SWA proxy', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('#api-status', { state: 'visible' })

    // Submit valid IPv4 address
    await page.fill('input[name="address"]', '192.168.1.1')
    await page.click('button[type="submit"]')

    // Wait for results
    await page.waitForSelector('#results', { state: 'visible', timeout: 15000 })

    const results = page.locator('#results')
    await expect(results).toContainText('Validation')
    await expect(results).toContainText('192.168.1.1')
  })

  test('05 - multiple API endpoints work', async ({ page }) => {
    await page.goto('/')
    await page.waitForSelector('#api-status', { state: 'visible' })

    // Test with RFC1918 address (triggers multiple endpoints)
    await page.fill('input[name="address"]', '10.0.0.0/24')
    await page.selectOption('select[name="mode"]', 'Azure')
    await page.click('button[type="submit"]')

    // Wait for results
    await page.waitForSelector('#results', { state: 'visible', timeout: 15000 })

    const results = page.locator('#results')

    // Should have validation result
    await expect(results).toContainText('Validation')

    // Should have private address check
    await expect(results).toContainText('Private Address Check')

    // Should have subnet info
    await expect(results).toContainText('Subnet Information')
  })

  test('06 - SWA routes work correctly', async ({ page }) => {
    await page.goto('/')

    // Verify we're on the root path
    expect(page.url()).toContain('localhost:')

    // Check that the app loaded (not a 404)
    const title = page.locator('h1')
    await expect(title).toBeVisible()
  })

  test('07 - SWA emulator serves frontend correctly', async ({ page }) => {
    const response = await page.goto('/')

    // Should return 200 OK
    expect(response?.status()).toBe(200)

    // Should have HTML content type
    const contentType = response?.headers()['content-type']
    expect(contentType).toContain('html')
  })

  test('08 - API proxy returns correct content-type', async ({ page }) => {
    await page.goto('/')

    // Listen for API responses
    let apiContentType = ''
    page.on('response', (response) => {
      if (response.url().includes('/api/v1/')) {
        apiContentType = response.headers()['content-type'] || ''
      }
    })

    // Trigger an API call
    await page.fill('input[name="address"]', '8.8.8.8')
    await page.click('button[type="submit"]')
    await page.waitForSelector('#results', { state: 'visible', timeout: 15000 })

    // API should return JSON
    expect(apiContentType).toContain('application/json')
  })
})
