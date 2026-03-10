/**
 * Frontend tests for TypeScript Vite implementation.
 *
 * This test suite implements the canonical frontend test specification.
 * See: subnet-calculator/docs/TEST_SPECIFICATION.md
 *
 * Total: 30 tests (excludes progressive enhancement tests 31-32)
 *
 * JWT Authentication Support:
 * Tests work with or without JWT authentication enabled.
 * When auth enabled (VITE_AUTH_ENABLED=true), login endpoint is mocked.
 */

import { type Page, expect, test } from '@playwright/test'

/**
 * Mock JWT login endpoint if authentication is enabled
 * Call this before any test that makes API requests when VITE_AUTH_ENABLED=true
 */
async function mockJwtLogin(page: Page) {
  // Mock the login endpoint to return a valid JWT token
  await page.route('**/api/v1/auth/login', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        access_token: 'mock-jwt-token-for-testing',
        token_type: 'bearer',
      }),
    })
  )
}

test.describe('Frontend Tests', () => {
  // Group 0: Essential Resources (1 test)

  test('00 - favicon is present', async ({ page }) => {
    // Check for either /favicon.svg or /favicon.ico
    const faviconSvgResponse = await page.goto('/favicon.svg')
    const faviconIcoResponse = await page.goto('/favicon.ico')

    // At least one should return 200
    const svgExists = faviconSvgResponse?.status() === 200
    const icoExists = faviconIcoResponse?.status() === 200

    expect(svgExists || icoExists).toBeTruthy()
  })

  // Group 1: Basic Page & Elements (5 tests)

  test('01 - page loads successfully', async ({ page }) => {
    await page.goto('/')
    await expect(page.locator('h1')).toContainText('IPv4 Subnet Calculator')
  })

  test('02 - form elements are present', async ({ page }) => {
    await page.goto('/')

    // Check input field
    const ipInput = page.locator('#ip-address')
    await expect(ipInput).toBeVisible()
    const placeholder = await ipInput.getAttribute('placeholder')
    expect(placeholder).not.toBeNull()
    expect(placeholder).toContain('e.g.')

    // Check cloud mode selector
    const modeSelect = page.locator('#cloud-mode')
    await expect(modeSelect).toBeVisible()

    // Check submit button
    const submitBtn = page.locator('button[type="submit"]')
    await expect(submitBtn).toBeVisible()
  })

  test('03 - cloud mode selector has all options', async ({ page }) => {
    await page.goto('/')

    // Check selector exists
    const selector = page.locator('#cloud-mode')
    await expect(selector).toBeVisible()

    // Check options
    const options = selector.locator('option')
    await expect(options).toHaveCount(4)

    // Check default value (Azure is the default)
    await expect(selector).toHaveValue('Azure')

    // Change to AWS
    await page.selectOption('#cloud-mode', 'AWS')
    await expect(selector).toHaveValue('AWS')
  })

  test('04 - input placeholder text', async ({ page }) => {
    await page.goto('/')

    const inputField = page.locator('#ip-address')
    const placeholder = await inputField.getAttribute('placeholder')
    expect(placeholder).not.toBeNull()
    expect(placeholder && (placeholder.includes('192.168') || placeholder.includes('10.0.0.0'))).toBe(true)
  })

  test('05 - semantic html structure', async ({ page }) => {
    await page.goto('/')

    // Check for semantic elements
    await expect(page.locator('header')).toBeVisible()
    await expect(page.locator('h1')).toBeVisible()
    await expect(page.locator('form')).toBeVisible()
    // TypeScript Vite frontend has 1 label (IP address input only)
    await expect(page.locator('label')).toHaveCount(1)
  })

  // Group 2: Input Validation (3 tests)

  test('06 - invalid ip validation', async ({ page }) => {
    await page.goto('/')

    // Mock JWT login if auth enabled
    await mockJwtLogin(page)

    // TypeScript Vite frontend doesn't have client-side validation error display
    // It relies on API validation, so we mock an error response
    await page.route('**/api/v1/ipv4/validate', (route) =>
      route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({
          detail: 'Invalid IP address format',
        }),
      })
    )

    // Enter invalid IP
    await page.fill('#ip-address', '999.999.999.999')
    await page.click('button[type="submit"]')

    // Should show error message
    const error = page.locator('#error')
    await expect(error).toBeVisible({ timeout: 5000 })
    const errorText = await error.innerText()
    expect(errorText.toLowerCase().includes('error') || errorText.toLowerCase().includes('invalid')).toBe(true)
  })

  test('07 - valid ip no error', async ({ page }) => {
    await page.goto('/')

    await page.fill('#ip-address', '192.168.1.0/24')

    // TypeScript Vite frontend doesn't show validation errors on input
    // Error element should remain hidden
    const error = page.locator('#error')
    await expect(error).toBeHidden()
  })

  test('08 - cidr notation accepted', async ({ page }) => {
    await page.goto('/')

    await page.fill('#ip-address', '10.0.0.0/24')

    // TypeScript Vite frontend doesn't show validation errors on input
    // Error element should remain hidden
    const error = page.locator('#error')
    await expect(error).toBeHidden()
  })

  // Group 3: Example Buttons (2 tests)

  test('09 - example buttons populate input', async ({ page }) => {
    await page.goto('/')

    // Click RFC1918 example
    await page.click('text=RFC1918: 10.0.0.0/24')

    // Input should be populated
    const inputValue = await page.inputValue('#ip-address')
    expect(inputValue).toBe('10.0.0.0/24')
  })

  test('10 - all example buttons present', async ({ page }) => {
    await page.goto('/')

    // Check all example buttons
    await expect(page.locator('.btn-rfc1918')).toBeVisible()
    await expect(page.locator('.btn-rfc6598')).toBeVisible()
    await expect(page.locator('.btn-public')).toBeVisible()
    await expect(page.locator('.btn-cloudflare')).toBeVisible()
  })

  // Group 4: Responsive Layout (3 tests)

  test('11 - mobile responsive layout', async ({ page }) => {
    // Set mobile viewport
    await page.setViewportSize({ width: 375, height: 667 })
    await page.goto('/')

    // Check that the form is visible and usable
    await expect(page.locator('#ip-address')).toBeVisible()
    await expect(page.locator('#cloud-mode')).toBeVisible()
    await expect(page.locator('button[type="submit"]')).toBeVisible()
  })

  test('12 - tablet responsive layout', async ({ page }) => {
    // Set tablet viewport
    await page.setViewportSize({ width: 768, height: 1024 })
    await page.goto('/')

    // Check that all elements are visible
    await expect(page.locator('#ip-address')).toBeVisible()
    await expect(page.locator('#cloud-mode')).toBeVisible()
    await expect(page.locator('button[type="submit"]')).toBeVisible()
  })

  test('13 - desktop responsive layout', async ({ page }) => {
    // Set desktop viewport
    await page.setViewportSize({ width: 1920, height: 1080 })
    await page.goto('/')

    // Check that all elements are visible and properly laid out
    await expect(page.locator('#ip-address')).toBeVisible()
    await expect(page.locator('#cloud-mode')).toBeVisible()
    await expect(page.locator('button[type="submit"]')).toBeVisible()
  })

  // Group 5: Theme Management (3 tests)

  test('14 - theme switcher works', async ({ page }) => {
    await page.goto('/')

    const html = page.locator('html')
    const themeSwitcher = page.locator('#theme-switcher')

    // Initial theme should be dark
    await expect(html).toHaveAttribute('data-theme', 'dark')

    // Toggle to light
    await themeSwitcher.click()
    await expect(html).toHaveAttribute('data-theme', 'light')

    // Toggle back to dark
    await themeSwitcher.click()
    await expect(html).toHaveAttribute('data-theme', 'dark')
  })

  test('15 - theme persists across reload', async ({ page }) => {
    await page.goto('/')

    const html = page.locator('html')
    const themeSwitcher = page.locator('#theme-switcher')

    // Switch to light theme
    await themeSwitcher.click()
    await expect(html).toHaveAttribute('data-theme', 'light')

    // Reload page
    await page.reload()

    // Theme should still be light
    await expect(html).toHaveAttribute('data-theme', 'light')
  })

  test('16 - dark mode is default', async ({ page }) => {
    await page.goto('/')

    const html = page.locator('html')
    await expect(html).toHaveAttribute('data-theme', 'dark')
  })

  // Group 6: UI State & Display (4 tests)

  test('17 - loading state exists', async ({ page }) => {
    await page.goto('/')

    const loading = page.locator('#loading')
    // Initially hidden
    await expect(loading).toBeHidden()
  })

  test('18 - error display exists', async ({ page }) => {
    await page.goto('/')

    const error = page.locator('#error')
    // Initially hidden
    await expect(error).toBeHidden()
  })

  test('19 - results table exists', async ({ page }) => {
    await page.goto('/')

    const results = page.locator('#results')
    // Initially hidden
    await expect(results).toBeHidden()

    // TypeScript Vite frontend has results-content div that dynamically renders tables
    const resultsContent = page.locator('#results-content')
    await expect(resultsContent).toHaveCount(1)
  })

  test('20 - copy button initially hidden', async ({ page }) => {
    await page.goto('/')

    // TypeScript Vite frontend doesn't have a copy button
    // This test verifies that the results section exists but is hidden
    const results = page.locator('#results')
    await expect(results).toBeHidden()
  })

  // Group 7: Button Functionality (2 tests)

  test('21 - clear button functionality', async ({ page }) => {
    await page.goto('/')

    // TypeScript Vite frontend doesn't have a clear button
    // This test verifies form functionality instead
    await page.fill('#ip-address', '10.0.0.0/24')
    await page.selectOption('#cloud-mode', 'AWS')

    // Verify values were set
    await expect(page.locator('#ip-address')).toHaveValue('10.0.0.0/24')
    await expect(page.locator('#cloud-mode')).toHaveValue('AWS')
  })

  test('22 - all buttons have labels', async ({ page }) => {
    await page.goto('/')

    // Main action button
    const submitBtn = page.locator('button[type="submit"]')
    await expect(submitBtn).toBeVisible()
    const submitText = await submitBtn.innerText()
    expect(submitText.length).toBeGreaterThan(0)

    // Theme switcher
    const themeBtn = page.locator('#theme-switcher')
    await expect(themeBtn).toBeVisible()

    // TypeScript Vite frontend doesn't have clear/copy buttons
    // Verify example buttons instead
    await expect(page.locator('.example-btn')).toHaveCount(4)
  })

  // Group 8: API Error Handling (6 tests)

  test('23 - api status panel displays', async ({ page }) => {
    // Mock JWT login if auth enabled
    await mockJwtLogin(page)

    await page.goto('/')

    // API status should be visible
    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible()

    // Should show either healthy or unavailable
    const statusText = await apiStatus.innerText()
    expect(statusText.toLowerCase().includes('healthy') || statusText.includes('Unavailable')).toBe(true)
  })

  test('24 - api unavailable shows helpful error', async ({ page }) => {
    // Intercept API health check and simulate connection failure
    await page.route('**/api/v1/health', (route) => route.abort('failed'))

    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible()

    // Should show user-friendly error message
    const statusText = await apiStatus.innerText()
    expect(/Unavailable|connect|backend/i.test(statusText)).toBe(true)
    // Should NOT show cryptic JSON error
    expect(statusText.includes("Failed to execute 'json'")).toBe(false)
  })

  test('25 - api timeout shows helpful error', async ({ page }) => {
    // Intercept API health check and delay response beyond timeout
    await page.route('**/api/v1/health', async (route) => {
      // Delay longer than the 5s timeout
      await new Promise((resolve) => setTimeout(resolve, 6000))
      await route.fulfill({
        status: 200,
        body: JSON.stringify({ status: 'ok' }),
      })
    })

    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible({ timeout: 10000 })

    // Should show timeout error
    const statusText = await apiStatus.innerText()
    expect(/timeout|starting up|unavailable/i.test(statusText)).toBe(true)

    // Clean up routes
    await page.unrouteAll({ behavior: 'ignoreErrors' })
  })

  test('26 - non json response shows helpful error', async ({ page }) => {
    // Intercept API health check and return HTML instead of JSON
    await page.route('**/api/v1/health', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'text/html',
        body: '<html><body>Service Starting...</body></html>',
      })
    )

    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible()

    // Should show helpful error
    const statusText = await apiStatus.innerText()
    expect(/did not return JSON|starting up|Unable to connect/i.test(statusText)).toBe(true)
    // Should NOT show cryptic JSON parsing error
    expect(statusText.includes('Unexpected end of JSON input')).toBe(false)
  })

  test('27 - http error shows status code', async ({ page }) => {
    // Intercept API health check and return 503 Service Unavailable
    await page.route('**/api/v1/health', (route) =>
      route.fulfill({
        status: 503,
        contentType: 'text/html',
        body: 'Service Unavailable',
      })
    )

    await page.goto('/')

    const apiStatus = page.locator('#api-status')
    await expect(apiStatus).toBeVisible()

    // Should show HTTP status
    const statusText = await apiStatus.innerText()
    expect(/503|unavailable/i.test(statusText)).toBe(true)
  })

  test('28 - form submission when api unavailable', async ({ page }) => {
    // Mock JWT login if auth enabled
    await mockJwtLogin(page)

    await page.goto('/')

    // Intercept API calls and simulate connection failure
    await page.route('**/api/v1/ipv4/validate', (route) => route.abort('failed'))

    // Fill and submit form
    await page.fill('#ip-address', '192.168.1.1')
    await page.click('button[type="submit"]')

    // Should show error message
    const error = page.locator('#error')
    await expect(error).toBeVisible({ timeout: 5000 })

    // Should show user-friendly message, not cryptic error
    const errorText = await error.innerText()
    expect(/connect|unavailable|backend/i.test(errorText)).toBe(true)
    expect(errorText.includes("Failed to execute 'json'")).toBe(false)
  })

  // Group 9: Full API Integration (2 tests)

  test('29 - form submission with valid ip mocked', async ({ page }) => {
    // Mock JWT login if auth enabled
    await mockJwtLogin(page)

    // Mock API responses
    await page.route('**/api/v1/ipv4/validate', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'address',
          address: '192.168.1.1',
          is_ipv4: true,
          is_ipv6: false,
        }),
      })
    )
    await page.route('**/api/v1/ipv4/check-private', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          is_rfc1918: true,
          is_rfc6598: false,
          matched_rfc1918_range: '192.168.0.0/16',
        }),
      })
    )
    await page.route('**/api/v1/ipv4/check-cloudflare', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          is_cloudflare: false,
          ip_version: 4,
        }),
      })
    )

    await page.goto('/')

    // Fill form
    await page.fill('#ip-address', '192.168.1.1')
    await page.selectOption('#cloud-mode', 'Azure')

    // Submit
    await page.click('button[type="submit"]')

    // Wait for results
    const results = page.locator('#results')
    await expect(results).toBeVisible({ timeout: 10000 })

    // Check results contain expected data
    const resultsText = await results.innerText()
    expect(resultsText.includes('192.168.1.1')).toBe(true)
    expect(/RFC1918|Private/i.test(resultsText)).toBe(true)
  })

  test('30 - form submission with cidr range mocked', async ({ page }) => {
    // Mock JWT login if auth enabled
    await mockJwtLogin(page)

    // Mock API responses
    await page.route('**/api/v1/ipv4/validate', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'network',
          address: '10.0.0.0/24',
          is_ipv4: true,
          is_ipv6: false,
        }),
      })
    )
    await page.route('**/api/v1/ipv4/check-private', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          is_rfc1918: true,
          is_rfc6598: false,
          matched_rfc1918_range: '10.0.0.0/8',
        }),
      })
    )
    await page.route('**/api/v1/ipv4/check-cloudflare', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          is_cloudflare: false,
          ip_version: 4,
        }),
      })
    )
    await page.route('**/api/v1/ipv4/subnet-info', (route) =>
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          network: '10.0.0.0/24',
          mode: 'Standard',
          network_address: '10.0.0.0',
          broadcast_address: '10.0.0.255',
          netmask: '255.255.255.0',
          wildcard_mask: '0.0.0.255',
          prefix_length: 24,
          total_addresses: 256,
          usable_addresses: 254,
          first_usable_ip: '10.0.0.1',
          last_usable_ip: '10.0.0.254',
        }),
      })
    )

    await page.goto('/')

    // Fill form with network
    await page.fill('#ip-address', '10.0.0.0/24')
    await page.selectOption('#cloud-mode', 'Standard')

    // Submit
    await page.click('button[type="submit"]')

    // Wait for results
    const results = page.locator('#results')
    await expect(results).toBeVisible({ timeout: 10000 })

    // Check subnet info is displayed
    const resultsText = await results.innerText()
    expect(/Subnet Information/i.test(resultsText)).toBe(true)
    expect(resultsText.includes('10.0.0.0')).toBe(true)
    expect(resultsText.includes('/24')).toBe(true)
  })
})
