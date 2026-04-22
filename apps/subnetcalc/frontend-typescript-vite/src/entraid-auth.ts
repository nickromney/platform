import { getAuthMethod } from './config'

/**
 * Browser-visible auth gateway helpers
 *
 * Handles authentication via SWA's built-in Entra ID integration or any
 * frontend gateway that exposes the same `/.auth/*` surface.
 *
 * These endpoints are expected:
 * - /.auth/login/aad (or another /.auth/login/* alias) - Login
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

type TokenLike =
  | string
  | {
      value?: string
      token?: string
      expires_on?: string | number
      expiresOn?: string | number
    }

interface EasyAuthPrincipal {
  provider_name?: string
  user_id?: string
  user_roles?: string[]
  userRoles?: string[]
  access_token?: TokenLike
  authentication_token?: TokenLike
  id_token?: TokenLike
  claims?: ClientPrincipal['claims']
  user_claims?: ClientPrincipal['claims']
}

let cachedAuthPayload: unknown

function normalizeToken(input?: TokenLike): string | null {
  if (!input) {
    return null
  }

  if (typeof input === 'string') {
    return input
  }

  return input.token || input.value || null
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  const parts = token.split('.')
  if (parts.length < 2) {
    return null
  }

  try {
    const payload = parts[1]
    if (!payload) {
      return null
    }

    const normalized = payload.replaceAll('-', '+').replaceAll('_', '/')
    const padding = (4 - (normalized.length % 4)) % 4
    const base64 = normalized.padEnd(normalized.length + padding, '=')
    return JSON.parse(atob(base64)) as Record<string, unknown>
  } catch {
    return null
  }
}

function isIdentityToken(token: string): boolean {
  const payload = decodeJwtPayload(token)
  return payload?.typ === 'ID'
}

function selectGatewayApiToken(session: EasyAuthPrincipal): string | null {
  const candidates = [normalizeToken(session.authentication_token), normalizeToken(session.access_token)]

  for (const token of candidates) {
    if (!token || isIdentityToken(token)) {
      continue
    }

    return token
  }

  return null
}

function normalizeClientPrincipal(payload: unknown): ClientPrincipal | null {
  if (!payload || typeof payload !== 'object') {
    return null
  }

  if ('clientPrincipal' in payload) {
    const principal = (payload as AuthResponse).clientPrincipal
    return principal ?? null
  }

  if (!Array.isArray(payload) || payload.length === 0) {
    return null
  }

  const session = payload[0] as EasyAuthPrincipal | undefined
  if (!session) {
    return null
  }

  const claims = session.claims || session.user_claims || []
  const emailClaim = claims.find((claim) => claim.typ === 'email' || claim.typ === 'preferred_username')
  const nameClaim = claims.find((claim) => claim.typ === 'name')
  const userId = session.user_id || emailClaim?.val || ''

  if (!userId && !nameClaim?.val) {
    return null
  }

  return {
    identityProvider: session.provider_name || 'proxy',
    userId,
    userDetails: emailClaim?.val || nameClaim?.val || userId,
    userRoles: session.userRoles || session.user_roles || [],
    claims,
  }
}

async function fetchAuthPayload(forceRefresh = false): Promise<unknown> {
  if (!forceRefresh && cachedAuthPayload !== undefined) {
    return cachedAuthPayload
  }

  const response = await fetch('/.auth/me', {
    headers: {
      Accept: 'application/json',
    },
  })

  if (!response.ok) {
    throw new Error(`Failed to fetch user info: ${response.status}`)
  }

  const data = await response.json()
  cachedAuthPayload = data
  return data
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
  const authMethod = getAuthMethod()
  return authMethod === 'entraid' || authMethod === 'gateway'
}

/**
 * Get the current authenticated user from SWA
 */
export async function getCurrentUser(): Promise<ClientPrincipal | null> {
  if (!useEntraIdAuth()) {
    return null
  }

  try {
    const data = await fetchAuthPayload()
    return normalizeClientPrincipal(data)
  } catch (error) {
    console.error('Error fetching user info:', error)
    return null
  }
}

export async function getGatewayAccessToken(forceRefresh = false): Promise<string | null> {
  if (getAuthMethod() !== 'gateway') {
    return null
  }

  try {
    const payload = await fetchAuthPayload(forceRefresh)
    if (!Array.isArray(payload) || payload.length === 0) {
      return null
    }

    const session = payload[0] as EasyAuthPrincipal
    return selectGatewayApiToken(session)
  } catch (error) {
    console.error('Error fetching gateway access token:', error)
    return null
  }
}

/**
 * Redirect to login using the auth surface for the active frontend mode.
 */
export function login(authMethod: 'entraid' | 'gateway', returnUrl?: string): void {
  const loginPath = authMethod === 'gateway' ? '/.auth/login/sso' : '/.auth/login/aad'
  const loginUrl = returnUrl ? `${loginPath}?post_login_redirect_uri=${encodeURIComponent(returnUrl)}` : loginPath

  window.location.href = loginUrl
}

/**
 * Logout from SWA
 */
export function logout(returnUrl?: string): void {
  cachedAuthPayload = undefined
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
