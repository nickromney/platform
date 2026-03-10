/**
 * API client for subnet calculator
 */

import type { IApiClient } from '@subnet-calculator/shared-frontend/api'
import { handleFetchError, isIpv6, parseJsonResponse } from '@subnet-calculator/shared-frontend/api'
import type { CloudMode } from '@subnet-calculator/shared-frontend/types'
import { TokenManager } from './auth'
import { API_CONFIG } from './config'
import type {
  ApiResults,
  CloudflareCheckResponse,
  HealthResponse,
  LookupResult,
  LookupResultWithDiagnostics,
  NetworkDiagnosticsResponse,
  PrivateCheckResponse,
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

  async checkHealth(): Promise<HealthResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.health}`, {
        headers: {
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
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.validate}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
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
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.checkPrivate}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
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
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.checkCloudflare}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
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

  async getSubnetInfo(network: string, mode: CloudMode): Promise<SubnetInfoResponse> {
    try {
      // Get auth headers if enabled
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.subnetInfo}`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
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

  async getNetworkDiagnostics(): Promise<NetworkDiagnosticsResponse> {
    try {
      const authHeaders = this.tokenManager ? await this.tokenManager.getAuthHeaders() : {}

      const response = await fetch(`${this.baseUrl}${API_CONFIG.paths.networkDiagnostics}`, {
        headers: {
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

  async performLookup(address: string, mode: CloudMode): Promise<LookupResultWithDiagnostics> {
    const overallStart = performance.now()
    const apiCalls: LookupResult['timing']['apiCalls'] = []
    const results: ApiResults = {}
    let networkDiagnostics: NetworkDiagnosticsResponse | null = null

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
      try {
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
      } catch (e) {
        // IPv6 addresses don't support this endpoint
        console.log('Private check skipped:', e)
      }
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

    if (API_CONFIG.showNetworkPath) {
      try {
        const diagnosticsStart = performance.now()
        const diagnosticsRequestTime = new Date().toISOString()
        networkDiagnostics = await this.getNetworkDiagnostics()
        const diagnosticsDuration = performance.now() - diagnosticsStart

        apiCalls.push({
          call: 'networkDiagnostics',
          requestTime: diagnosticsRequestTime,
          responseTime: new Date().toISOString(),
          duration: Math.round(diagnosticsDuration),
        })
      } catch (error) {
        console.log('Network diagnostics unavailable:', error)
      }
    }

    const overallDuration = performance.now() - overallStart

    return {
      results,
      networkDiagnostics,
      timing: {
        overallDuration: Math.round(overallDuration),
        renderingDuration: 0, // Will be calculated by UI
        totalDuration: Math.round(overallDuration),
        apiCalls,
      },
    }
  }
}

export const apiClient = new ApiClient(API_CONFIG.baseUrl)
