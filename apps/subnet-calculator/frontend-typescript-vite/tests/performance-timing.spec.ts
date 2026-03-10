/**
 * Performance timing feature tests
 *
 * Tests that performance metrics are displayed when API lookups are performed.
 */

import { expect, test } from '@playwright/test'

test.describe('Performance Timing', () => {
  test.beforeEach(async ({ page }) => {
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
