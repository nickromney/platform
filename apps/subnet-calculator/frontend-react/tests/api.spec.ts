/**
 * API Integration tests
 * Tests interaction with the backend API
 */

import { test, expect } from '@playwright/test'

test.describe('API Integration', () => {
  test('displays API health status on page load', async ({ page }) => {
    await page.goto('/')

    // Should check API health and display status
    const statusIndicator = page.locator('[data-testid="api-status"]').or(
      page.getByText(/API.*Connected|Backend.*Available|API.*Healthy/i)
    )

    await expect(statusIndicator.first()).toBeVisible({ timeout: 10000 })
  })

  test('handles API unavailable gracefully', async ({ page }) => {
    // Mock API to return errors
    await page.route('**/api/v1/**', route => route.abort())

    await page.goto('/')

    // Should show that API is unavailable
    await expect(page.getByText(/unavailable|offline|unable to connect/i)).toBeVisible({
      timeout: 10000
    })
  })

  test('handles API timeout gracefully', async ({ page }) => {
    // Mock API with long delay
    await page.route('**/api/v1/**', async route => {
      await new Promise(resolve => setTimeout(resolve, 20000))
      await route.continue()
    })

    await page.goto('/')

    // Should show timeout error
    await expect(page.getByText(/timeout|timed out/i)).toBeVisible({ timeout: 15000 })
  })

  test('handles non-JSON API response', async ({ page }) => {
    // Mock API to return HTML instead of JSON
    await page.route('**/api/v1/**', route => {
      route.fulfill({
        status: 200,
        contentType: 'text/html',
        body: '<html><body>Not JSON</body></html>',
      })
    })

    await page.goto('/')

    // Should show helpful error about API not returning JSON
    await expect(page.getByText(/JSON|starting up|error state/i)).toBeVisible({ timeout: 10000 })
  })

  test('handles HTTP error codes', async ({ page }) => {
    await page.goto('/')

    // Mock validation endpoint to return 400
    await page.route('**/api/v1/**/validate', route => {
      route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({ detail: 'Invalid IP address format' }),
      })
    })

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('999.999.999.999')

    const submitButton = page.getByRole('button', { name: /lookup|calculate/i })
    await submitButton.click()

    // Should show the error message
    await expect(page.getByText(/invalid.*format|400/i)).toBeVisible({ timeout: 5000 })
  })

  test('successful IPv4 lookup displays results', async ({ page }) => {
    await page.goto('/')

    // Mock successful validation response
    await page.route('**/api/v1/ipv4/validate', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'address',
          address: '8.8.8.8',
          is_ipv4: true,
          is_ipv6: false,
        }),
      })
    })

    // Mock other endpoints
    await page.route('**/api/v1/ipv4/check-private', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '8.8.8.8',
          is_rfc1918: false,
          is_rfc6598: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-cloudflare', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '8.8.8.8',
          is_cloudflare: false,
          ip_version: 4,
        }),
      })
    })

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('8.8.8.8')

    const submitButton = page.getByRole('button', { name: /lookup|calculate/i })
    await submitButton.click()

    // Should display results
    await expect(page.getByText(/8\.8\.8\.8/)).toBeVisible({ timeout: 5000 })
    await expect(page.getByText(/valid/i)).toBeVisible({ timeout: 5000 })
  })

  test('successful IPv6 lookup uses correct endpoint', async ({ page }) => {
    await page.goto('/')

    let ipv6EndpointCalled = false

    // Mock IPv6 validation endpoint
    await page.route('**/api/v1/ipv6/validate', route => {
      ipv6EndpointCalled = true
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'address',
          address: '2001:4860:4860::8888',
          is_ipv4: false,
          is_ipv6: true,
        }),
      })
    })

    await page.route('**/api/v1/ipv6/check-cloudflare', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '2001:4860:4860::8888',
          is_cloudflare: false,
          ip_version: 6,
        }),
      })
    })

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('2001:4860:4860::8888')

    const submitButton = page.getByRole('button', { name: /lookup|calculate/i })
    await submitButton.click()

    // Wait for results
    await page.waitForTimeout(1000)

    // Should have called IPv6 endpoint
    expect(ipv6EndpointCalled).toBe(true)
  })

  test('network CIDR triggers subnet info call', async ({ page }) => {
    await page.goto('/')

    let subnetEndpointCalled = false

    // Mock validation for network
    await page.route('**/api/v1/ipv4/validate', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'network',
          address: '192.168.1.0/24',
          network_address: '192.168.1.0',
          prefix_length: 24,
          is_ipv4: true,
          is_ipv6: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-private', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '192.168.1.0',
          is_rfc1918: true,
          is_rfc6598: false,
          matched_rfc1918_range: '192.168.0.0/16',
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-cloudflare', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '192.168.1.0',
          is_cloudflare: false,
          ip_version: 4,
        }),
      })
    })

    // Mock subnet info endpoint
    await page.route('**/api/v1/ipv4/subnet-info', route => {
      subnetEndpointCalled = true
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          network: '192.168.1.0/24',
          mode: 'standard',
          network_address: '192.168.1.0',
          broadcast_address: '192.168.1.255',
          netmask: '255.255.255.0',
          wildcard_mask: '0.0.0.255',
          prefix_length: 24,
          total_addresses: 256,
          usable_addresses: 254,
          first_usable_ip: '192.168.1.1',
          last_usable_ip: '192.168.1.254',
        }),
      })
    })

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('192.168.1.0/24')

    const submitButton = page.getByRole('button', { name: /lookup|calculate/i })
    await submitButton.click()

    // Wait for all API calls
    await page.waitForTimeout(1500)

    // Should have called subnet info endpoint
    expect(subnetEndpointCalled).toBe(true)

    // Should display subnet information
    await expect(page.getByText(/192\.168\.1\.0/)).toBeVisible()
  })

  test('displays performance timing information', async ({ page }) => {
    await page.goto('/')

    // Mock API responses
    await page.route('**/api/v1/ipv4/validate', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'address',
          address: '8.8.8.8',
          is_ipv4: true,
          is_ipv6: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-private', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '8.8.8.8',
          is_rfc1918: false,
          is_rfc6598: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-cloudflare', route => {
      route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '8.8.8.8',
          is_cloudflare: false,
          ip_version: 4,
        }),
      })
    })

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('8.8.8.8')

    const submitButton = page.getByRole('button', { name: /lookup|calculate/i })
    await submitButton.click()

    // Should display timing information
    await expect(page.getByText(/response time|duration|ms/i)).toBeVisible({ timeout: 5000 })
  })
})
