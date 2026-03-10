/**
 * Runtime configuration for the React frontend
 * Supports multiple deployment scenarios:
 * - Azure Web App with Easy Auth
 * - Azure Container Apps with Easy Auth
 * - Azure Static Web Apps with Entra ID
 * - AKS with OAuth2 Proxy sidecar
 * - Local development with MSAL
 */

// Runtime configuration (injected by deployment scripts or environment variables)
declare global {
  interface Window {
    RUNTIME_CONFIG?: {
      API_BASE_URL?: string
      AUTH_METHOD?: 'none' | 'easyauth' | 'msal' | 'entraid-swa' | 'jwt' | 'oidc'
      AZURE_CLIENT_ID?: string
      AZURE_TENANT_ID?: string
      AZURE_REDIRECT_URI?: string
      JWT_USERNAME?: string
      JWT_PASSWORD?: string
      EASYAUTH_RESOURCE_ID?: string
      API_PROXY_ENABLED?: string | boolean
      OIDC_AUTHORITY?: string
      OIDC_CLIENT_ID?: string
      OIDC_REDIRECT_URI?: string
      OIDC_AUTO_LOGIN?: string | boolean
      OIDC_PROMPT?: string
      OIDC_FORCE_REAUTH?: string | boolean
      APIM_SUBSCRIPTION_KEY?: string
    }
  }
}

export interface AuthConfig {
  method: 'none' | 'easyauth' | 'msal' | 'entraid-swa' | 'jwt' | 'oidc'
  clientId?: string
  tenantId?: string
  redirectUri?: string
  jwtUsername?: string
  jwtPassword?: string
  easyAuthResourceId?: string
  oidcAuthority?: string
  oidcClientId?: string
  oidcRedirectUri?: string
  oidcAutoLogin?: boolean
  oidcPrompt?: string
  oidcForceReauth?: boolean
}

export interface AppConfig {
  apiBaseUrl: string
  auth: AuthConfig
  stackName: string
  apiProxyEnabled: boolean
  apimSubscriptionKey?: string
  deploymentStage: DeploymentStage
}

export type DeploymentStage = 'DEV' | 'UAT' | 'LOCAL' | 'UNKNOWN'

export function getDeploymentStage(hostname?: string): DeploymentStage {
  if (typeof window === 'undefined') {
    return 'UNKNOWN'
  }

  const host = (hostname ?? window.location.hostname).toLowerCase()

  if (host === 'localhost' || host === '127.0.0.1') {
    return 'LOCAL'
  }

  if (host.includes('.dev.')) {
    return 'DEV'
  }

  if (host.includes('.uat.')) {
    return 'UAT'
  }

  return 'UNKNOWN'
}

/**
 * Detect if running in Azure with Easy Auth enabled
 * Easy Auth sets WEBSITE_HOSTNAME environment variable
 */
export function isAzureEasyAuth(): boolean {
  // Check for Easy Auth headers (presence indicates Easy Auth is active)
  // This would be checked per-request in components
  return (
    typeof window !== 'undefined' &&
    (window.location.hostname.endsWith('.azurewebsites.net') ||
      window.location.hostname.endsWith('.azurecontainerapps.io'))
  )
}

/**
 * Detect if running in Azure Static Web Apps
 */
export function isAzureSWA(): boolean {
  return typeof window !== 'undefined' && window.location.hostname.endsWith('.azurestaticapps.net')
}

/**
 * Get authentication method based on environment
 * Priority: Runtime config > Environment variables > URL detection > Default
 */
export function getAuthMethod(): AuthConfig['method'] {
  // Check runtime config first (injected by deployment scripts)
  if (window.RUNTIME_CONFIG?.AUTH_METHOD) {
    return window.RUNTIME_CONFIG.AUTH_METHOD
  }

  // Check build-time environment variables (takes precedence over hostname detection)
  const envAuthMethod = import.meta.env.VITE_AUTH_METHOD as AuthConfig['method'] | undefined
  if (envAuthMethod) {
    return envAuthMethod
  }

  // Auto-detect based on hostname (only if no explicit config)
  if (isAzureSWA()) {
    return 'entraid-swa'
  }

  if (isAzureEasyAuth()) {
    return 'easyauth'
  }

  // Check if JWT credentials are available
  const jwtUsername = import.meta.env.VITE_JWT_USERNAME
  if (jwtUsername) {
    return 'jwt'
  }

  // Check if MSAL config is available for local development
  const clientId = import.meta.env.VITE_AZURE_CLIENT_ID
  if (clientId) {
    return 'msal'
  }

  // Default: no authentication
  return 'none'
}

