/**
 * Performance timing feature tests
 *
 * Tests that performance metrics are displayed when API lookups are performed.
 */

import type { Page } from '@playwright/test'
import { expect, test } from '@playwright/test'

const HEALTH_RESPONSE = {
  status: 'ok',
  service: 'subnetcalc-api',
  version: 'test',
}

const subnetInfoResponse = (network: string, mode: string) => ({
  network,
  mode,
  network_address: network.split('/')[0],
  broadcast_address: '10.0.0.255',
  netmask: '255.255.255.0',
  wildcard_mask: '0.0.0.255',
  prefix_length: Number.parseInt(network.split('/')[1] || '24', 10),
  total_addresses: 256,
  usable_addresses: 254,
  first_usable_ip: '10.0.0.1',
  last_usable_ip: '10.0.0.254',
})

async function mockLookupApis(page: Page) {
  await page.route('**/api/v1/health', (route) =>
    route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(HEALTH_RESPONSE),
    })
  )

  await page.route('**/api/v1/ipv4/validate', async (route) => {
    const { address } = route.request().postDataJSON() as { address: string }
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        valid: true,
        type: address.includes('/') ? 'network' : 'address',
        address,
        is_ipv4: true,
        is_ipv6: false,
      }),
    })
  })

  await page.route('**/api/v1/ipv4/check-private', async (route) => {
    const { address } = route.request().postDataJSON() as { address: string }
    const isRfc1918 = address.startsWith('10.') || address.startsWith('192.168.') || address.startsWith('172.16.')
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify({
        is_rfc1918: isRfc1918,
        is_rfc6598: false,
        matched_rfc1918_range: isRfc1918 ? '10.0.0.0/8' : null,
      }),
    })
  })

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

  await page.route('**/api/v1/ipv4/subnet-info', async (route) => {
    const { network, mode } = route.request().postDataJSON() as { network: string; mode: string }
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(subnetInfoResponse(network, mode)),
    })
  })
}

test.describe('Performance Timing', () => {
  test.beforeEach(async ({ page }) => {
    await mockLookupApis(page)

    // Start from the home page
    await page.goto('/')

    // Wait for the app to be ready
    await page.waitForSelector('#lookup-form')
  })

  test('should display performance timing after successful lookup', async ({ page }) => {
    // Fill in the form with a valid IP
    await page.fill('#ip-address', '192.168.1.1')
    await page.selectOption('select[name="mode"]', 'Standard')

    // Click the lookup button
    await page.click('button[type="submit"]')

    // Wait for results to appear
    await page.waitForSelector('#results', { state: 'visible' })

    // Check that performance timing section exists
    const performanceSection = page.locator('.performance-timing')
    await expect(performanceSection).toBeVisible()

    // Check that the performance heading is present
    await expect(performanceSection.locator('h3')).toContainText('Performance')

    // Check that response time is displayed
    const responseTimeCell = performanceSection.locator('td').filter({ hasText: /\d+ms/ })
    await expect(responseTimeCell).toBeVisible()

    // Verify response time format (should be like "123ms (0.123s)")
    const responseTimeText = await responseTimeCell.textContent()
    expect(responseTimeText).toMatch(/\d+ms \(\d+\.\d{3}s\)/)
  })

  test('should display timestamps in performance timing', async ({ page }) => {
    // Fill in the form
    await page.fill('#ip-address', '10.0.0.0/24')

    // Submit
    await page.click('button[type="submit"]')

    // Wait for results
    await page.waitForSelector('.performance-timing', { state: 'visible' })

    // Check request timestamp is present
    const requestRow = page.locator('.performance-timing tr').filter({ hasText: 'First Request Sent (UTC)' })
    await expect(requestRow).toBeVisible()
    const requestTimestamp = await requestRow.locator('td').textContent()
    expect(requestTimestamp).toMatch(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)

    // Check response timestamp is present
    const responseRow = page.locator('.performance-timing tr').filter({ hasText: 'Last Response Received (UTC)' })
    await expect(responseRow).toBeVisible()
    const responseTimestamp = await responseRow.locator('td').textContent()
    expect(responseTimestamp).toMatch(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/)
  })

  test('should display request payload in performance timing', async ({ page }) => {
    const testAddress = '172.16.0.0/16'
    const testMode = 'AWS'

    // Fill in the form
    await page.fill('#ip-address', testAddress)
    await page.selectOption('select[name="mode"]', testMode)

    // Submit
    await page.click('button[type="submit"]')

    // Wait for results
    await page.waitForSelector('.performance-timing', { state: 'visible' })

    // Check request payload is present
    const payloadRow = page.locator('.performance-timing tr').filter({ hasText: 'Request Payload' })
    await expect(payloadRow).toBeVisible()

    // Verify JSON payload format
    const payload = await payloadRow.locator('td code').textContent()
    expect(payload).toContain(`"address":"${testAddress}"`)
    expect(payload).toContain(`"mode":"${testMode}"`)
  })
  test('should measure and display timing for multiple sequential lookups', async ({ page }) => {
    // First lookup
    await page.fill('#ip-address', '192.168.1.1')
    await page.click('button[type="submit"]')
    await page.waitForSelector('.performance-timing', { state: 'visible' })

    const firstTiming = await page.locator('.performance-timing td').filter({ hasText: /\d+ms/ }).textContent()

    // Second lookup (different IP)
    await page.fill('#ip-address', '10.0.0.0/8')
    await page.click('button[type="submit"]')
    await page.waitForSelector('.performance-timing', { state: 'visible' })

    const secondTiming = await page.locator('.performance-timing td').filter({ hasText: /\d+ms/ }).textContent()

    // Verify both timings are present and potentially different
    expect(firstTiming).toBeTruthy()
    expect(secondTiming).toBeTruthy()

    // Performance timing should be displayed for the latest lookup
    const performanceSection = page.locator('.performance-timing')
    await expect(performanceSection).toBeVisible()
  })
})
