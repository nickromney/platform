// Runtime configuration (injected by deployment scripts or container startup)
declare global {
  interface Window {
    RUNTIME_CONFIG?: {
      API_BASE_URL?: string
      AUTH_METHOD?: 'none' | 'jwt' | 'entraid' | 'gateway' | 'oidc'
      AUTH_ENABLED?: string | boolean
      APIM_SUBSCRIPTION_KEY?: string
      OIDC_AUTHORITY?: string
      OIDC_CLIENT_ID?: string
      OIDC_REDIRECT_URI?: string
      OIDC_AUTO_LOGIN?: string | boolean
      OIDC_PROMPT?: string
      OIDC_FORCE_REAUTH?: string | boolean
      JWT_USERNAME?: string
      JWT_PASSWORD?: string
      SHOW_NETWORK_PATH?: string | boolean
      NETWORK_HOPS?: string
      NETWORK_DIAGNOSTICS_LABEL?: string
      SECONDARY_NETWORK_DIAGNOSTICS_LABEL?: string
      SECONDARY_NETWORK_DIAGNOSTICS_PATH?: string
      FRONTEND_STATUS_LABEL?: string
      API_INGRESS_STATUS_LABEL?: string
      BACKEND_PATH_STATUS_LABEL?: string
      BACKEND_PATH_STATUS_DETAIL?: string
      STACK_DESCRIPTION?: string
    }
    API_BASE_URL?: string
    AUTH_ENABLED?: string
    JWT_USERNAME?: string
    JWT_PASSWORD?: string
  }
}

function getRuntimeConfig() {
  if (typeof window === 'undefined') {
    return undefined
  }

  if (window.RUNTIME_CONFIG) {
    return window.RUNTIME_CONFIG
  }

  return {
    API_BASE_URL: window.API_BASE_URL,
    AUTH_ENABLED: window.AUTH_ENABLED,
    JWT_USERNAME: window.JWT_USERNAME,
    JWT_PASSWORD: window.JWT_PASSWORD,
  }
}

const runtimeConfig = getRuntimeConfig()
const authEnabledFlag =
  `${runtimeConfig?.AUTH_ENABLED ?? import.meta.env.VITE_AUTH_ENABLED ?? 'false'}`.toLowerCase() === 'true'

export interface NetworkHop {
  label: string
  detail: string
  role?: string
}

export interface OidcConfig {
  authority: string
  clientId: string
  redirectUri: string
  autoLogin: boolean
  prompt?: string
  forceReauth: boolean
}

function parseBooleanFlag(value: unknown, fallback = false): boolean {
  if (value === undefined || value === null || value === '') {
    return fallback
  }

  return `${value}`.toLowerCase() === 'true'
}

