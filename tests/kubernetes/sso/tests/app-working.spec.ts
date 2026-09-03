import { expect, test } from '@playwright/test'
import {
  OIDC_HOST,
  TARGETS,
  attachLoggedInScreenshotIfEnabled,
  loginToTarget,
} from '../lib/harness'
import { missingWorkingContracts, workingAssertion } from '../lib/working'

const missing = missingWorkingContracts()
if (missing.length > 0) {
  throw new Error(`SSO working suite is missing contracts for: ${missing.join(', ')}`)
}

test.describe('platform SSO endpoints: working', () => {
  test.describe.configure({ mode: 'serial' })

  for (const target of TARGETS) {
    test(`${target.name}: is working`, async ({ page }, testInfo) => {
      test.setTimeout(240_000)
      await loginToTarget(page, target)
      await workingAssertion(target)(page, target)
      await attachLoggedInScreenshotIfEnabled(page, testInfo, `${target.name}-working`)
      await expect(page.locator('#login')).toHaveCount(0)
      await expect(page.locator('#username')).toHaveCount(0)
      if (target.name !== 'keycloak') {
        expect(new URL(page.url()).host === OIDC_HOST).toBe(false)
      }
    })
  }
})
