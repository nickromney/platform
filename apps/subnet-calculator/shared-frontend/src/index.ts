/**
 * Shared frontend types and utilities for subnet calculator
 * @packageDocumentation
 */

// Export all types
export type {
  CloudMode,
  HealthResponse,
  ValidateResponse,
  PrivateCheckResponse,
  CloudflareCheckResponse,
  SubnetInfoResponse,
  ApiResults,
  ApiCallTiming,
  PerformanceTiming,
  LookupResult,
  UserInfo,
} from './types'

// Export API utilities and interface
export type { IApiClient } from './api'
export { isIpv6, getApiPrefix, handleFetchError, parseJsonResponse } from './api'

// Export authentication utilities
export { TokenManager } from './auth'
