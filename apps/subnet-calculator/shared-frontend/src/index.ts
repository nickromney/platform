/**
 * Shared frontend types and utilities for subnet calculator
 * @packageDocumentation
 */

// Export API utilities and interface
export type { IApiClient } from './api'
export { getApiPrefix, handleFetchError, isIpv6, parseJsonResponse } from './api'
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
  PerformanceTiming,
  PrivateCheckResponse,
  SubnetInfoResponse,
  UserInfo,
  ValidateResponse,
} from './types'
