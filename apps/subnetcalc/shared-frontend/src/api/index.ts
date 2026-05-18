/**
 * Shared API client interface and utilities
 */

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

/**
 * API Client interface that all frontends must implement
 */
export interface IApiClient {
  /**
   * Get the base URL of the API
   */
  getBaseUrl(): string

  /**
   * Check API health
   */
  checkHealth(): Promise<HealthResponse>

  /**
   * Validate an IP address or network
   */
  validateAddress(address: string): Promise<ValidateResponse>

  /**
   * Check if address is RFC1918 private (IPv4 only)
   */
  checkPrivate(address: string): Promise<PrivateCheckResponse>

  /**
   * Check if address is in Cloudflare ranges
   */
  checkCloudflare(address: string): Promise<CloudflareCheckResponse>

  /**
   * Check if address is in a generic provider range
   */
  checkProviderRange(provider: ProviderName, address: string): Promise<ProviderRangeResponse>

  /**
   * Get subnet information for a network
   */
  getSubnetInfo(network: string, mode: CloudMode): Promise<SubnetInfoResponse>

  /**
   * Allocate a network plan within a parent network
   */
  allocateNetworkPlan(
    parent: string,
    mode: CloudMode,
    requirements: NetworkPlanRequirement[]
  ): Promise<NetworkPlanResponse>

  /**
   * Perform complete lookup with all checks
   */
  performLookup(address: string, mode: CloudMode): Promise<LookupResult>
}

/**
 * Detect if an address is IPv6 based on presence of colons
 */
export function isIpv6(address: string): boolean {
  return address.includes(':')
}

/**
 * Get API path prefix based on IP version
 */
export function getApiPrefix(address: string): string {
  return isIpv6(address) ? '/api/v1/ipv6' : '/api/v1/ipv4'
}

/**
 * Handle fetch errors with user-friendly messages
 */
export function handleFetchError(error: unknown): never {
  if (error instanceof Error) {
    if (error.name === 'TimeoutError' || error.name === 'AbortError') {
      throw new Error('API request timed out. The API may be starting up or unavailable.', { cause: error })
    }
    if (error.message.includes('Failed to fetch') || error.message.includes('NetworkError')) {
      throw new Error('Unable to connect to API. Please ensure the backend is running.', { cause: error })
    }
  }
  throw error
}

/**
 * Safely parse JSON response with proper error handling
 */
export async function parseJsonResponse<T>(response: Response): Promise<T> {
  const contentType = response.headers.get('content-type')
  if (!contentType?.includes('application/json')) {
    throw new Error('API did not return JSON response. It may still be starting up.')
  }

  try {
    return await response.json()
  } catch {
    throw new Error('Failed to parse API response. The API may be starting up or in an error state.')
  }
}

async function timedApiCall<T>(
  apiCalls: LookupResult['timing']['apiCalls'],
  call: string,
  operation: () => Promise<T>
): Promise<T> {
  const start = performance.now()
  const requestTime = new Date().toISOString()
  const result = await operation()
  apiCalls.push({
    call,
    requestTime,
    responseTime: new Date().toISOString(),
    duration: Math.round(performance.now() - start),
  })
  return result
}

/**
 * Perform the core subnet lookup workflow shared by frontend implementations.
 *
 * Concrete clients still own backend routing, auth headers, APIM subscription
 * headers, and fetch details. This helper owns the domain-level lookup order
 * and API call timing contract.
 */
export async function performCoreLookup(client: IApiClient, address: string, mode: CloudMode): Promise<LookupResult> {
  const overallStart = performance.now()
  const apiCalls: LookupResult['timing']['apiCalls'] = []
  const results: LookupResult['results'] = {}
  const isV6 = isIpv6(address)

  results.validate = await timedApiCall(apiCalls, 'validate', () => client.validateAddress(address))

  if (!isV6) {
    results.private = await timedApiCall(apiCalls, 'checkPrivate', () => client.checkPrivate(address))
  }

  results.cloudflare = await timedApiCall(apiCalls, 'checkCloudflare', () => client.checkCloudflare(address))

  if (results.validate.type === 'network') {
    results.subnet = await timedApiCall(apiCalls, 'subnetInfo', () => client.getSubnetInfo(address, mode))
  }

  const overallDuration = Math.round(performance.now() - overallStart)
  return {
    results,
    timing: {
      overallDuration,
      renderingDuration: 0,
      totalDuration: overallDuration,
      apiCalls,
    },
  }
}
