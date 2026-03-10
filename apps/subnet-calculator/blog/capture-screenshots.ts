/**
 * Playwright script to capture screenshots for blog posts
 * Run with: npx playwright test capture-screenshots.ts --project=chromium
 */

import { test, expect } from '@playwright/test';
import { chromium } from '@playwright/test';
import * as path from 'path';

const BLOG_DIR = path.join(__dirname);
const API_URL = process.env.API_URL || 'http://localhost:8090';
const BASE_URL = process.env.BASE_URL || 'http://localhost:3000';

test.describe('Capture screenshots for blog posts', () => {
  test('Part 12: TypeScript Vite Frontend screenshots', async ({ page }) => {
    const screenshotDir = path.join(BLOG_DIR, '2025-10-10-python-api-azure-functions-12');

    // Navigate to the TypeScript Vite frontend
    await page.goto(BASE_URL);

    // Wait for page to load
    await page.waitForLoadState('networkidle');

    // Screenshot 1: Initial load with light theme
    await page.screenshot({
      path: path.join(screenshotDir, 'vite-app-light-theme.png'),
      fullPage: true
    });

    // Screenshot 2: Switch to dark theme
    const themeButton = page.locator('[data-theme-switcher]').or(page.locator('button:has-text("Toggle Theme")'));
    if (await themeButton.isVisible()) {
      await themeButton.click();
      await page.waitForTimeout(500);
      await page.screenshot({
        path: path.join(screenshotDir, 'vite-app-dark-theme.png'),
        fullPage: true
      });
    }

    // Screenshot 3: Fill form with sample data
    await page.fill('input[type="text"]', '192.168.1.0/24');
    await page.screenshot({
      path: path.join(screenshotDir, 'form-filled.png'),
      fullPage: true
    });

    // Screenshot 4: Submit and show results
    await page.click('button[type="submit"]');
    await page.waitForTimeout(1000);
    await page.screenshot({
      path: path.join(screenshotDir, 'results-displayed.png'),
      fullPage: true
    });

    // Screenshot 5: Open DevTools programmatically to show Network tab
    // Note: This requires special browser context - capture manually
    console.log('✓ Part 12 screenshots captured');
  });

  test('Part 14: Test UI screenshots', async ({ page, browser }) => {
    const screenshotDir = path.join(BLOG_DIR, '2025-10-12-python-api-azure-functions-14');

    // Note: Playwright UI mode and test reports require manual screenshots
    // This test just documents the requirement

    console.log('✓ Part 14 requires manual screenshots of:');
    console.log('  - pytest terminal output (run: uv run pytest -v)');
    console.log('  - playwright UI mode (run: npm run test:ui)');
    console.log('  - playwright HTML report');
  });
});

test.describe('Additional UI screenshots', () => {
  test('Capture TypeScript code editor view', async ({ page }) => {
    // This would require opening a code editor - capture manually
    console.log('✓ Manual screenshot needed: TypeScript code in editor showing type safety');
  });

  test('Capture browser DevTools', async ({ context }) => {
    // DevTools screenshots require CDP or manual capture
    console.log('✓ Manual screenshot needed: Browser DevTools Network tab showing API calls');
  });
});

// Standalone script mode for easier execution
if (require.main === module) {
  (async () => {
    const browser = await chromium.launch({ headless: false });
    const context = await browser.newContext({
      viewport: { width: 1280, height: 720 },
    });
    const page = await context.newPage();

    const BLOG_DIR_LOCAL = __dirname;
    const screenshotDir = path.join(BLOG_DIR_LOCAL, '2025-10-10-python-api-azure-functions-12');

    console.log('Capturing screenshots for Part 12...');
    console.log('Starting frontend at:', BASE_URL);
    console.log('Using API at:', API_URL);
    console.log('Screenshots will be saved to:', screenshotDir);

    try {
      await page.goto(BASE_URL);
      await page.waitForLoadState('networkidle');

      // Light theme
      await page.screenshot({
        path: path.join(screenshotDir, 'vite-app-light-theme.png'),
        fullPage: true
      });
      console.log('✓ Captured: vite-app-light-theme.png');

      // Dark theme
      const themeButton = page.locator('[data-theme-switcher]').or(page.locator('button:has-text("Toggle Theme")'));
      if (await themeButton.count() > 0) {
        await themeButton.first().click();
        await page.waitForTimeout(500);
        await page.screenshot({
          path: path.join(screenshotDir, 'vite-app-dark-theme.png'),
          fullPage: true
        });
        console.log('✓ Captured: vite-app-dark-theme.png');
      }

      // Form filled
      const input = page.locator('input[type="text"]').first();
      await input.fill('192.168.1.0/24');
      await page.screenshot({
        path: path.join(screenshotDir, 'form-filled.png'),
        fullPage: true
      });
      console.log('✓ Captured: form-filled.png');

      // Results
      await page.click('button[type="submit"]');
      await page.waitForTimeout(2000);
      await page.screenshot({
        path: path.join(screenshotDir, 'results-displayed.png'),
        fullPage: true
      });
      console.log('✓ Captured: results-displayed.png');

      console.log('\n✓ All automated screenshots captured successfully!');
      console.log('\nManual screenshots still needed:');
      console.log('  - Browser DevTools Network tab');
      console.log('  - VS Code showing TypeScript code');
      console.log('  - Terminal outputs (pytest, make commands)');

    } catch (error) {
      console.error('Error capturing screenshots:', error);
    } finally {
      await browser.close();
    }
  })();
}
