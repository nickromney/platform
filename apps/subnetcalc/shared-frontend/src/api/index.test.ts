/**
 * Tests for API utility functions
 */

import { describe, expect, it } from 'vitest'
import type {
  CloudflareCheckResponse,
  CloudMode,
  HealthResponse,
  NetworkPlanRequirement,
  NetworkPlanResponse,
  PrivateCheckResponse,
  ProviderName,
  ProviderRangeResponse,
  SubnetInfoResponse,
  ValidateResponse,
} from '../types'
import type { IApiClient } from './index'
import { getApiPrefix, handleFetchError, isIpv6, parseJsonResponse, performCoreLookup } from './index'

describe('isIpv6', () => {
  it('should return true for IPv6 addresses', () => {
    expect(isIpv6('2001:db8::')).toBe(true)
    expect(isIpv6('2001:db8::/32')).toBe(true)
    expect(isIpv6('::1')).toBe(true)
    expect(isIpv6('fe80::1')).toBe(true)
  })

  it('should return false for IPv4 addresses', () => {
    expect(isIpv6('192.168.1.1')).toBe(false)
    expect(isIpv6('10.0.0.0/24')).toBe(false)
    expect(isIpv6('8.8.8.8')).toBe(false)
  })

  it('should return false for empty or invalid input', () => {
    expect(isIpv6('')).toBe(false)
    expect(isIpv6('not-an-ip')).toBe(false)
  })
})

describe('getApiPrefix', () => {
  it('should return IPv6 prefix for IPv6 addresses', () => {
    expect(getApiPrefix('2001:db8::')).toBe('/api/v1/ipv6')
    expect(getApiPrefix('2001:db8::/32')).toBe('/api/v1/ipv6')
    expect(getApiPrefix('::1')).toBe('/api/v1/ipv6')
  })

  it('should return IPv4 prefix for IPv4 addresses', () => {
    expect(getApiPrefix('192.168.1.1')).toBe('/api/v1/ipv4')
    expect(getApiPrefix('10.0.0.0/24')).toBe('/api/v1/ipv4')
    expect(getApiPrefix('8.8.8.8')).toBe('/api/v1/ipv4')
  })
})

describe('handleFetchError', () => {
  it('should throw timeout error message for TimeoutError', () => {
    const error = new Error('Timeout')
    error.name = 'TimeoutError'

    expect(() => handleFetchError(error)).toThrow('API request timed out. The API may be starting up or unavailable.')
  })

  it('should throw timeout error message for AbortError', () => {
    const error = new Error('Aborted')
    error.name = 'AbortError'

    expect(() => handleFetchError(error)).toThrow('API request timed out. The API may be starting up or unavailable.')
  })

  it('should throw connection error message for fetch failures', () => {
    const error = new Error('Failed to fetch')

    expect(() => handleFetchError(error)).toThrow('Unable to connect to API. Please ensure the backend is running.')
  })

  it('should throw connection error message for NetworkError', () => {
    const error = new Error('NetworkError when attempting to fetch resource')

    expect(() => handleFetchError(error)).toThrow('Unable to connect to API. Please ensure the backend is running.')
  })

  it('should rethrow unknown errors', () => {
    const error = new Error('Some other error')

    expect(() => handleFetchError(error)).toThrow('Some other error')
  })

  it('should rethrow non-Error objects', () => {
    const error = 'string error'

    expect(() => handleFetchError(error)).toThrow('string error')
  })
})

describe('parseJsonResponse', () => {
  it('should parse valid JSON response', async () => {
    const mockResponse = {
      ok: true,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: async () => ({ data: 'test' }),
    } as Response

    const result = await parseJsonResponse(mockResponse)
    expect(result).toEqual({ data: 'test' })
  })

  it('should throw error for non-JSON content type', async () => {
    const mockResponse = {
      ok: true,
      headers: new Headers({ 'content-type': 'text/html' }),
      json: async () => ({}),
    } as Response

    await expect(parseJsonResponse(mockResponse)).rejects.toThrow(
      'API did not return JSON response. It may still be starting up.'
    )
  })

  it('should throw error for missing content-type header', async () => {
    const mockResponse = {
      ok: true,
      headers: new Headers(),
      json: async () => ({}),
    } as Response

    await expect(parseJsonResponse(mockResponse)).rejects.toThrow(
      'API did not return JSON response. It may still be starting up.'
    )
  })

  it('should throw error for invalid JSON', async () => {
    const mockResponse = {
      ok: true,
      headers: new Headers({ 'content-type': 'application/json' }),
      json: async () => {
        throw new SyntaxError('Unexpected token')
      },
    } as Response

    await expect(parseJsonResponse(mockResponse)).rejects.toThrow(
      'Failed to parse API response. The API may be starting up or in an error state.'
    )
  })
})

