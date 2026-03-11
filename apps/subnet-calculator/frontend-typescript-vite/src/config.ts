// Runtime configuration (injected by deployment scripts)
// Deployment scripts can set window.RUNTIME_CONFIG before loading this module
declare global {
  interface Window {
    API_BASE_URL?: string
    AUTH_ENABLED?: string
    JWT_USERNAME?: string
    JWT_PASSWORD?: string
  }
}

export interface NetworkHop {
  label: string
  detail: string
  role?: string
}

export const API_CONFIG = {
  // Priority: Runtime config (window) > Build-time env (import.meta.env) > Default (empty for SWA proxy)
  baseUrl: (typeof window !== 'undefined' && window.API_BASE_URL) || import.meta.env.VITE_API_URL || '',
  auth: {
    enabled:
      (typeof window !== 'undefined' && window.AUTH_ENABLED === 'true') || import.meta.env.VITE_AUTH_ENABLED === 'true',
    username: (typeof window !== 'undefined' && window.JWT_USERNAME) || import.meta.env.VITE_JWT_USERNAME || '',
    password: (typeof window !== 'undefined' && window.JWT_PASSWORD) || import.meta.env.VITE_JWT_PASSWORD || '',
  },
  showNetworkPath: import.meta.env.VITE_SHOW_NETWORK_PATH === 'true',
  networkDiagnostics: {
    primaryLabel: import.meta.env.VITE_NETWORK_DIAGNOSTICS_LABEL || 'Live Diagnostics',
    secondaryLabel: import.meta.env.VITE_SECONDARY_NETWORK_DIAGNOSTICS_LABEL || '',
    secondaryPath: import.meta.env.VITE_SECONDARY_NETWORK_DIAGNOSTICS_PATH || '',
  },
  apiStatus: {
    frontendLabel: import.meta.env.VITE_FRONTEND_STATUS_LABEL || 'Frontend origin',
    ingressLabel: import.meta.env.VITE_API_INGRESS_STATUS_LABEL || 'API ingress',
    backendPathLabel: import.meta.env.VITE_BACKEND_PATH_STATUS_LABEL || 'Backend path',
    backendPathDetail: import.meta.env.VITE_BACKEND_PATH_STATUS_DETAIL || '',
  },
  paths: {
    health: '/api/v1/health',
    // Both backends use consistent /ipv4/ endpoints
    validate: '/api/v1/ipv4/validate',
    checkPrivate: '/api/v1/ipv4/check-private',
    checkCloudflare: '/api/v1/ipv4/check-cloudflare',
    subnetInfo: '/api/v1/ipv4/subnet-info',
    networkDiagnostics: '/api/v1/network/diagnostics',
  },
}

function isNetworkHop(value: unknown): value is NetworkHop {
  if (typeof value !== 'object' || value === null) {
    return false
  }

  const hop = value as Partial<NetworkHop>
  return (
    typeof hop.label === 'string' &&
    typeof hop.detail === 'string' &&
    (hop.role === undefined || typeof hop.role === 'string')
  )
}

export function getNetworkHops(): NetworkHop[] | null {
  if (!API_CONFIG.showNetworkPath) {
    return null
  }

  const customHops = import.meta.env.VITE_NETWORK_HOPS
  if (customHops) {
    try {
      const parsed = JSON.parse(customHops) as unknown
      if (Array.isArray(parsed) && parsed.every((hop) => isNetworkHop(hop))) {
        return parsed
      }
      return null
    } catch {
      return null
    }
  }

  return [
    { label: 'Browser', detail: 'localhost:8081' },
    { label: 'cloud1 nginx', detail: '127.0.0.1:8080 (Lima guest target)', role: 'Frontend + reverse proxy' },
    {
      label: 'WireGuard SD-WAN',
      detail: '172.16.11.2:443 (mTLS)',
      role: 'Encrypted cross-cloud tunnel (wg0: 192.168.1.1 ↔ 192.168.1.2)',
    },
    { label: 'cloud2 nginx', detail: 'Inbound gateway', role: 'mTLS termination + proxy' },
    { label: 'cloud2 FastAPI', detail: '10.10.1.4:8000', role: 'Subnet Calculator API (JWT auth)' },
  ]
}

/**
 * Check if we're running in Azure Static Web Apps (legacy detection)
 *
 * IMPORTANT: This only detects default .azurestaticapps.net domains.
 * For custom domains, VITE_AUTH_METHOD must be set explicitly during build.
 * All deployment scripts (azure-stack-*.sh) should set VITE_AUTH_METHOD.
 */
export function isRunningInSWA(): boolean {
  return typeof window !== 'undefined' && window.location.hostname.endsWith('.azurestaticapps.net')
}

/**
 * Determine which auth method is active
 */
export function getAuthMethod(): 'none' | 'jwt' | 'entraid' | 'oidc' {
  // Check for explicit auth method from build-time config
  const explicitMethod = import.meta.env.VITE_AUTH_METHOD as 'none' | 'jwt' | 'entraid' | 'oidc' | undefined
  if (explicitMethod) {
    return explicitMethod
  }

  // Fallback to legacy detection for backwards compatibility
  if (!API_CONFIG.auth.enabled) {
    return 'none'
  }

  // In SWA context, use Entra ID
  if (isRunningInSWA()) {
    return 'entraid'
  }

  // Otherwise assume OIDC (local kind cluster uses Dex)
  return 'oidc'
}

/**
 * Get stack description based on API URL and auth configuration
 */
export function getStackDescription(): string {
  const authMethod = getAuthMethod()
  const apiUrl = API_CONFIG.baseUrl

  // Check for Azure Function indicators (relative paths or specific ports)
  const isAzureFunction = apiUrl === '' || apiUrl === '/' || apiUrl.includes(':7071') || apiUrl.includes(':8080')

  // When running in SWA with Entra ID
  if (authMethod === 'entraid') {
    return 'TypeScript + Vite + SWA (Entra ID)'
  }

  if (isAzureFunction && authMethod === 'jwt') {
    return 'TypeScript + Vite + Azure Function (JWT)'
  }

  if (isAzureFunction) {
    return 'TypeScript + Vite + Azure Function'
  }

  return 'TypeScript + Vite + Container App'
}
