import { defineConfig, devices } from '@playwright/test'

const chromiumArgs = process.env.SSO_E2E_HOST_RESOLVER_RULES
  ? [`--host-resolver-rules=${process.env.SSO_E2E_HOST_RESOLVER_RULES}`]
  : []

const browserChannel = process.env.PLATFORM_PLAYWRIGHT_CHANNEL || undefined

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
    channel: browserChannel,
    launchOptions: {
      args: chromiumArgs,
      executablePath: browserChannel ? undefined : process.env.SSO_E2E_CHROMIUM_EXECUTABLE_PATH || undefined,
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
