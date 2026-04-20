/**
 * Tests for API utility functions
 */

import { describe, expect, it } from 'vitest'
import { getApiPrefix, handleFetchError, isIpv6, parseJsonResponse } from './index'

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
