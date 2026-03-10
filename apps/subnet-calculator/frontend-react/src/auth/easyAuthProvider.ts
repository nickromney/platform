/**
 * Easy Auth Provider
 * Handles Azure App Service / Container Apps Easy Auth
 * Easy Auth injects user information via HTTP headers
 */

import type { UserInfo } from '../types'

interface EasyAuthClaim {
  typ: string
  val: string
}

type TokenLike =
  | string
  | {
      value?: string
      token?: string
      expires_on?: string | number
      expiresOn?: string | number
    }

interface EasyAuthSession {
  access_token?: TokenLike
  id_token?: TokenLike
  authentication_token?: TokenLike
  expires_on?: string
  user_id?: string
  provider_name?: string
  claims?: EasyAuthClaim[]
  user_claims?: EasyAuthClaim[]
}

interface CachedSession {
  session: EasyAuthSession
  expiresAt?: number
}

const tokenCache = new Map<string, CachedSession>()
let cachedSession: CachedSession | null = null

function isAuthenticatedSession(session: EasyAuthSession): boolean {
  const userId = session.user_id?.trim() || ''
  const claimList = session.claims || session.user_claims || []
  const hasNonEmptyClaim = claimList.some(claim => {
    const typ = claim.typ?.trim() || ''
    const val = claim.val?.trim() || ''
    return typ.length > 0 && val.length > 0
  })

  const candidates: TokenLike[] = [session.authentication_token, session.access_token, session.id_token].filter(
    (token): token is TokenLike => Boolean(token)
  )
  const hasToken = candidates.some(candidate => {
    const normalized = normalizeToken(candidate)
    return Boolean(normalized?.token)
  })

  return userId.length > 0 || hasNonEmptyClaim || hasToken
}

/**
 * Parse Easy Auth principal from X-MS-CLIENT-PRINCIPAL header
 * This would typically be done server-side, but for client-side SPAs
 * we can make a call to /.auth/me endpoint
 */
async function fetchEasyAuthSession(forceRefresh = false): Promise<EasyAuthSession | null> {
  if (!forceRefresh && cachedSession) {
    if (!cachedSession.expiresAt || cachedSession.expiresAt - 60_000 > Date.now()) {
      return cachedSession.session
    }
  }

  try {
    const response = await fetch('/.auth/me', {
      credentials: 'include',
    })

    if (!response.ok) {
      return null
    }

    const data = await response.json()

    if (!Array.isArray(data) || data.length === 0) {
      return null
    }

    const session: EasyAuthSession = data[0]

    if (!isAuthenticatedSession(session)) {
      cachedSession = null
      return null
    }

    const expiresOn = session.expires_on ? Number(session.expires_on) * 1000 : undefined
    cachedSession = {
      session,
      expiresAt: expiresOn,
    }

    return session
  } catch (error) {
    console.error('Error fetching Easy Auth session:', error)
    return null
  }
}

export async function getEasyAuthUser(): Promise<UserInfo | null> {
  try {
    const session = await fetchEasyAuthSession()
    if (!session) {
      return null
    }

    if (!isAuthenticatedSession(session)) {
      return null
    }

    const claimList = session.claims || session.user_claims || []

    // Extract claims into a map for easier access
    const claimMap: Record<string, string> = {}
    for (const claim of claimList) {
      claimMap[claim.typ] = claim.val
    }

    // Extract user information
    return {
      name: claimMap.name || session.user_id || 'User',
      email: claimMap.email || claimMap.preferred_username,
      username: session.user_id,
    }
  } catch (error) {
    console.error('Error fetching Easy Auth user info:', error)
    return null
  }
}

export interface EasyAuthAccessToken {
  token: string
  source: 'authentication_token' | 'access_token' | 'id_token'
  expiresAt?: number
}

export async function getEasyAuthAccessToken(
  forceRefresh = false,
  resourceId?: string
): Promise<EasyAuthAccessToken | null> {
  if (resourceId) {
    const cacheKey = resourceId
    const cached = tokenCache.get(cacheKey)
    if (!forceRefresh && cached && (!cached.expiresAt || cached.expiresAt - 60_000 > Date.now())) {
      return { token: cached.session.access_token as string, source: 'access_token', expiresAt: cached.expiresAt }
    }

    const token = await fetchResourceToken(resourceId)
    if (token) {
      tokenCache.set(cacheKey, { session: { access_token: token.token }, expiresAt: token.expiresAt })
      return token
    }
    // fall back to default session if resource token not available
  }

  const session = await fetchEasyAuthSession(forceRefresh)
  if (!session) {
    return null
  }

  const candidates: Array<{ value?: TokenLike; source: EasyAuthAccessToken['source'] }> = [
    { value: session.authentication_token, source: 'authentication_token' },
    { value: session.access_token, source: 'access_token' },
    { value: session.id_token, source: 'id_token' },
  ]

  for (const candidate of candidates) {
    const normalized = normalizeToken(candidate.value)
    if (normalized) {
      return {
        token: normalized.token,
        source: candidate.source,
        expiresAt: normalized.expiresAt ?? (session.expires_on ? Number(session.expires_on) * 1000 : undefined),
      }
    }
  }

  return null
}

async function fetchResourceToken(resourceId: string): Promise<EasyAuthAccessToken | null> {
  const attempts = [
    `/.auth/refresh?resource=${encodeURIComponent(resourceId)}`,
    `/.auth/refresh?scopes=${encodeURIComponent(`${resourceId}/user_impersonation`)}`,
    `/.auth/refresh?scopes=${encodeURIComponent(`${resourceId}/.default`)}`,
  ]

  for (const url of attempts) {
    try {
      const response = await fetch(url, { credentials: 'include' })
      if (!response.ok) {
        continue
      }
      const data = await response.json()
      const normalized = normalizeToken(data?.access_token || data?.authentication_token || data?.id_token)
      if (!normalized) {
        continue
      }
      return {
        token: normalized.token,
        source: 'access_token',
        expiresAt: normalized.expiresAt,
      }
    } catch (error) {
      console.error(`Error refreshing Easy Auth token via ${url}:`, error)
    }
  }

  return null
}

function normalizeToken(input?: TokenLike): { token: string; expiresAt?: number } | null {
  if (!input) {
    return null
  }

  if (typeof input === 'string') {
    return { token: input }
  }

  const token = input.token || input.value
  if (!token) {
    return null
  }

  const expiresRaw = input.expires_on ?? input.expiresOn
  const expiresAt =
    typeof expiresRaw === 'number' ? expiresRaw * 1000 : expiresRaw ? Number(expiresRaw) * 1000 : undefined
  return { token, expiresAt }
}

/**
 * Check if user is authenticated with Easy Auth
 */
export async function isEasyAuthAuthenticated(): Promise<boolean> {
  const session = await fetchEasyAuthSession()
  return session !== null
}

/**
 * Initiate Easy Auth login
 */
export function easyAuthLogin(provider: string = 'aad'): void {
  window.location.href = `/.auth/login/${provider}?post_login_redirect_uri=${encodeURIComponent(window.location.href)}`
}

/**
 * Initiate Easy Auth logout
 */
export function easyAuthLogout(): void {
  window.location.href = `/.auth/logout?post_logout_redirect_uri=${encodeURIComponent(window.location.origin)}`
}
