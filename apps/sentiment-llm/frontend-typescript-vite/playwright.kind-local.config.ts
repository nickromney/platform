import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: './tests',
  testMatch: '**/kind-local-sentiment-auth-*.spec.ts',
  workers: 1,
  fullyParallel: false,
  retries: 0,
  reporter: 'html',

  use: {
    baseURL: process.env.BASE_URL || 'https://sentiment.dev.127.0.0.1.sslip.io',
    ignoreHTTPSErrors: true,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
})
