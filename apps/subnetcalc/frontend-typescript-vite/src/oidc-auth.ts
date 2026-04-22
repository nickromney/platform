import type { User as OidcUser, UserManager } from 'oidc-client-ts'
import { getOidcConfig } from './config'
import type { ClientPrincipal } from './entraid-auth'

type OidcModule = typeof import('oidc-client-ts')

let oidcModulePromise: Promise<OidcModule> | null = null
let userManagerPromise: Promise<UserManager> | null = null
let autoLoginAttempted = false

function getOidcModule(): Promise<OidcModule> {
  if (!oidcModulePromise) {
    oidcModulePromise = import('oidc-client-ts')
  }

  return oidcModulePromise
}

function normalizeRedirectUri(value: string): string {
  return value.endsWith('/') ? value : `${value}/`
}

function hasOidcCallbackParams(): boolean {
  const params = new URLSearchParams(window.location.search)
  return params.has('code') || params.has('state')
}

function extractReturnUrl(state: unknown): string {
  if (typeof state === 'string' && state.startsWith('/')) {
    return state
  }

  if (typeof state === 'object' && state !== null && 'returnUrl' in state) {
    const returnUrl = (state as { returnUrl?: unknown }).returnUrl
    if (typeof returnUrl === 'string' && returnUrl.startsWith('/')) {
      return returnUrl
    }
  }

  return window.location.pathname || '/'
}

function normalizeClaims(profile: OidcUser['profile']): ClientPrincipal['claims'] {
  return Object.entries(profile).flatMap(([typ, rawValue]) => {
    if (typeof rawValue === 'string') {
      return [{ typ, val: rawValue }]
    }

    if (Array.isArray(rawValue)) {
      return rawValue
        .filter((value): value is string => typeof value === 'string')
        .map((value) => ({ typ, val: value }))
    }

    return []
  })
}

function normalizeUserRoles(profile: OidcUser['profile']): string[] {
  const rawRoles = profile.roles
  if (!Array.isArray(rawRoles)) {
    return []
  }

  return rawRoles.filter((role): role is string => typeof role === 'string')
}

function normalizeOidcUser(user: OidcUser): ClientPrincipal {
  const preferredUsername =
    typeof user.profile.preferred_username === 'string' ? user.profile.preferred_username : undefined
  const email = typeof user.profile.email === 'string' ? user.profile.email : undefined
  const name = typeof user.profile.name === 'string' ? user.profile.name : undefined
  const sub = typeof user.profile.sub === 'string' ? user.profile.sub : ''

  return {
    identityProvider: 'oidc',
    userId: sub || preferredUsername || email || name || '',
    userDetails: email || preferredUsername || name || sub,
    userRoles: normalizeUserRoles(user.profile),
    claims: normalizeClaims(user.profile),
  }
}

async function getUserManager(): Promise<UserManager> {
  if (!userManagerPromise) {
    userManagerPromise = (async () => {
      const { UserManager, WebStorageStateStore } = await getOidcModule()
      const config = getOidcConfig()
      const authority = config.authority
      const clientId = config.clientId

      if (!authority || !clientId) {
        throw new Error('OIDC configuration missing: authority and clientId are required')
      }

      const redirectUri = normalizeRedirectUri(config.redirectUri)
      const logoutRedirectUri = new URL('/logged-out.html', redirectUri).toString()

      return new UserManager({
        authority,
        client_id: clientId,
        redirect_uri: redirectUri,
        post_logout_redirect_uri: logoutRedirectUri,
        response_type: 'code',
        scope: 'openid user_impersonation',
        loadUserInfo: true,
        userStore: new WebStorageStateStore({ store: window.localStorage }),
        ...(config.prompt ? { extraQueryParams: { prompt: config.prompt } } : {}),
        metadata: {
          issuer: authority,
          authorization_endpoint: `${authority}/protocol/openid-connect/auth`,
          token_endpoint: `${authority}/protocol/openid-connect/token`,
          userinfo_endpoint: `${authority}/protocol/openid-connect/userinfo`,
          end_session_endpoint: `${authority}/protocol/openid-connect/logout`,
          jwks_uri: `${authority}/protocol/openid-connect/certs`,
        },
      })
    })()
  }

  return userManagerPromise
}

export async function initializeOidcSession(): Promise<ClientPrincipal | null> {
  try {
    const manager = await getUserManager()
    const config = getOidcConfig()

    if (config.forceReauth && !hasOidcCallbackParams()) {
      await manager.removeUser()
    }

    let user: OidcUser | null = null
    if (hasOidcCallbackParams()) {
      user = await manager.signinRedirectCallback()
      const returnUrl = extractReturnUrl(user.state)
      window.history.replaceState({}, document.title, returnUrl)
    } else {
      user = await manager.getUser()
    }

    if (user && !user.expired) {
      return normalizeOidcUser(user)
    }

    if (config.autoLogin && !autoLoginAttempted) {
      autoLoginAttempted = true
      await manager.signinRedirect({
        state: {
          returnUrl: `${window.location.pathname}${window.location.search}${window.location.hash}` || '/',
        },
      })
    }
  } catch (error) {
    console.error('OIDC initialization error:', error)
  }

  return null
}

export async function getOidcAccessToken(): Promise<string | null> {
  try {
    const manager = await getUserManager()
    const user = await manager.getUser()

    if (!user || user.expired) {
      return null
    }

    return user.access_token
  } catch (error) {
    console.error('Error getting OIDC access token:', error)
    return null
  }
}

export async function loginWithOidc(returnUrl?: string): Promise<void> {
  const manager = await getUserManager()
  autoLoginAttempted = true
  await manager.signinRedirect({
    state: {
      returnUrl: returnUrl || `${window.location.pathname}${window.location.search}${window.location.hash}` || '/',
    },
  })
}

export async function logoutFromOidc(returnUrl?: string): Promise<void> {
  const manager = await getUserManager()
  autoLoginAttempted = false
  await manager.removeUser()
  await manager.signoutRedirect({
    post_logout_redirect_uri: returnUrl || `${window.location.origin}/logged-out.html`,
  })
}
