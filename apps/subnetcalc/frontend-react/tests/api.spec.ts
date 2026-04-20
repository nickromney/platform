import type { Page } from '@playwright/test'
import { expect, test } from '@playwright/test'

const HEALTH_RESPONSE = {
  status: 'ok',
  service: 'subnetcalc-api',
  version: 'test',
}

const fillLookupForm = async (page: Page, address: string) => {
  await page.getByLabel(/IP Address or CIDR Range/i).fill(address)
  await page.getByRole('button', { name: /^Lookup$/i }).click()
}

const mockHealthyApi = async (page: Page) => {
  await page.route('**/api/v1/health', async (route) => {
    await route.fulfill({
      status: 200,
      contentType: 'application/json',
      body: JSON.stringify(HEALTH_RESPONSE),
    })
  })
}

test.describe('API Integration', () => {
  test('displays API health status on page load', async ({ page }) => {
    await mockHealthyApi(page)
    await page.goto('/')
    await expect(page.locator('#api-status')).toContainText(/API Status:\s*healthy/i)
    await expect(page.locator('#api-status')).toContainText(/subnetcalc-api/i)
  })

  test('handles API unavailable gracefully', async ({ page }) => {
    await page.addInitScript(() => {
      const nativeFetch = window.fetch.bind(window)
      window.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
        const requestUrl = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url
        if (requestUrl.includes('/api/v1/health')) {
          throw new TypeError('Failed to fetch')
        }
        return nativeFetch(input, init)
      }) as typeof window.fetch
    })

    await page.goto('/')
    await expect(page.locator('#api-status')).toContainText(/API Offline/i, { timeout: 15000 })
    await expect(page.locator('#api-status')).toContainText(/Unable to connect to API/i)
  })

  test('handles API timeout gracefully', async ({ page }) => {
    await page.addInitScript(() => {
      const nativeFetch = window.fetch.bind(window)
      window.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
        const requestUrl = typeof input === 'string' ? input : input instanceof URL ? input.toString() : input.url
        if (requestUrl.includes('/api/v1/health')) {
          throw new DOMException('The operation was aborted.', 'AbortError')
        }
        return nativeFetch(input, init)
      }) as typeof window.fetch
    })

    await page.goto('/')
    await expect(page.locator('#api-status')).toContainText(/API Offline/i, { timeout: 15000 })
    await expect(page.locator('#api-status')).toContainText(/timed out/i)
  })

  test('handles non-JSON API response', async ({ page }) => {
    await page.route('**/api/v1/health', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'text/html',
        body: '<html><body>Not JSON</body></html>',
      })
    })

    await page.goto('/')
    await expect(page.locator('#api-status')).toContainText(/API Offline/i, { timeout: 15000 })
    await expect(page.locator('#api-status')).toContainText(/did not return JSON/i)
  })

  test('handles HTTP error codes', async ({ page }) => {
    await mockHealthyApi(page)
    await page.route('**/api/v1/ipv4/validate', async (route) => {
      await route.fulfill({
        status: 400,
        contentType: 'application/json',
        body: JSON.stringify({ detail: 'Invalid IP address format' }),
      })
    })

    await page.goto('/')
    await fillLookupForm(page, '999.999.999.999')
    await expect(page.locator('#error')).toContainText(/Invalid IP address format/i)
  })

  test('successful IPv4 lookup displays results', async ({ page }) => {
    await mockHealthyApi(page)
    await page.route('**/api/v1/ipv4/validate', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'address',
          address: '8.8.8.8',
          is_ipv4: true,
          is_ipv6: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-private', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '8.8.8.8',
          is_rfc1918: false,
          is_rfc6598: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-cloudflare', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '8.8.8.8',
          is_cloudflare: false,
          ip_version: 4,
        }),
      })
    })

    await page.goto('/')
    await fillLookupForm(page, '8.8.8.8')
    await expect(page.locator('#results')).toBeVisible()
    await expect(page.getByRole('heading', { name: /Validation/i })).toBeVisible()
    await expect(page.getByRole('cell', { name: '8.8.8.8' }).first()).toBeVisible()
    await expect(page.getByRole('heading', { name: /Performance Timing/i })).toBeVisible()
  })

  test('successful IPv6 lookup uses correct endpoint', async ({ page }) => {
    await mockHealthyApi(page)

    let ipv6EndpointCalled = false

    await page.route('**/api/v1/ipv6/validate', async (route) => {
      ipv6EndpointCalled = true
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'address',
          address: '2001:4860:4860::8888',
          is_ipv4: false,
          is_ipv6: true,
        }),
      })
    })

    await page.route('**/api/v1/ipv6/check-cloudflare', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '2001:4860:4860::8888',
          is_cloudflare: false,
          ip_version: 6,
        }),
      })
    })

    await page.goto('/')
    await fillLookupForm(page, '2001:4860:4860::8888')
    expect(ipv6EndpointCalled).toBe(true)
    await expect(page.locator('#results')).toBeVisible()
    await expect(page.getByText(/IPv6/i)).toBeVisible()
  })

  test('network CIDR triggers subnet info call', async ({ page }) => {
    await mockHealthyApi(page)

    let subnetEndpointCalled = false

    await page.route('**/api/v1/ipv4/validate', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'network',
          address: '192.168.1.0/24',
          network_address: '192.168.1.0',
          prefix_length: 24,
          is_ipv4: true,
          is_ipv6: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-private', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '192.168.1.0',
          is_rfc1918: true,
          is_rfc6598: false,
          matched_rfc1918_range: '192.168.0.0/16',
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-cloudflare', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '192.168.1.0',
          is_cloudflare: false,
          ip_version: 4,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/subnet-info', async (route) => {
      subnetEndpointCalled = true
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          network: '192.168.1.0/24',
          mode: 'standard',
          network_address: '192.168.1.0',
          broadcast_address: '192.168.1.255',
          netmask: '255.255.255.0',
          wildcard_mask: '0.0.0.255',
          prefix_length: 24,
          total_addresses: 256,
          usable_addresses: 254,
          first_usable_ip: '192.168.1.1',
          last_usable_ip: '192.168.1.254',
        }),
      })
    })

    await page.goto('/')
    await fillLookupForm(page, '192.168.1.0/24')
    await expect.poll(() => subnetEndpointCalled).toBe(true)
    await expect(page.getByRole('heading', { name: /Subnet Information/i })).toBeVisible()
    await expect(page.getByRole('cell', { name: '192.168.1.0', exact: true })).toBeVisible()
  })

  test('displays performance timing information', async ({ page }) => {
    await mockHealthyApi(page)
    await page.route('**/api/v1/ipv4/validate', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          valid: true,
          type: 'address',
          address: '8.8.8.8',
          is_ipv4: true,
          is_ipv6: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-private', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '8.8.8.8',
          is_rfc1918: false,
          is_rfc6598: false,
        }),
      })
    })

    await page.route('**/api/v1/ipv4/check-cloudflare', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          address: '8.8.8.8',
          is_cloudflare: false,
          ip_version: 4,
        }),
      })
    })

    await page.goto('/')
    await fillLookupForm(page, '8.8.8.8')
    await expect(page.getByRole('heading', { name: /Performance Timing/i })).toBeVisible()
    await expect(page.getByText(/Total Response Time/i)).toBeVisible()
    await expect(page.getByText(/\d+ms/).first()).toBeVisible()
  })
})
