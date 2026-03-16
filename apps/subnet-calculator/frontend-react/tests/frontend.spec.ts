import type { Page } from '@playwright/test'
import { expect, test } from '@playwright/test'

const ipInput = (page: Page) => page.getByLabel(/IP Address or CIDR Range/i)

test.describe('Subnet Calculator React Frontend', () => {
  test('page loads successfully', async ({ page }) => {
    await page.goto('/')
    await expect(page).toHaveTitle(/Subnet Calculator/i)
    await expect(page.getByRole('heading', { level: 1, name: /IPv4 Subnet Calculator/i })).toBeVisible()
  })

  test('displays the primary form controls', async ({ page }) => {
    await page.goto('/')
    await expect(ipInput(page)).toBeVisible()
    await expect(page.locator('#cloud-mode')).toBeVisible()
    await expect(page.getByRole('button', { name: /^Lookup$/i })).toBeVisible()
  })

  test('accepts IPv4, IPv6, and CIDR input values', async ({ page }) => {
    await page.goto('/')

    await ipInput(page).fill('8.8.8.8')
    await expect(ipInput(page)).toHaveValue('8.8.8.8')

    await ipInput(page).fill('2001:4860:4860::8888')
    await expect(ipInput(page)).toHaveValue('2001:4860:4860::8888')

    await ipInput(page).fill('192.168.1.0/24')
    await expect(ipInput(page)).toHaveValue('192.168.1.0/24')
  })

  test('ships the current example shortcuts', async ({ page }) => {
    await page.goto('/')
    const exampleButtons = page.locator('#example-buttons button')
    await expect(exampleButtons).toHaveCount(4)
    await expect(page.getByRole('button', { name: /RFC1918: 10\.0\.0\.0\/24/i })).toBeVisible()
    await expect(page.getByRole('button', { name: /Cloudflare: 104\.16\.1\.1/i })).toBeVisible()
  })

  test('example shortcuts populate the lookup field', async ({ page }) => {
    await page.goto('/')

    await page.getByRole('button', { name: /Public: 8\.8\.8\.8/i }).click()
    await expect(ipInput(page)).toHaveValue('8.8.8.8')

    await page.getByRole('button', { name: /RFC1918: 10\.0\.0\.0\/24/i }).click()
    await expect(ipInput(page)).toHaveValue('10.0.0.0/24')
  })

  test('renders cleanly on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 })
    await page.goto('/')
    const body = await page.locator('body').boundingBox()
    expect(body?.width).toBeLessThanOrEqual(375)
    await expect(ipInput(page)).toBeVisible()
  })

  test('renders cleanly on tablet', async ({ page }) => {
    await page.setViewportSize({ width: 768, height: 1024 })
    await page.goto('/')
    const body = await page.locator('body').boundingBox()
    expect(body?.width).toBeLessThanOrEqual(768)
    await expect(ipInput(page)).toBeVisible()
  })

  test('toggles and persists the theme preference', async ({ page }) => {
    await page.goto('/')
    const themeButton = page.locator('#theme-switcher')
    await expect(themeButton).toBeVisible()

    const initialTheme = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
    await themeButton.click()
    await expect
      .poll(() => page.evaluate(() => document.documentElement.getAttribute('data-theme')))
      .not.toBe(initialTheme)

    const toggledTheme = await page.evaluate(() => document.documentElement.getAttribute('data-theme'))
    await page.reload()
    await expect
      .poll(() => page.evaluate(() => document.documentElement.getAttribute('data-theme')))
      .toBe(toggledTheme)
  })

  test('shows stage and stack metadata', async ({ page }) => {
    await page.goto('/')
    await expect(page.getByText(/^LOCAL$/i)).toBeVisible()
    await expect(page.locator('#stack-description')).toContainText(/React \+ TypeScript \+ Vite/i)
  })

  test('keeps the primary controls accessible', async ({ page }) => {
    await page.goto('/')
    await expect(ipInput(page)).toBeVisible()

    const buttons = await page.getByRole('button').all()
    for (const button of buttons) {
      const text = (await button.textContent())?.trim()
      const ariaLabel = await button.getAttribute('aria-label')
      expect(text || ariaLabel).toBeTruthy()
    }
  })
})
