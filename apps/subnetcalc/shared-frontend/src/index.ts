/**
 * Shared frontend types and utilities for subnet calculator
 * @packageDocumentation
 */

// Export API utilities and interface
export type { IApiClient } from './api'
export { getApiPrefix, handleFetchError, isIpv6, parseJsonResponse, performCoreLookup } from './api'
// Export authentication utilities
export { TokenManager } from './auth'
// Export all types
export type {
  ApiCallTiming,
  ApiResults,
  CloudflareCheckResponse,
  CloudMode,
  HealthResponse,
  LookupResult,
  NetworkPlanAllocation,
  NetworkPlanRequirement,
  NetworkPlanResponse,
  PerformanceTiming,
  PrivateCheckResponse,
  ProviderName,
  ProviderRangeResponse,
  SubnetInfoResponse,
  UserInfo,
  ValidateResponse,
} from './types'