/**
 * Get complete application configuration
 */
export function getAppConfig(): AppConfig {
  const runtimeProxyFlag = window.RUNTIME_CONFIG?.API_PROXY_ENABLED ?? import.meta.env.VITE_API_PROXY_ENABLED
  const apiProxyEnabled = `${runtimeProxyFlag ?? ''}`.toLowerCase() === 'true'
  const apimSubscriptionKey =
    window.RUNTIME_CONFIG?.APIM_SUBSCRIPTION_KEY ?? import.meta.env.VITE_APIM_SUBSCRIPTION_KEY ?? ''
  const oidcAutoLoginFlag = window.RUNTIME_CONFIG?.OIDC_AUTO_LOGIN ?? import.meta.env.VITE_OIDC_AUTO_LOGIN
  const oidcAutoLogin = `${oidcAutoLoginFlag ?? ''}`.toLowerCase() === 'true'
  const oidcPrompt = window.RUNTIME_CONFIG?.OIDC_PROMPT ?? import.meta.env.VITE_OIDC_PROMPT
  const oidcForceReauthFlag = window.RUNTIME_CONFIG?.OIDC_FORCE_REAUTH ?? import.meta.env.VITE_OIDC_FORCE_REAUTH
  const oidcForceReauth = `${oidcForceReauthFlag ?? ''}`.toLowerCase() === 'true'

  const authMethod = getAuthMethod()

  // API Base URL priority: Runtime > Environment > Default (relative for SWA)
  let apiBaseUrl =
    window.RUNTIME_CONFIG?.API_BASE_URL ||
    import.meta.env.VITE_API_BASE_URL ||
    import.meta.env.VITE_API_URL ||
    (isAzureSWA() ? '' : 'http://localhost:7071')

  if (apiProxyEnabled) {
    apiBaseUrl = ''
  }

  // MSAL / Easy Auth configuration
  const clientId = window.RUNTIME_CONFIG?.AZURE_CLIENT_ID ?? (import.meta.env.VITE_AZURE_CLIENT_ID || '')
  const tenantId = window.RUNTIME_CONFIG?.AZURE_TENANT_ID ?? (import.meta.env.VITE_AZURE_TENANT_ID || 'common')
  const redirectUri =
    window.RUNTIME_CONFIG?.AZURE_REDIRECT_URI ?? (import.meta.env.VITE_AZURE_REDIRECT_URI || window.location.origin)
  const easyAuthResourceId =
    window.RUNTIME_CONFIG?.EASYAUTH_RESOURCE_ID ?? (import.meta.env.VITE_EASYAUTH_RESOURCE_ID || '')

  // JWT configuration (only used when authMethod === 'jwt')
  const jwtUsername = window.RUNTIME_CONFIG?.JWT_USERNAME ?? (import.meta.env.VITE_JWT_USERNAME || '')
  const jwtPassword = window.RUNTIME_CONFIG?.JWT_PASSWORD ?? (import.meta.env.VITE_JWT_PASSWORD || '')

  // Determine stack name for display
  let stackName = 'React + TypeScript + Vite'
  if (authMethod === 'easyauth') {
    stackName += ' + Azure Web App (Easy Auth)'
  } else if (authMethod === 'entraid-swa') {
    stackName += ' + Static Web Apps (Entra ID)'
  } else if (authMethod === 'msal') {
    stackName += ' (MSAL Local Dev)'
  } else if (authMethod === 'jwt') {
    stackName += ' + Azure Function (JWT)'
  }

  return {
    apiBaseUrl,
    auth: {
      method: authMethod,
      clientId,
      tenantId,
      redirectUri,
      jwtUsername,
      jwtPassword,
      easyAuthResourceId,
      oidcAutoLogin,
      oidcPrompt: oidcPrompt || undefined,
      oidcForceReauth,
    },
    stackName,
    apiProxyEnabled,
    apimSubscriptionKey,
    deploymentStage: getDeploymentStage(),
  }
}

// Export lazy-loaded singleton config instance
let _cachedConfig: AppConfig | null = null

