import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright configuration for TypeScript Vite frontend
 * See https://playwright.dev/docs/test-configuration
 */
export default defineConfig({
  testDir: './tests',
  testIgnore: ['**/integration.spec.ts', '**/swa.spec.ts'], // Exclude opt-in suites with their own configs
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',

  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  webServer: process.env.BASE_URL
    ? undefined
    : {
        command: 'bun run preview',
        url: 'http://localhost:3000',
        reuseExistingServer: !process.env.CI,
      },
})
