import { getAuthMethod } from './config'

/**
 * Azure Static Web Apps Entra ID Authentication
 *
 * Handles authentication via SWA's built-in Entra ID integration.
 * This module only activates when:
 * 1. VITE_AUTH_ENABLED=true
 * 2. Running in Azure Static Web Apps context (detected by hostname)
 *
 * SWA provides these endpoints automatically:
 * - /.auth/login/aad - Login with Entra ID
 * - /.auth/logout - Logout
 * - /.auth/me - Get current user info
 */

export interface ClientPrincipal {
  identityProvider: string
  userId: string
  userDetails: string // Usually the email
  userRoles: string[]
  claims?: Array<{
    typ: string
    val: string
  }>
}

export interface AuthResponse {
  clientPrincipal: ClientPrincipal | null
}

/**
 * Check if we're running in Azure Static Web Apps (legacy detection)
 *
 * IMPORTANT: This only detects default .azurestaticapps.net domains.
 * For custom domains, set AUTH_METHOD in runtime config.
 */
export function isRunningInSWA(): boolean {
  // SWA domains end with .azurestaticapps.net
  return typeof window !== 'undefined' && window.location.hostname.endsWith('.azurestaticapps.net')
}

/**
 * Check if Entra ID auth should be used.
 * Prefer explicit runtime configuration, then fall back to hostname detection.
 */
export function useEntraIdAuth(): boolean {
  if (getAuthMethod() === 'entraid') {
    return true
  }

  return false
}

/**
 * Get the current authenticated user from SWA
 */
export async function getCurrentUser(): Promise<ClientPrincipal | null> {
  if (!useEntraIdAuth()) {
    return null
  }

  try {
    const response = await fetch('/.auth/me', {
      headers: {
        Accept: 'application/json',
      },
    })

    if (!response.ok) {
      console.error('Failed to fetch user info:', response.status)
      return null
    }

    const data: AuthResponse = await response.json()
    return data.clientPrincipal
  } catch (error) {
    console.error('Error fetching user info:', error)
    return null
  }
}

/**
 * Redirect to Entra ID login
 */
export function login(returnUrl?: string): void {
  const loginUrl = returnUrl
    ? `/.auth/login/aad?post_login_redirect_uri=${encodeURIComponent(returnUrl)}`
    : '/.auth/login/aad'

  window.location.href = loginUrl
}

/**
 * Logout from SWA
 */
export function logout(returnUrl?: string): void {
  const logoutUrl = returnUrl
    ? `/.auth/logout?post_logout_redirect_uri=${encodeURIComponent(returnUrl)}`
    : '/.auth/logout'

  window.location.href = logoutUrl
}

/**
 * Get display name for the user
 */
export function getUserDisplayName(user: ClientPrincipal): string {
  // Try to get name from claims first
  if (user.claims) {
    const nameClaim = user.claims.find((c) => c.typ === 'name')
    if (nameClaim) {
      return nameClaim.val
    }
  }

  // Fall back to userDetails (usually email)
  if (user.userDetails) {
    return user.userDetails
  }

  // Last resort, use userId
  return user.userId
}

/**
 * Check if user has a specific role
 */
export function userHasRole(user: ClientPrincipal, role: string): boolean {
  return user.userRoles.includes(role)
}
