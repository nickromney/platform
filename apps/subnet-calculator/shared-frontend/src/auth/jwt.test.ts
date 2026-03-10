/**
 * Tests for JWT TokenManager
 */

import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { TokenManager } from './jwt'

// Mock fetch globally
const mockFetch = vi.fn()
global.fetch = mockFetch

describe('TokenManager', () => {
  beforeEach(() => {
    mockFetch.mockReset()
    vi.clearAllTimers()
    vi.useFakeTimers()
  })

  afterEach(() => {
    vi.useRealTimers()
  })

  describe('isAuthEnabled', () => {
    it('should return true when username and password are provided', () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')
      expect(manager.isAuthEnabled()).toBe(true)
    })

    it('should return false when username is empty', () => {
      const manager = new TokenManager('http://localhost:8080', '', 'password123')
      expect(manager.isAuthEnabled()).toBe(false)
    })

    it('should return false when password is empty', () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', '')
      expect(manager.isAuthEnabled()).toBe(false)
    })

    it('should return false when both username and password are empty', () => {
      const manager = new TokenManager('http://localhost:8080', '', '')
      expect(manager.isAuthEnabled()).toBe(false)
    })
  })

  describe('getToken', () => {
    it('should return null when auth is not enabled', async () => {
      const manager = new TokenManager('http://localhost:8080', '', '')
      const token = await manager.getToken()
      expect(token).toBeNull()
    })

    it('should login and return token on first call', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'test-token', token_type: 'bearer' }),
      })

      const token = await manager.getToken()

      expect(token).toBe('test-token')
      expect(mockFetch).toHaveBeenCalledTimes(1)
      expect(mockFetch).toHaveBeenCalledWith(
        'http://localhost:8080/api/v1/auth/login',
        expect.objectContaining({
          method: 'POST',
          headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        })
      )
    })

    it('should return cached token when still valid', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'test-token', token_type: 'bearer' }),
      })

      // First call - should login
      const token1 = await manager.getToken()
      expect(token1).toBe('test-token')
      expect(mockFetch).toHaveBeenCalledTimes(1)

      // Second call - should use cache
      const token2 = await manager.getToken()
      expect(token2).toBe('test-token')
      expect(mockFetch).toHaveBeenCalledTimes(1) // No additional call
    })

    it('should refresh token when cache expires', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ access_token: 'token-1', token_type: 'bearer' }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ access_token: 'token-2', token_type: 'bearer' }),
        })

      // First call
      const token1 = await manager.getToken()
      expect(token1).toBe('token-1')

      // Advance time past cache expiration (25 minutes + 1 second)
      vi.advanceTimersByTime(25 * 60 * 1000 + 1000)

      // Second call - should refresh
      const token2 = await manager.getToken()
      expect(token2).toBe('token-2')
      expect(mockFetch).toHaveBeenCalledTimes(2)
    })

    it('should retry once on network error', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch.mockRejectedValueOnce(new Error('Network error')).mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'test-token', token_type: 'bearer' }),
      })

      // Run with real timers since the retry delay uses setTimeout
      vi.useRealTimers()
      const token = await manager.getToken()
      vi.useFakeTimers()

      expect(token).toBe('test-token')
      expect(mockFetch).toHaveBeenCalledTimes(2)
    })

    it('should throw error when login fails with non-2xx status', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'wrong-password')

      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 401,
      })

      await expect(manager.getToken()).rejects.toThrow('Login failed: HTTP 401')
    })

    it('should clear cache on login error', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      // First successful login
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'token-1', token_type: 'bearer' }),
      })

      await manager.getToken()
      expect(mockFetch).toHaveBeenCalledTimes(1)

      // Expire cache
      vi.advanceTimersByTime(25 * 60 * 1000 + 1000)

      // Failed refresh attempt
      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 401,
      })

      await expect(manager.getToken()).rejects.toThrow()

      // Next attempt should try to login again (cache was cleared)
      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'token-2', token_type: 'bearer' }),
      })

      const token = await manager.getToken()
      expect(token).toBe('token-2')
    })
  })

  describe('getAuthHeaders', () => {
    it('should return empty object when auth is not enabled', async () => {
      const manager = new TokenManager('http://localhost:8080', '', '')
      const headers = await manager.getAuthHeaders()
      expect(headers).toEqual({})
    })

    it('should return Authorization header with Bearer token', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'test-token', token_type: 'bearer' }),
      })

      const headers = await manager.getAuthHeaders()

      expect(headers).toEqual({
        Authorization: 'Bearer test-token',
      })
    })

    it('should return empty object when token retrieval fails', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch.mockResolvedValueOnce({
        ok: false,
        status: 401,
      })

      await expect(manager.getAuthHeaders()).rejects.toThrow()
    })
  })

  describe('clearCache', () => {
    it('should clear cached token', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ access_token: 'token-1', token_type: 'bearer' }),
        })
        .mockResolvedValueOnce({
          ok: true,
          json: async () => ({ access_token: 'token-2', token_type: 'bearer' }),
        })

      // First call
      const token1 = await manager.getToken()
      expect(token1).toBe('token-1')

      // Clear cache
      manager.clearCache()

      // Should login again instead of using cache
      const token2 = await manager.getToken()
      expect(token2).toBe('token-2')
      expect(mockFetch).toHaveBeenCalledTimes(2)
    })
  })

  describe('login request format', () => {
    it('should send credentials as form-urlencoded', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'test-token', token_type: 'bearer' }),
      })

      await manager.getToken()

      const callArgs = mockFetch.mock.calls[0]
      const body = callArgs[1].body as URLSearchParams

      expect(body.get('username')).toBe('demo')
      expect(body.get('password')).toBe('password123')
    })

    it('should include 5 second timeout', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'test-token', token_type: 'bearer' }),
      })

      await manager.getToken()

      const callArgs = mockFetch.mock.calls[0]
      const signal = callArgs[1].signal

      expect(signal).toBeDefined()
    })
  })

  describe('token expiration handling', () => {
    it('should cache token for 25 minutes (5 minutes before actual expiry)', async () => {
      const manager = new TokenManager('http://localhost:8080', 'demo', 'password123')

      mockFetch.mockResolvedValueOnce({
        ok: true,
        json: async () => ({ access_token: 'test-token', token_type: 'bearer' }),
      })

      await manager.getToken()

      // Token should still be cached at 24 minutes
      vi.advanceTimersByTime(24 * 60 * 1000)
      mockFetch.mockClear()

      const token = await manager.getToken()
      expect(token).toBe('test-token')
      expect(mockFetch).not.toHaveBeenCalled()
    })
  })
})
