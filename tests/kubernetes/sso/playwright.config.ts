import { defineConfig, devices } from '@playwright/test'

const chromiumArgs = process.env.SSO_E2E_HOST_RESOLVER_RULES
  ? [`--host-resolver-rules=${process.env.SSO_E2E_HOST_RESOLVER_RULES}`]
  : []

export default defineConfig({
  testDir: './tests',
  workers: 1,
  fullyParallel: false,
  retries: 0,
  reporter: [['list'], ['html', { open: 'never' }]],

  use: {
    ignoreHTTPSErrors: true,
    trace: 'on-first-retry',
    screenshot: process.env.SSO_E2E_SCREENSHOTS === '1' ? 'on' : 'only-on-failure',
    video: 'retain-on-failure',
    launchOptions: {
      args: chromiumArgs,
      slowMo: process.env.PW_SLOWMO ? Number(process.env.PW_SLOWMO) : undefined,
    },
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
})
