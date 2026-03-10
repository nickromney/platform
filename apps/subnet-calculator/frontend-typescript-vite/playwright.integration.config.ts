import { defineConfig, devices } from '@playwright/test'

/**
 * Playwright Integration Test Configuration
 *
 * Tests against running containers - NO MOCKING
 * Validates real JWT authentication and API calls
 *
 * Usage:
 *   npm run test:integration              # Stack 5 (JWT)
 *   npm run test:integration:stack4       # Stack 4 (no auth)
 */
export default defineConfig({
  testDir: './tests',
  testMatch: '**/integration.spec.ts',
  fullyParallel: false, // Run serially to avoid overwhelming API
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 1, // Retry once for flaky network issues
  workers: 1, // Single worker to avoid race conditions
  reporter: 'html',
  timeout: 30000, // 30 second timeout for real API calls

  use: {
    baseURL: process.env.BASE_URL || 'http://localhost:3001',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],

  // Expect containers to already be running
  // No webServer configuration - user must start containers manually
})