export const API_CONFIG = {
  // Priority: Runtime config (window) > Build-time env (import.meta.env) > Default (empty for SWA proxy)
  baseUrl: runtimeConfig?.API_BASE_URL || import.meta.env.VITE_API_URL || '',
  apimSubscriptionKey: runtimeConfig?.APIM_SUBSCRIPTION_KEY || import.meta.env.VITE_APIM_SUBSCRIPTION_KEY || '',
  auth: {
    enabled: getAuthMethod() === 'jwt',
    username: runtimeConfig?.JWT_USERNAME || import.meta.env.VITE_JWT_USERNAME || '',
    password: runtimeConfig?.JWT_PASSWORD || import.meta.env.VITE_JWT_PASSWORD || '',
  },
  showNetworkPath: parseBooleanFlag(runtimeConfig?.SHOW_NETWORK_PATH ?? import.meta.env.VITE_SHOW_NETWORK_PATH),
  networkDiagnostics: {
    primaryLabel:
      runtimeConfig?.NETWORK_DIAGNOSTICS_LABEL || import.meta.env.VITE_NETWORK_DIAGNOSTICS_LABEL || 'Live Diagnostics',
    secondaryLabel:
      runtimeConfig?.SECONDARY_NETWORK_DIAGNOSTICS_LABEL ||
      import.meta.env.VITE_SECONDARY_NETWORK_DIAGNOSTICS_LABEL ||
      '',
    secondaryPath:
      runtimeConfig?.SECONDARY_NETWORK_DIAGNOSTICS_PATH ||
      import.meta.env.VITE_SECONDARY_NETWORK_DIAGNOSTICS_PATH ||
      '',
  },
  apiStatus: {
    frontendLabel:
      runtimeConfig?.FRONTEND_STATUS_LABEL || import.meta.env.VITE_FRONTEND_STATUS_LABEL || 'Frontend origin',
    ingressLabel:
      runtimeConfig?.API_INGRESS_STATUS_LABEL || import.meta.env.VITE_API_INGRESS_STATUS_LABEL || 'API ingress',
    backendPathLabel:
      runtimeConfig?.BACKEND_PATH_STATUS_LABEL || import.meta.env.VITE_BACKEND_PATH_STATUS_LABEL || 'Backend path',
    backendPathDetail:
      runtimeConfig?.BACKEND_PATH_STATUS_DETAIL || import.meta.env.VITE_BACKEND_PATH_STATUS_DETAIL || '',
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

  const customHops = runtimeConfig?.NETWORK_HOPS || import.meta.env.VITE_NETWORK_HOPS
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
      label: 'WireGuard overlay',
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
 * For custom domains, set AUTH_METHOD in runtime config.
 */
export function isRunningInSWA(): boolean {
  return typeof window !== 'undefined' && window.location.hostname.endsWith('.azurestaticapps.net')
}

/**
 * Determine which auth method is active
 */
export function getAuthMethod(): 'none' | 'jwt' | 'entraid' | 'gateway' | 'oidc' {
  const explicitMethod =
    runtimeConfig?.AUTH_METHOD ||
    (import.meta.env.VITE_AUTH_METHOD as 'none' | 'jwt' | 'entraid' | 'gateway' | 'oidc' | undefined)
  if (explicitMethod) {
    return explicitMethod
  }

  // Fallback to legacy detection for backwards compatibility
  if (!authEnabledFlag) {
    return 'none'
  }

  // In SWA context, use Entra ID
  if (isRunningInSWA()) {
    return 'entraid'
  }

  // Otherwise assume OIDC (local kind cluster uses Dex)
  return 'oidc'
}

export function getOidcConfig(): OidcConfig {
  return {
    authority: runtimeConfig?.OIDC_AUTHORITY || import.meta.env.VITE_OIDC_AUTHORITY || '',
    clientId: runtimeConfig?.OIDC_CLIENT_ID || import.meta.env.VITE_OIDC_CLIENT_ID || '',
    redirectUri: runtimeConfig?.OIDC_REDIRECT_URI || import.meta.env.VITE_OIDC_REDIRECT_URI || window.location.origin,
    autoLogin: parseBooleanFlag(runtimeConfig?.OIDC_AUTO_LOGIN ?? import.meta.env.VITE_OIDC_AUTO_LOGIN),
    prompt: runtimeConfig?.OIDC_PROMPT || import.meta.env.VITE_OIDC_PROMPT || undefined,
    forceReauth: parseBooleanFlag(runtimeConfig?.OIDC_FORCE_REAUTH ?? import.meta.env.VITE_OIDC_FORCE_REAUTH),
  }
}

/**
 * Get stack description based on API URL and auth configuration
 */
export function getStackDescription(): string {
  const configuredDescription = runtimeConfig?.STACK_DESCRIPTION || import.meta.env.VITE_STACK_DESCRIPTION
  if (configuredDescription) {
    return configuredDescription
  }

  const authMethod = getAuthMethod()
  const apiUrl = API_CONFIG.baseUrl

  // Check for Azure Function indicators (relative paths or specific ports)
  const isAzureFunction = apiUrl === '' || apiUrl === '/' || apiUrl.includes(':7071') || apiUrl.includes(':8080')

  // When running in SWA with Entra ID
  if (authMethod === 'entraid' && isRunningInSWA()) {
    return 'TypeScript + Vite + SWA (Entra ID)'
  }

  if (authMethod === 'gateway') {
    return 'TypeScript + Vite + OAuth2 Proxy'
  }

  if (authMethod === 'oidc') {
    return 'TypeScript + Vite + OIDC'
  }

  if (authMethod === 'entraid') {
    return 'TypeScript + Vite + Entra ID'
  }

  if (isAzureFunction && authMethod === 'jwt') {
    return 'TypeScript + Vite + Azure Function (JWT)'
  }

  if (isAzureFunction) {
    return 'TypeScript + Vite + Azure Function'
  }

  return 'TypeScript + Vite + Container App'
}
