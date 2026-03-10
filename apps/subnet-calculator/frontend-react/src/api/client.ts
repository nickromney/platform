/**
 * API Client for subnet calculator
 * Supports both IPv4 and IPv6 lookups with performance timing
 */

import { TokenManager } from '@subnet-calculator/shared-frontend'
import type { IApiClient } from '@subnet-calculator/shared-frontend/api'
import { getApiPrefix, handleFetchError, isIpv6, parseJsonResponse } from '@subnet-calculator/shared-frontend/api'
import { getEasyAuthAccessToken } from '../auth/easyAuthProvider'
import { getOidcAccessToken } from '../auth/oidcAuthProvider'
import { APP_CONFIG } from '../config'
import type {
  ApiCallTiming,
  CloudflareCheckResponse,
  CloudMode,
  HealthResponse,
  LookupResult,
  PrivateCheckResponse,
  SubnetInfoResponse,
  ValidateResponse,
} from '../types'

// Error message constants
const AUTH_REQUIRED_ERROR = 'Please log in to use the calculator'

class ApiClient implements IApiClient {
  private baseUrl: string
  private tokenManager: TokenManager | null = null
  private easyAuthToken: { token: string; expiresAt?: number } | null = null

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl

    // Initialize token manager if JWT auth is configured
    if (APP_CONFIG.auth.method === 'jwt') {
      this.tokenManager = new TokenManager(
        APP_CONFIG.apiBaseUrl,
        APP_CONFIG.auth.jwtUsername || '',
        APP_CONFIG.auth.jwtPassword || ''
      )
    }
  }

  private getBaseHeaders(): Record<string, string> {
    const headers: Record<string, string> = {}
    if (APP_CONFIG.apimSubscriptionKey) {
      headers['Ocp-Apim-Subscription-Key'] = APP_CONFIG.apimSubscriptionKey
    }
    return headers
  }

  /**
   * Get authentication headers (Authorization bearer token for JWT/OIDC)
   */
  private async getAuthHeaders(): Promise<Record<string, string>> {
    // OIDC authentication
    if (APP_CONFIG.auth.method === 'oidc') {
      const token = await getOidcAccessToken()
      if (token) {
        return {
          Authorization: `Bearer ${token}`,
        }
      }
      return {}
    }

    // JWT authentication with token manager
    if (this.tokenManager) {
      return await this.tokenManager.getAuthHeaders()
    }

    // Easy Auth token handling
    if (await this.shouldAttachEasyAuthToken()) {
      const token = await this.getEasyAuthAuthHeader()
      if (token) {
        return token
      }
    }

    return {}
  }

  private async shouldAttachEasyAuthToken(): Promise<boolean> {
    if (APP_CONFIG.auth.method !== 'easyauth') {
      return false
    }

    if (!this.baseUrl) {
      return false
    }

    try {
      const apiOrigin = new URL(this.baseUrl, window.location.origin).origin
      return apiOrigin !== window.location.origin
    } catch {
      return false
    }
  }

  private async getEasyAuthAuthHeader(): Promise<Record<string, string> | null> {
    if (this.easyAuthToken && (!this.easyAuthToken.expiresAt || this.easyAuthToken.expiresAt - 60_000 > Date.now())) {
      return this.buildEasyAuthHeaders(this.easyAuthToken.token)
    }

    const tokenInfo = await getEasyAuthAccessToken(
      this.easyAuthToken !== null,
      APP_CONFIG.auth.easyAuthResourceId || undefined
    )
    if (!tokenInfo) {
      return null
    }

    this.easyAuthToken = tokenInfo
    return this.buildEasyAuthHeaders(tokenInfo.token)
  }

  private buildEasyAuthHeaders(token: string): Record<string, string> {
    return {
      Authorization: `Bearer ${token}`,
      'X-ZUMO-AUTH': token,
    }
  }

  getBaseUrl(): string {
    return this.baseUrl
  }

  async checkHealth(): Promise<HealthResponse> {
    try {
      const authHeaders = await this.getAuthHeaders()
      const response = await fetch(`${this.baseUrl}/api/v1/health`, {
        headers: {
          ...this.getBaseHeaders(),
          ...authHeaders,
        },
        signal: AbortSignal.timeout(5000), // 5 second timeout
      })

      if (!response.ok) {
        throw new Error(`API returned HTTP ${response.status}: ${response.statusText}`)
      }

      return parseJsonResponse<HealthResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async validateAddress(address: string): Promise<ValidateResponse> {
    try {
      const apiPrefix = getApiPrefix(address)
      const authHeaders = await this.getAuthHeaders()
      const response = await fetch(`${this.baseUrl}${apiPrefix}/validate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...this.getBaseHeaders(),
          ...authHeaders,
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000), // 10 second timeout
      })

      if (!response.ok) {
        // User-friendly error for authentication failures
        if (response.status === 401) {
          throw new Error(AUTH_REQUIRED_ERROR)
        }
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return parseJsonResponse<ValidateResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async checkPrivate(address: string): Promise<PrivateCheckResponse> {
    try {
      const authHeaders = await this.getAuthHeaders()
      const response = await fetch(`${this.baseUrl}/api/v1/ipv4/check-private`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...this.getBaseHeaders(),
          ...authHeaders,
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        // User-friendly error for authentication failures
        if (response.status === 401) {
          throw new Error(AUTH_REQUIRED_ERROR)
        }
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return parseJsonResponse<PrivateCheckResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async checkCloudflare(address: string): Promise<CloudflareCheckResponse> {
    try {
      const apiPrefix = getApiPrefix(address)
      const authHeaders = await this.getAuthHeaders()
      const response = await fetch(`${this.baseUrl}${apiPrefix}/check-cloudflare`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...this.getBaseHeaders(),
          ...authHeaders,
        },
        body: JSON.stringify({ address }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        // User-friendly error for authentication failures
        if (response.status === 401) {
          throw new Error(AUTH_REQUIRED_ERROR)
        }
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return parseJsonResponse<CloudflareCheckResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async getSubnetInfo(network: string, mode: CloudMode): Promise<SubnetInfoResponse> {
    try {
      const apiPrefix = getApiPrefix(network)
      const authHeaders = await this.getAuthHeaders()
      const response = await fetch(`${this.baseUrl}${apiPrefix}/subnet-info`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...this.getBaseHeaders(),
          ...authHeaders,
        },
        body: JSON.stringify({ network, mode }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        // User-friendly error for authentication failures
        if (response.status === 401) {
          throw new Error(AUTH_REQUIRED_ERROR)
        }
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return parseJsonResponse<SubnetInfoResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  /**
   * Perform complete lookup with timing information
   */
  async performLookup(address: string, mode: CloudMode): Promise<LookupResult> {
    const overallStart = performance.now()
    const apiCalls: ApiCallTiming[] = []
    const results: LookupResult['results'] = {}

    const isV6 = isIpv6(address)

    // 1. Validate address
    const validateStart = performance.now()
    const validateRequestTime = new Date().toISOString()
    results.validate = await this.validateAddress(address)
    const validateDuration = performance.now() - validateStart
    apiCalls.push({
      call: 'validate',
      requestTime: validateRequestTime,
      responseTime: new Date().toISOString(),
      duration: Math.round(validateDuration),
    })

    // 2. Check if RFC1918 (private) - IPv4 only
    if (!isV6) {
      const privateStart = performance.now()
      const privateRequestTime = new Date().toISOString()
      results.private = await this.checkPrivate(address)
      const privateDuration = performance.now() - privateStart
      apiCalls.push({
        call: 'checkPrivate',
        requestTime: privateRequestTime,
        responseTime: new Date().toISOString(),
        duration: Math.round(privateDuration),
      })
    }

    // 3. Check if Cloudflare
    const cloudflareStart = performance.now()
    const cloudflareRequestTime = new Date().toISOString()
    results.cloudflare = await this.checkCloudflare(address)
    const cloudflareDuration = performance.now() - cloudflareStart
    apiCalls.push({
      call: 'checkCloudflare',
      requestTime: cloudflareRequestTime,
      responseTime: new Date().toISOString(),
      duration: Math.round(cloudflareDuration),
    })

    // 4. Get subnet info if it's a network
    if (results.validate.type === 'network') {
      const subnetStart = performance.now()
      const subnetRequestTime = new Date().toISOString()
      results.subnet = await this.getSubnetInfo(address, mode)
      const subnetDuration = performance.now() - subnetStart
      apiCalls.push({
        call: 'subnetInfo',
        requestTime: subnetRequestTime,
        responseTime: new Date().toISOString(),
        duration: Math.round(subnetDuration),
      })
    }

    const overallDuration = performance.now() - overallStart

    return {
      results,
      timing: {
        overallDuration: Math.round(overallDuration),
        renderingDuration: 0, // Will be calculated by UI
        totalDuration: Math.round(overallDuration),
        apiCalls,
      },
    }
  }
}

// Export singleton instance
export const apiClient = new ApiClient(APP_CONFIG.apiBaseUrl)
