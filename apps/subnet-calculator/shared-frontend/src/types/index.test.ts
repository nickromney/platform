/**
 * Tests for type definitions and type guards
 */

import { describe, expect, it } from 'vitest'
import type {
  ApiResults,
  CloudMode,
  CloudflareCheckResponse,
  HealthResponse,
  PrivateCheckResponse,
  SubnetInfoResponse,
  ValidateResponse,
} from './index'

describe('CloudMode type', () => {
  it('should accept valid cloud modes', () => {
    const modes: CloudMode[] = ['Standard', 'AWS', 'Azure', 'OCI']
    expect(modes).toHaveLength(4)
    expect(modes).toContain('Standard')
    expect(modes).toContain('AWS')
    expect(modes).toContain('Azure')
    expect(modes).toContain('OCI')
  })
})

describe('HealthResponse', () => {
  it('should have correct shape', () => {
    const response: HealthResponse = {
      status: 'healthy',
      service: 'Subnet Calculator API',
      version: '1.0.0',
    }

    expect(response.status).toBe('healthy')
    expect(response.service).toBe('Subnet Calculator API')
    expect(response.version).toBe('1.0.0')
  })
})

describe('ValidateResponse', () => {
  it('should validate IPv4 address response', () => {
    const response: ValidateResponse = {
      valid: true,
      type: 'address',
      address: '192.168.1.1',
      is_ipv4: true,
      is_ipv6: false,
    }

    expect(response.valid).toBe(true)
    expect(response.type).toBe('address')
    expect(response.is_ipv4).toBe(true)
    expect(response.is_ipv6).toBe(false)
  })

  it('should validate IPv6 network response', () => {
    const response: ValidateResponse = {
      valid: true,
      type: 'network',
      address: '2001:db8::/32',
      network_address: '2001:db8::',
      prefix_length: 32,
      is_ipv4: false,
      is_ipv6: true,
    }

    expect(response.type).toBe('network')
    expect(response.is_ipv6).toBe(true)
    expect(response.prefix_length).toBe(32)
  })
})

describe('PrivateCheckResponse', () => {
  it('should check RFC1918 address', () => {
    const response: PrivateCheckResponse = {
      address: '10.0.0.1',
      is_rfc1918: true,
      is_rfc6598: false,
      matched_rfc1918_range: '10.0.0.0/8',
    }

    expect(response.is_rfc1918).toBe(true)
    expect(response.is_rfc6598).toBe(false)
    expect(response.matched_rfc1918_range).toBe('10.0.0.0/8')
  })

  it('should check RFC6598 address', () => {
    const response: PrivateCheckResponse = {
      address: '100.64.0.1',
      is_rfc1918: false,
      is_rfc6598: true,
      matched_rfc6598_range: '100.64.0.0/10',
    }

    expect(response.is_rfc1918).toBe(false)
    expect(response.is_rfc6598).toBe(true)
    expect(response.matched_rfc6598_range).toBe('100.64.0.0/10')
  })
})

describe('CloudflareCheckResponse', () => {
  it('should check Cloudflare IPv4 address', () => {
    const response: CloudflareCheckResponse = {
      address: '104.16.1.1',
      is_cloudflare: true,
      ip_version: 4,
      matched_ranges: ['104.16.0.0/13'],
    }

    expect(response.is_cloudflare).toBe(true)
    expect(response.ip_version).toBe(4)
    expect(response.matched_ranges).toHaveLength(1)
  })

  it('should check non-Cloudflare address', () => {
    const response: CloudflareCheckResponse = {
      address: '8.8.8.8',
      is_cloudflare: false,
      ip_version: 4,
      matched_ranges: [],
    }

    expect(response.is_cloudflare).toBe(false)
    expect(response.matched_ranges).toEqual([])
  })
})

describe('SubnetInfoResponse', () => {
  it('should contain IPv4 subnet information', () => {
    const response: SubnetInfoResponse = {
      network: '10.0.0.0/24',
      mode: 'Azure',
      network_address: '10.0.0.0',
      broadcast_address: '10.0.0.255',
      netmask: '255.255.255.0',
      wildcard_mask: '0.0.0.255',
      prefix_length: 24,
      total_addresses: 256,
      usable_addresses: 251,
      first_usable_ip: '10.0.0.4',
      last_usable_ip: '10.0.0.254',
    }

    expect(response.mode).toBe('Azure')
    expect(response.prefix_length).toBe(24)
    expect(response.total_addresses).toBe(256)
    expect(response.usable_addresses).toBe(251)
  })

  it('should handle IPv6 subnet (no broadcast)', () => {
    // Note: IPv6 address counts can exceed JavaScript's safe integer range
    // API returns these as numbers, so we use a smaller subnet for testing
    const response: SubnetInfoResponse = {
      network: '2001:db8::/112',
      mode: 'Standard',
      network_address: '2001:db8::',
      broadcast_address: null,
      netmask: 'ffff:ffff:ffff:ffff:ffff:ffff:ffff:0',
      wildcard_mask: '::ffff',
      prefix_length: 112,
      total_addresses: 65536,
      usable_addresses: 65536,
      first_usable_ip: '2001:db8::',
      last_usable_ip: '2001:db8::ffff',
    }

    expect(response.broadcast_address).toBeNull()
    expect(response.prefix_length).toBe(112)
  })
})

describe('ApiResults', () => {
  it('should contain all optional result types', () => {
    const results: ApiResults = {
      validate: {
        valid: true,
        type: 'network',
        address: '10.0.0.0/24',
        is_ipv4: true,
        is_ipv6: false,
      },
      private: {
        address: '10.0.0.0',
        is_rfc1918: true,
        is_rfc6598: false,
      },
      cloudflare: {
        address: '10.0.0.0',
        is_cloudflare: false,
        ip_version: 4,
      },
      subnet: {
        network: '10.0.0.0/24',
        mode: 'Azure',
        network_address: '10.0.0.0',
        broadcast_address: '10.0.0.255',
        netmask: '255.255.255.0',
        wildcard_mask: '0.0.0.255',
        prefix_length: 24,
        total_addresses: 256,
        usable_addresses: 251,
        first_usable_ip: '10.0.0.4',
        last_usable_ip: '10.0.0.254',
      },
    }

    expect(results.validate).toBeDefined()
    expect(results.private).toBeDefined()
    expect(results.cloudflare).toBeDefined()
    expect(results.subnet).toBeDefined()
  })

  it('should allow partial results', () => {
    const results: ApiResults = {
      validate: {
        valid: true,
        type: 'address',
        address: '8.8.8.8',
        is_ipv4: true,
        is_ipv6: false,
      },
    }

    expect(results.validate).toBeDefined()
    expect(results.private).toBeUndefined()
    expect(results.subnet).toBeUndefined()
  })
})
