/**
 * API client for subnet calculator
 */

import type { IApiClient } from '@subnetcalc/shared-frontend/api'
import { handleFetchError, parseJsonResponse, performCoreLookup } from '@subnetcalc/shared-frontend/api'
import type { CloudMode } from '@subnetcalc/shared-frontend/types'
import { TokenManager } from './auth'
import { API_CONFIG, getAuthMethod } from './config'
import { getGatewayAccessToken } from './entraid-auth'
import { getOidcAccessToken } from './oidc-auth'
import type {
  CloudflareCheckResponse,
  HealthResponse,
  LookupResultWithDiagnostics,
  NetworkDiagnosticsResponse,
  NetworkPlanRequirement,
  NetworkPlanResponse,
  PrivateCheckResponse,
  ProviderName,
  ProviderRangeResponse,
  SubnetInfoResponse,
  ValidateResponse,
} from './types'

class ApiClient implements IApiClient {
  private baseUrl: string
  private tokenManager: TokenManager | null

  constructor(baseUrl: string) {
    this.baseUrl = baseUrl

    // Initialize TokenManager if auth is enabled
    if (API_CONFIG.auth.enabled) {
      this.tokenManager = new TokenManager(baseUrl, API_CONFIG.auth.username, API_CONFIG.auth.password)
    } else {
      this.tokenManager = null
    }
  }

  getBaseUrl(): string {
    return this.baseUrl
  }

  private getBaseHeaders(): Record<string, string> {
    const headers: Record<string, string> = {}

    if (API_CONFIG.apimSubscriptionKey) {
      headers['Ocp-Apim-Subscription-Key'] = API_CONFIG.apimSubscriptionKey
    }

    return headers
  }

  private async getAuthHeaders(): Promise<Record<string, string>> {
    if (this.tokenManager) {
      return this.tokenManager.getAuthHeaders()
    }

    const authMethod = getAuthMethod()
    const token =
      authMethod === 'gateway'
        ? await getGatewayAccessToken()
        : authMethod === 'oidc'
          ? await getOidcAccessToken()
          : null

    if (!token) {
      return {}
    }

    return {
      Authorization: `Bearer ${token}`,
    }
  }

  async checkHealth(): Promise<HealthResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = await this.getAuthHeaders()

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.health}`, {
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
      // Get auth headers if enabled
      const authHeaders = await this.getAuthHeaders()

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.validate}`, {
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
        const error = await parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Validation failed (HTTP ${response.status})`)
      }

      return parseJsonResponse<ValidateResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async checkPrivate(address: string): Promise<PrivateCheckResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = await this.getAuthHeaders()

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.checkPrivate}`, {
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
        const error = await parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Private check failed (HTTP ${response.status})`)
      }

      return parseJsonResponse<PrivateCheckResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async checkCloudflare(address: string): Promise<CloudflareCheckResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = await this.getAuthHeaders()

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.checkCloudflare}`, {
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
        const error = await parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Cloudflare check failed (HTTP ${response.status})`)
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
        const error = await parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Provider range check failed (HTTP ${response.status})`)
      }

      return parseJsonResponse<ProviderRangeResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async getSubnetInfo(network: string, mode: CloudMode): Promise<SubnetInfoResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = await this.getAuthHeaders()

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.subnetInfo}`, {
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
        const error = await parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Subnet info failed (HTTP ${response.status})`)
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
        const error = await parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Network plan allocation failed (HTTP ${response.status})`)
      }

      return parseJsonResponse<NetworkPlanResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async getNetworkDiagnostics(): Promise<NetworkDiagnosticsResponse> {
    try {
      const authHeaders = await this.getAuthHeaders()

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.networkDiagnostics}`, {
        headers: {
          ...this.getBaseHeaders(),
          ...authHeaders,
        },
        signal: AbortSignal.timeout(15000),
      })

      if (!response.ok) {
        const error = await parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Network diagnostics failed (HTTP ${response.status})`)
      }

      return parseJsonResponse<NetworkDiagnosticsResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async getSecondaryNetworkDiagnostics(): Promise<NetworkDiagnosticsResponse | null> {
    if (!API_CONFIG.networkDiagnostics.secondaryPath) {
      return null
    }

    try {
      const response = await fetch(API_CONFIG.networkDiagnostics.secondaryPath, {
        signal: AbortSignal.timeout(15000),
      })

      if (!response.ok) {
        const error = await parseJsonResponse<{ detail?: string }>(response).catch((): { detail?: string } => ({}))
        throw new Error(error.detail || `Secondary network diagnostics failed (HTTP ${response.status})`)
      }

      return parseJsonResponse<NetworkDiagnosticsResponse>(response)
    } catch (error) {
      return handleFetchError(error)
    }
  }

  async performLookup(address: string, mode: CloudMode): Promise<LookupResultWithDiagnostics> {
    const coreLookup = await performCoreLookup(this, address, mode)
    let networkDiagnostics: NetworkDiagnosticsResponse | null = null
    let secondaryNetworkDiagnostics: NetworkDiagnosticsResponse | null = null

    if (API_CONFIG.showNetworkPath) {
      try {
        const secondaryDiagnosticsStart = performance.now()
        const secondaryDiagnosticsRequestTime = new Date().toISOString()
        secondaryNetworkDiagnostics = await this.getSecondaryNetworkDiagnostics()
        const secondaryDiagnosticsDuration = performance.now() - secondaryDiagnosticsStart

        if (secondaryNetworkDiagnostics) {
          coreLookup.timing.apiCalls.push({
            call: 'secondaryNetworkDiagnostics',
            requestTime: secondaryDiagnosticsRequestTime,
            responseTime: new Date().toISOString(),
            duration: Math.round(secondaryDiagnosticsDuration),
          })
        }
      } catch (error) {
        console.log('Secondary network diagnostics unavailable:', error)
      }

      try {
        const diagnosticsStart = performance.now()
        const diagnosticsRequestTime = new Date().toISOString()
        networkDiagnostics = await this.getNetworkDiagnostics()
        const diagnosticsDuration = performance.now() - diagnosticsStart

        coreLookup.timing.apiCalls.push({
          call: 'networkDiagnostics',
          requestTime: diagnosticsRequestTime,
          responseTime: new Date().toISOString(),
          duration: Math.round(diagnosticsDuration),
        })
      } catch (error) {
        console.log('Network diagnostics unavailable:', error)
      }
    }

    const totalDuration = coreLookup.timing.apiCalls.reduce((sum, call) => sum + call.duration, 0)

    return {
      ...coreLookup,
      networkDiagnostics,
      secondaryNetworkDiagnostics,
      timing: {
        ...coreLookup.timing,
        totalDuration: Math.max(coreLookup.timing.totalDuration, totalDuration),
      },
    }
  }
}

export const apiClient = new ApiClient(API_CONFIG.baseUrl)
