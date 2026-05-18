/**
 * Shared type definitions for subnet calculator API responses
 * Used by both React and TypeScript Vite frontends
 */

/**
 * Cloud provider mode for subnet calculations
 * Different providers reserve different numbers of addresses
 */
export type CloudMode = 'Standard' | 'AWS' | 'Azure' | 'OCI'

/**
 * Provider range sources supported by the generic provider range API
 */
export type ProviderName = 'cloudflare' | 'aws' | 'azure' | 'stripe' | 'openai'

/**
 * Health check response from API
 */
export interface HealthResponse {
  status: string
  service: string
  version: string
}

/**
 * Validation response for IP addresses and networks
 */
export interface ValidateResponse {
  valid: boolean
  type: 'address' | 'network'
  address: string
  network_address?: string
  netmask?: string
  prefix_length?: number
  num_addresses?: number
  is_ipv4: boolean
  is_ipv6: boolean
}

/**
 * RFC1918 private address check (IPv4 only)
 */
export interface PrivateCheckResponse {
  address: string
  is_rfc1918: boolean
  is_rfc6598: boolean
  matched_rfc1918_range?: string
  matched_rfc6598_range?: string
}

/**
 * Cloudflare IP range check
 */
export interface CloudflareCheckResponse {
  address: string
  is_cloudflare: boolean
  ip_version: number
  matched_ranges?: string[]
}

/**
 * Generic provider range check
 */
export interface ProviderRangeResponse {
  address: string
  provider: ProviderName
  is_provider_range: boolean
  ip_version: number
  range_source: string
  range_source_url?: string
  range_source_note?: string
  matched_ranges?: string[]
}

/**
 * Subnet information response
 */
export interface SubnetInfoResponse {
  network: string
  mode: string
  network_address: string
  broadcast_address: string | null
  netmask: string
  wildcard_mask: string
  prefix_length: number
  total_addresses: number
  usable_addresses: number
  first_usable_ip: string
  last_usable_ip: string
  note?: string
}

/**
 * Host-count requirement for network planning
 */
export interface NetworkPlanRequirement {
  name: string
  hosts: number
}

/**
 * One allocated network within a network plan
 */
export interface NetworkPlanAllocation {
  name: string
  network: string
  prefix_length: number
  total_addresses: number
  usable_addresses: number
  first_usable_ip: string
  last_usable_ip: string
}

/**
 * Network plan allocation response
 */
export interface NetworkPlanResponse {
  parent: string
  mode: CloudMode
  allocations: NetworkPlanAllocation[]
}

/**
 * Combined API results from multiple endpoints
 */
export interface ApiResults {
  validate?: ValidateResponse
  private?: PrivateCheckResponse
  cloudflare?: CloudflareCheckResponse
  subnet?: SubnetInfoResponse
}

/**
 * Performance timing for individual API calls
 */
export interface ApiCallTiming {
  call: string
  requestTime: string
  responseTime: string
  duration: number
}

/**
 * Overall performance timing metrics
 */
export interface PerformanceTiming {
  overallDuration: number
  renderingDuration: number
  totalDuration: number
  apiCalls: ApiCallTiming[]
}

/**
 * Complete lookup result with timing information
 */
export interface LookupResult {
  results: ApiResults
  timing: PerformanceTiming
}

/**
 * User information from authentication provider
 */
export interface UserInfo {
  name?: string
  email?: string
  username?: string
}
