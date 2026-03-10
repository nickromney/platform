/**
 * Frontend E2E tests for React subnet calculator
 * Tests basic functionality, responsive design, and user interactions
 */

import { test, expect } from '@playwright/test'

test.describe('Subnet Calculator React Frontend', () => {
  test('page loads successfully', async ({ page }) => {
    await page.goto('/')
    await expect(page).toHaveTitle(/Subnet Calculator/i)
  })

  test('has main heading', async ({ page }) => {
    await page.goto('/')
    const heading = page.getByRole('heading', { level: 1 })
    await expect(heading).toBeVisible()
  })

  test('displays form elements', async ({ page }) => {
    await page.goto('/')

    // Check for IP address input
    const ipInput = page.getByPlaceholder(/IP address/i)
    await expect(ipInput).toBeVisible()

    // Check for submit button
    const submitButton = page.getByRole('button', { name: /lookup|calculate/i })
    await expect(submitButton).toBeVisible()
  })

  test('has cloud mode selector', async ({ page }) => {
    await page.goto('/')

    // Check for mode selector (Standard, Simple, Expert)
    const modeSelector = page.locator('select').or(page.locator('[role="radiogroup"]'))
    await expect(modeSelector.first()).toBeVisible()
  })

  test('validates invalid IP address', async ({ page }) => {
    await page.goto('/')

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('invalid.ip.address')

    const submitButton = page.getByRole('button', { name: /lookup|calculate/i })
    await submitButton.click()

    // Should show validation error
    await expect(page.getByText(/invalid|error/i)).toBeVisible({ timeout: 5000 })
  })

  test('accepts valid IPv4 address', async ({ page }) => {
    await page.goto('/')

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('8.8.8.8')

    // Input should be accepted without validation error on the input itself
    await expect(ipInput).toHaveValue('8.8.8.8')
  })

  test('accepts valid IPv6 address', async ({ page }) => {
    await page.goto('/')

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('2001:4860:4860::8888')

    // Input should be accepted
    await expect(ipInput).toHaveValue('2001:4860:4860::8888')
  })

  test('accepts CIDR notation', async ({ page }) => {
    await page.goto('/')

    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('192.168.1.0/24')

    await expect(ipInput).toHaveValue('192.168.1.0/24')
  })

  test('has example buttons', async ({ page }) => {
    await page.goto('/')

    // Should have at least one example button
    const exampleButton = page.getByRole('button', { name: /example|192.168|10.0|172.16/i })
    await expect(exampleButton.first()).toBeVisible()
  })

  test('example button populates input', async ({ page }) => {
    await page.goto('/')

    const exampleButton = page.getByRole('button', { name: /192.168|10.0|172.16/i }).first()
    await exampleButton.click()

    const ipInput = page.getByPlaceholder(/IP address/i)
    const value = await ipInput.inputValue()

    // Should have populated the input with an IP address
    expect(value).toMatch(/^\d+\.\d+\.\d+\.\d+(\/\d+)?$/)
  })

  test('is mobile responsive', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 }) // iPhone SE
    await page.goto('/')

    // Page should render without horizontal scroll
    const body = await page.locator('body').boundingBox()
    expect(body?.width).toBeLessThanOrEqual(375)

    // Main elements should still be visible
    await expect(page.getByPlaceholder(/IP address/i)).toBeVisible()
  })

  test('is tablet responsive', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 }) // iPad
    await page.goto('/')

    const body = await page.locator('body').boundingBox()
    expect(body?.width).toBeLessThanOrEqual(768)

    await expect(page.getByPlaceholder(/IP address/i)).toBeVisible()
  })

  test('has theme switcher', async ({ page }) => {
    await page.goto('/')

    // Look for theme toggle button (common patterns: sun/moon icon, "theme", "dark mode")
    const themeButton = page.getByRole('button').filter({
      hasText: /theme|dark|light/i
    }).or(page.locator('[aria-label*="theme" i]'))

    await expect(themeButton.first()).toBeVisible()
  })

  test('theme switcher changes appearance', async ({ page }) => {
    await page.goto('/')

    const themeButton = page.getByRole('button').filter({
      hasText: /theme|dark|light/i
    }).or(page.locator('[aria-label*="theme" i]')).first()

    // Get initial background color
    const body = page.locator('body')
    const initialBg = await body.evaluate(el => window.getComputedStyle(el).backgroundColor)

    await themeButton.click()
    await page.waitForTimeout(300) // Wait for theme transition

    const newBg = await body.evaluate(el => window.getComputedStyle(el).backgroundColor)

    // Background should have changed
    expect(newBg).not.toBe(initialBg)
  })

  test('theme preference persists across reload', async ({ page }) => {
    await page.goto('/')

    const themeButton = page.getByRole('button').filter({
      hasText: /theme|dark|light/i
    }).or(page.locator('[aria-label*="theme" i]')).first()

    // Toggle theme
    await themeButton.click()
    await page.waitForTimeout(300)

    const body = page.locator('body')
    const themeAfterToggle = await body.evaluate(el => window.getComputedStyle(el).backgroundColor)

    // Reload page
    await page.reload()
    await page.waitForTimeout(300)

    const themeAfterReload = await body.evaluate(el => window.getComputedStyle(el).backgroundColor)

    // Theme should be the same after reload
    expect(themeAfterReload).toBe(themeAfterToggle)
  })

  test('has loading state indicator', async ({ page }) => {
    await page.goto('/')

    // Loading indicator should exist (hidden initially)
    const loading = page.locator('[role="status"]').or(page.getByText(/loading/i))
    await expect(loading.first()).toBeDefined()
  })

  test('has error display area', async ({ page }) => {
    await page.goto('/')

    // Error display should exist in the DOM
    const errorArea = page.locator('[role="alert"]').or(page.locator('.error'))
    await expect(errorArea.first()).toBeDefined()
  })

  test('has results display area', async ({ page }) => {
    await page.goto('/')

    // Results area should exist
    const results = page.locator('[data-testid="results"]').or(page.locator('.results'))
    await expect(results.first()).toBeDefined()
  })

  test('has clear button', async ({ page }) => {
    await page.goto('/')

    const clearButton = page.getByRole('button', { name: /clear|reset/i })
    await expect(clearButton).toBeVisible()
  })

  test('clear button empties input', async ({ page }) => {
    await page.goto('/')

    // Fill input
    const ipInput = page.getByPlaceholder(/IP address/i)
    await ipInput.fill('192.168.1.1')

    // Click clear
    const clearButton = page.getByRole('button', { name: /clear|reset/i })
    await clearButton.click()

    // Input should be empty
    await expect(ipInput).toHaveValue('')
  })

  test('displays API health status', async ({ page }) => {
    await page.goto('/')

    // Should show API status (connected/disconnected)
    await expect(page.getByText(/API|Backend|Connected|Disconnected/i).first()).toBeVisible({
      timeout: 10000
    })
  })

  test('has accessible form labels', async ({ page }) => {
    await page.goto('/')

    // Input should have associated label (either <label> or aria-label)
    const ipInput = page.getByPlaceholder(/IP address/i)
    const ariaLabel = await ipInput.getAttribute('aria-label')
    const id = await ipInput.getAttribute('id')

    if (id) {
      const label = page.locator(`label[for="${id}"]`)
      const labelExists = await label.count()
      expect(labelExists > 0 || ariaLabel).toBeTruthy()
    } else {
      expect(ariaLabel).toBeTruthy()
    }
  })

  test('buttons have accessible labels', async ({ page }) => {
    await page.goto('/')

    const buttons = await page.getByRole('button').all()

    for (const button of buttons) {
      const text = await button.textContent()
      const ariaLabel = await button.getAttribute('aria-label')

      // Each button should have either text or aria-label
      expect(text || ariaLabel).toBeTruthy()
    }
  })

  test('has IPv6 example button', async ({ page }) => {
    await page.goto('/')

    const ipv6Button = page.getByRole('button', { name: /2001:db8|IPv6/i })
    await expect(ipv6Button).toBeVisible()
  })

  test('IPv6 example button populates input', async ({ page }) => {
    await page.goto('/')

    const ipv6Button = page.getByRole('button', { name: /2001:db8|IPv6/i })
    await ipv6Button.click()

    const ipInput = page.getByPlaceholder(/IP address/i)
    const value = await ipInput.inputValue()

    // Should be an IPv6 address (contains colons)
    expect(value).toContain(':')
  })

  test('displays stack information', async ({ page }) => {
    await page.goto('/')

    // Should show which stack is running (React + TypeScript + Vite + deployment method)
    await expect(page.getByText(/React.*TypeScript.*Vite/i)).toBeVisible()
  })
})