export function getConfig(): AppConfig {
  if (!_cachedConfig) {
    // Priority: window.RUNTIME_CONFIG (injected by server.js) > build-time env > defaults
    const authMethod = (window.RUNTIME_CONFIG?.AUTH_METHOD || getAuthMethod()) as AuthConfig['method']

    let apiBaseUrl =
      window.RUNTIME_CONFIG?.API_BASE_URL ||
      import.meta.env.VITE_API_BASE_URL ||
      import.meta.env.VITE_API_URL ||
      (isAzureSWA() ? '' : 'http://localhost:7071')

    const runtimeProxyFlag = window.RUNTIME_CONFIG?.API_PROXY_ENABLED ?? import.meta.env.VITE_API_PROXY_ENABLED
    const apiProxyEnabled = `${runtimeProxyFlag ?? ''}`.toLowerCase() === 'true'
    const apimSubscriptionKey =
      window.RUNTIME_CONFIG?.APIM_SUBSCRIPTION_KEY ?? import.meta.env.VITE_APIM_SUBSCRIPTION_KEY ?? ''
    const oidcAutoLoginFlag = window.RUNTIME_CONFIG?.OIDC_AUTO_LOGIN ?? import.meta.env.VITE_OIDC_AUTO_LOGIN
    const oidcAutoLogin = `${oidcAutoLoginFlag ?? ''}`.toLowerCase() === 'true'
    const oidcPrompt = window.RUNTIME_CONFIG?.OIDC_PROMPT ?? import.meta.env.VITE_OIDC_PROMPT
    const oidcForceReauthFlag = window.RUNTIME_CONFIG?.OIDC_FORCE_REAUTH ?? import.meta.env.VITE_OIDC_FORCE_REAUTH
    const oidcForceReauth = `${oidcForceReauthFlag ?? ''}`.toLowerCase() === 'true'

    if (apiProxyEnabled) {
      apiBaseUrl = ''
    }

    // Determine stack name suffix based on auth method
    const authSuffix =
      {
        jwt: ' + JWT',
        easyauth: ' + Easy Auth',
        'entraid-swa': ' + SWA',
        msal: '',
        oidc: ' + OIDC (Keycloak)',
        none: '',
      }[authMethod] || ''

    _cachedConfig = {
      apiBaseUrl,
      auth: {
        method: authMethod,
        clientId: window.RUNTIME_CONFIG?.AZURE_CLIENT_ID ?? (import.meta.env.VITE_AZURE_CLIENT_ID || ''),
        tenantId: window.RUNTIME_CONFIG?.AZURE_TENANT_ID ?? (import.meta.env.VITE_AZURE_TENANT_ID || 'common'),
        redirectUri:
          window.RUNTIME_CONFIG?.AZURE_REDIRECT_URI ??
          (import.meta.env.VITE_AZURE_REDIRECT_URI || window.location.origin),
        jwtUsername: window.RUNTIME_CONFIG?.JWT_USERNAME ?? (import.meta.env.VITE_JWT_USERNAME || ''),
        jwtPassword: window.RUNTIME_CONFIG?.JWT_PASSWORD ?? (import.meta.env.VITE_JWT_PASSWORD || ''),
        easyAuthResourceId:
          window.RUNTIME_CONFIG?.EASYAUTH_RESOURCE_ID ?? (import.meta.env.VITE_EASYAUTH_RESOURCE_ID || ''),
        oidcAuthority: window.RUNTIME_CONFIG?.OIDC_AUTHORITY ?? (import.meta.env.VITE_OIDC_AUTHORITY || ''),
        oidcClientId: window.RUNTIME_CONFIG?.OIDC_CLIENT_ID ?? (import.meta.env.VITE_OIDC_CLIENT_ID || ''),
        oidcRedirectUri:
          window.RUNTIME_CONFIG?.OIDC_REDIRECT_URI ??
          (import.meta.env.VITE_OIDC_REDIRECT_URI || window.location.origin),
        oidcAutoLogin,
        oidcPrompt: oidcPrompt || undefined,
        oidcForceReauth,
      },
      stackName: `React + TypeScript + Vite${authSuffix}`,
      apiProxyEnabled,
      apimSubscriptionKey,
      deploymentStage: getDeploymentStage(),
    }
  }
  return _cachedConfig
}

// For backward compatibility
export const APP_CONFIG = new Proxy({} as AppConfig, {
  get(_target, prop) {
    return getConfig()[prop as keyof AppConfig]
  },
})
