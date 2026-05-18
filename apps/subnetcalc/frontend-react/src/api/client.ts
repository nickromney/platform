/**
 * API Client for subnet calculator
 * Supports both IPv4 and IPv6 lookups with performance timing
 */

import { TokenManager } from '@subnetcalc/shared-frontend'
import type { IApiClient } from '@subnetcalc/shared-frontend/api'
import { getApiPrefix, handleFetchError, parseJsonResponse, performCoreLookup } from '@subnetcalc/shared-frontend/api'
import { getEasyAuthAccessToken } from '../auth/easyAuthProvider'
import { APP_CONFIG } from '../config'
import type {
  CloudflareCheckResponse,
  CloudMode,
  HealthResponse,
  LookupResult,
  NetworkPlanRequirement,
  NetworkPlanResponse,
  PrivateCheckResponse,
  ProviderName,
  ProviderRangeResponse,
  SubnetInfoResponse,
  ValidateResponse,
} from '../types'

// Error message constants
const AUTH_REQUIRED_ERROR = 'Please log in to use the calculator'

async function getOidcAuthHeaders(): Promise<Record<string, string>> {
  const { getOidcAccessToken } = await import('../auth/oidcAuthProvider')
  const token = await getOidcAccessToken()
  if (!token) {
    return {}
  }

  return {
    Authorization: `Bearer ${token}`,
  }
}

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
      return getOidcAuthHeaders()
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

  async checkProviderRange(provider: ProviderName, address: string): Promise<ProviderRangeResponse> {
    try {
      const authHeaders = await this.getAuthHeaders()
      const response = await fetch(`${this.baseUrl}/api/v1/provider-ranges/check`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...this.getBaseHeaders(),
          ...authHeaders,
        },
        body: JSON.stringify({ provider, address }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error(AUTH_REQUIRED_ERROR)
        }
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return parseJsonResponse<ProviderRangeResponse>(response)
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

  async allocateNetworkPlan(
    parent: string,
    mode: CloudMode,
    requirements: NetworkPlanRequirement[]
  ): Promise<NetworkPlanResponse> {
    try {
      const authHeaders = await this.getAuthHeaders()
      const response = await fetch(`${this.baseUrl}/api/v1/network-plan/allocate`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...this.getBaseHeaders(),
          ...authHeaders,
        },
        body: JSON.stringify({ parent, mode, requirements }),
        signal: AbortSignal.timeout(10000),
      })

      if (!response.ok) {
        if (response.status === 401) {
          throw new Error(AUTH_REQUIRED_ERROR)
        }
        const errorData = await response.json().catch(() => ({ detail: response.statusText }))
        throw new Error(errorData.detail || `HTTP ${response.status}: ${response.statusText}`)
      }

      return parseJsonResponse<NetworkPlanResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  /**
   * Perform complete lookup with timing information
   */
  async performLookup(address: string, mode: CloudMode): Promise<LookupResult> {
    return performCoreLookup(this, address, mode)
  }
}

// Export singleton instance
export const apiClient = new ApiClient(APP_CONFIG.apiBaseUrl)
