/**
 * Type definitions for TypeScript frontend
 * Re-exports from shared package for backwards compatibility
 */

import type { LookupResult } from '@subnet-calculator/shared-frontend'

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
  ValidateResponse,
} from '@subnet-calculator/shared-frontend'

export interface TunnelPeerDiagnostics {
  public_key: string
  endpoint_ip: string | null
  endpoint_port: number | null
  allowed_ips: string[]
  tunnel_peer_ip: string | null
  latest_handshake_unix: number | null
}

export interface NetworkDiagnosticsResponse {
  viewpoint?: string
  target: string
  generated_at: string
  dns: {
    resolver: string
    answers: string[]
    command: string
    exit_code: number
    raw_output: string
  }
  traceroute: {
    command: string
    exit_code: number
    hops: string[]
    hop_count: number
    raw_output: string
  }
  tunnel: {
    interface: string
    local_tunnel_ip: string | null
    peer_tunnel_ips: string[]
    peer_endpoint_ips: string[]
    peers: TunnelPeerDiagnostics[]
  }
}

export interface LookupResultWithDiagnostics extends LookupResult {
  networkDiagnostics?: NetworkDiagnosticsResponse | null
  secondaryNetworkDiagnostics?: NetworkDiagnosticsResponse | null
}