describe('performCoreLookup', () => {
  class FakeApiClient implements IApiClient {
    calls: string[] = []

    getBaseUrl(): string {
      return 'http://api.test'
    }

    async checkHealth(): Promise<HealthResponse> {
      return { status: 'healthy', service: 'test', version: '1.0.0' }
    }

    async validateAddress(address: string): Promise<ValidateResponse> {
      this.calls.push(`validate:${address}`)
      return {
        valid: true,
        type: address.includes('/') ? 'network' : 'address',
        address,
        is_ipv4: !address.includes(':'),
        is_ipv6: address.includes(':'),
      }
    }

    async checkPrivate(address: string): Promise<PrivateCheckResponse> {
      this.calls.push(`private:${address}`)
      return { address, is_rfc1918: true, is_rfc6598: false }
    }

    async checkCloudflare(address: string): Promise<CloudflareCheckResponse> {
      this.calls.push(`cloudflare:${address}`)
      return { address, is_cloudflare: false, ip_version: address.includes(':') ? 6 : 4 }
    }

    async checkProviderRange(provider: ProviderName, address: string): Promise<ProviderRangeResponse> {
      return {
        address,
        provider,
        is_provider_range: provider === 'aws',
        ip_version: address.includes(':') ? 6 : 4,
        range_source: 'bundled',
      }
    }

    async getSubnetInfo(network: string, mode: CloudMode): Promise<SubnetInfoResponse> {
      this.calls.push(`subnet:${network}:${mode}`)
      return {
        network,
        mode,
        network_address: network.split('/')[0],
        broadcast_address: null,
        netmask: '255.255.255.0',
        wildcard_mask: '0.0.0.255',
        prefix_length: 24,
        total_addresses: 256,
        usable_addresses: 251,
        first_usable_ip: '10.0.0.4',
        last_usable_ip: '10.0.0.254',
      }
    }

    async allocateNetworkPlan(
      parent: string,
      mode: CloudMode,
      requirements: NetworkPlanRequirement[]
    ): Promise<NetworkPlanResponse> {
      return {
        parent,
        mode,
        allocations: requirements.map((requirement) => ({
          name: requirement.name,
          network: '10.0.0.0/25',
          prefix_length: 25,
          total_addresses: 128,
          usable_addresses: 123,
          first_usable_ip: '10.0.0.4',
          last_usable_ip: '10.0.0.126',
        })),
      }
    }

    async performLookup(address: string, mode: CloudMode) {
      return performCoreLookup(this, address, mode)
    }
  }

  it('orchestrates validate, private, cloudflare, subnet, and timings for IPv4 networks', async () => {
    const client = new FakeApiClient()

    const result = await performCoreLookup(client, '10.0.0.0/24', 'Azure')

    expect(client.calls).toEqual([
      'validate:10.0.0.0/24',
      'private:10.0.0.0/24',
      'cloudflare:10.0.0.0/24',
      'subnet:10.0.0.0/24:Azure',
    ])
    expect(result.results.subnet?.usable_addresses).toBe(251)
    expect(result.timing.apiCalls.map((call) => call.call)).toEqual([
      'validate',
      'checkPrivate',
      'checkCloudflare',
      'subnetInfo',
    ])
    expect(result.timing.totalDuration).toBeGreaterThanOrEqual(result.timing.overallDuration)
  })

  it('skips private checks for IPv6 addresses', async () => {
    const client = new FakeApiClient()

    const result = await performCoreLookup(client, '2001:db8::1', 'Standard')

    expect(client.calls).toEqual(['validate:2001:db8::1', 'cloudflare:2001:db8::1'])
    expect(result.results.private).toBeUndefined()
    expect(result.results.subnet).toBeUndefined()
  })
})
