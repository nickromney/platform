import fs from 'node:fs/promises'
import path from 'node:path'

import { type Page, expect, test } from '@playwright/test'

const BASE_URL = process.env.BASE_URL || 'https://sentiment.dev.127.0.0.1.sslip.io'
const USERNAME = process.env.KEYCLOAK_USERNAME || 'demo'
const PASSWORD = process.env.KEYCLOAK_PASSWORD || 'password123'

async function ensureLoggedIn(page: Page) {
  await page.goto('/', { waitUntil: 'domcontentloaded' })

  // If already on the app, nothing to do.
  const appTitle = page.getByText('Sentiment Analysis (Authenticated UI)')
  if (await appTitle.isVisible().catch(() => false)) return

  // oauth2-proxy sign-in page (provider selection)
  const providerButton = page.getByRole('button', { name: /sign in with openid connect/i })
  if (await providerButton.isVisible().catch(() => false)) {
    await providerButton.click()
  }

  // Keycloak login form.
  await page.waitForSelector('#username', { timeout: 60_000 })
  await page.fill('#username', USERNAME)
  await page.fill('#password', PASSWORD)
  await page.click('#kc-login')

  await expect(page.getByText('Sentiment Analysis (Authenticated UI)')).toBeVisible({ timeout: 60_000 })
}

function isLocalComposeUrl(baseUrl: string) {
  return baseUrl.startsWith('http://localhost') || baseUrl.startsWith('http://127.0.0.1')
}

async function countCsvRecordsIfLocalCompose() {
  if (!isLocalComposeUrl(BASE_URL)) return null

  const repoRoot = path.resolve(process.cwd(), '..')
  const csvPath = process.env.SENTIMENT_CSV_PATH || path.join(repoRoot, 'data', 'comments.csv')

  try {
    const raw = await fs.readFile(csvPath, 'utf8')
    const lines = raw
      .split('\n')
      .map((l) => l.trimEnd())
      .filter((l) => l.trim().length > 0)

    if (lines.length === 0) return 0
    // First line is header.
    return Math.max(0, lines.length - 1)
  } catch {
    // If file doesn't exist yet, treat as empty.
    return 0
  }
}

test.describe('sentiment authenticated UI: smoke', () => {
  test.describe.configure({ mode: 'serial' })

  test('login, click all buttons, analyze twice, verify response + comments persist', async ({ page }) => {
    test.setTimeout(180_000)

    await ensureLoggedIn(page)

    const textarea = page.getByPlaceholder('Type a comment to analyze…')
    await expect(textarea).toBeVisible()

    // Buttons should exist and be clickable.
    const samplePositive = page.getByRole('button', { name: 'Sample: Positive' })
    const sampleNegative = page.getByRole('button', { name: 'Sample: Negative' })
    const sampleMixed = page.getByRole('button', { name: 'Sample: Mixed' })
    const analyzeButton = page.getByRole('button', { name: 'Analyze' })
    const refreshButton = page.getByRole('button', { name: 'Refresh' })
    const logoutButton = page.getByRole('button', { name: 'Logout' })

    await expect(samplePositive).toBeVisible()
    await expect(sampleNegative).toBeVisible()
    await expect(sampleMixed).toBeVisible()
    await expect(analyzeButton).toBeVisible()
    await expect(refreshButton).toBeVisible()
    await expect(logoutButton).toBeVisible()

    // 1) Use sample buttons
    await samplePositive.click()
    await expect(textarea).toHaveValue(/absolutely love/i)

    await sampleNegative.click()
    await expect(textarea).toHaveValue(/refund/i)

    await sampleMixed.click()
    await expect(textarea).toHaveValue(/overall/i)

    // 2) Analyze sample text and verify API response + UI updates.
    const countBefore1 = await countCsvRecordsIfLocalCompose()

    await expect(analyzeButton).toBeEnabled()
    const post1 = page.waitForResponse((r) => r.url().includes('/api/v1/comments') && r.request().method() === 'POST', {
      timeout: 180_000,
    })
    await analyzeButton.click()
    const post1Response = await post1
    const post1Text = await post1Response.text()
    expect(post1Response.status(), `POST /api/v1/comments failed: ${post1Text}`).toBe(200)
    const post1Json = post1Text ? JSON.parse(post1Text) : null

    expect(typeof post1Json?.label).toBe('string')
    expect(['positive', 'negative', 'neutral']).toContain(post1Json.label)
    expect(typeof post1Json?.confidence).toBe('number')

    // UI: should show a non-empty classification.
    const lastResultValue = page.locator('.status .value')
    await expect(lastResultValue).toContainText(/positive|negative|neutral/i, { timeout: 60_000 })

    const countAfter1 = await countCsvRecordsIfLocalCompose()
    if (countBefore1 !== null && countAfter1 !== null) {
      expect(countAfter1).toBe(countBefore1 + 1)
    }

    // 3) Paste custom text (not from a sample button) and analyze again.
    const customText = `Custom test text ${Date.now()} — I am not sure how I feel about this.`
    await textarea.fill(customText)
    await expect(textarea).toHaveValue(customText)

    const countBefore2 = await countCsvRecordsIfLocalCompose()
    await expect(analyzeButton).toBeEnabled()
    const post2 = page.waitForResponse((r) => r.url().includes('/api/v1/comments') && r.request().method() === 'POST', {
      timeout: 180_000,
    })
    await analyzeButton.click()
    const post2Response = await post2
    const post2Text = await post2Response.text()
    expect(post2Response.status(), `POST /api/v1/comments failed: ${post2Text}`).toBe(200)
    const post2Json = post2Text ? JSON.parse(post2Text) : null
    expect(post2Json?.text).toBe(customText)

    const countAfter2 = await countCsvRecordsIfLocalCompose()
    if (countBefore2 !== null && countAfter2 !== null) {
      expect(countAfter2).toBe(countBefore2 + 1)
    }

    // 4) Refresh should be clickable and the custom text should appear in recent comments.
    await refreshButton.click()
    await expect(page.locator('.list').getByText(customText)).toBeVisible({ timeout: 30_000 })

    // 5) Logout button should navigate away to oauth2-proxy.
    await logoutButton.click()
    await page.waitForURL(/(oauth2\/sign_in|protocol\/openid-connect\/logout)/, { timeout: 60_000 })
  })
})
