/**
 * OIDC Authentication Provider
 * Uses oidc-client-ts for OpenID Connect authentication (Keycloak, Auth0, Okta, etc.)
 */

import type { UserInfo } from '@subnetcalc/shared-frontend'
import { type User as OidcUser, UserManager, WebStorageStateStore } from 'oidc-client-ts'
import { createContext, type ReactNode, useContext, useEffect, useRef, useState } from 'react'
import { APP_CONFIG } from '../config'

// Constants
const POST_LOGOUT_PAGE = '/logged-out.html'

interface OidcAuthContextType {
  isAuthenticated: boolean
  isLoading: boolean
  user: UserInfo | null
  login: () => Promise<void>
  logout: () => void
  hasApiSession: boolean
}

const OidcAuthContext = createContext<OidcAuthContextType | undefined>(undefined)

// Initialize UserManager
let userManager: UserManager | null = null

function getUserManager(): UserManager {
  if (!userManager) {
    const authorityFromConfig = APP_CONFIG.auth.oidcAuthority
    const authority = authorityFromConfig || `${window.location.origin}/realms/subnetcalc`
    const clientId = APP_CONFIG.auth.oidcClientId
    const redirectUri = APP_CONFIG.auth.oidcRedirectUri || window.location.origin
    const prompt = APP_CONFIG.auth.oidcPrompt

    if (!authority || !clientId) {
      throw new Error('OIDC configuration missing: authority and clientId required')
    }

    userManager = new UserManager({
      authority,
      client_id: clientId,
      redirect_uri: `${redirectUri}/`,
      post_logout_redirect_uri: `${redirectUri}${POST_LOGOUT_PAGE}`,
      response_type: 'code',
      scope: 'openid user_impersonation',
      automaticSilentRenew: true,
      userStore: new WebStorageStateStore({ store: window.localStorage }),
      ...(prompt ? { extraQueryParams: { prompt } } : {}),
      // For local development with Keycloak
      loadUserInfo: true,
      metadata: {
        issuer: authority,
        authorization_endpoint: `${authority}/protocol/openid-connect/auth`,
        token_endpoint: `${authority}/protocol/openid-connect/token`,
        userinfo_endpoint: `${authority}/protocol/openid-connect/userinfo`,
        end_session_endpoint: `${authority}/protocol/openid-connect/logout`,
        jwks_uri: `${authority}/protocol/openid-connect/certs`,
      },
    })
  }

  return userManager
}

export function OidcAuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [user, setUser] = useState<UserInfo | null>(null)
  const [hasApiSession, setHasApiSession] = useState(false)
  const autoLoginAttemptedRef = useRef(false)

  useEffect(() => {
    ;(window as Window & { __OIDC_AUTO_LOGIN__?: boolean }).__OIDC_AUTO_LOGIN__ = APP_CONFIG.auth.oidcAutoLogin
    const initAuth = async () => {
      try {
        const manager = getUserManager()
        let authenticated = false

        const forceReauth = APP_CONFIG.auth.oidcForceReauth === true
        if (forceReauth && !(window.location.search.includes('code=') || window.location.search.includes('state='))) {
          // For local demos, aggressively clear any cached oidc-client user so role/claim
          // changes in Keycloak take effect immediately.
          await manager.removeUser()
        }

        const setUserFromOidc = (oidcUser: OidcUser) => {
          setIsAuthenticated(true)
          setUser({
            name: oidcUser.profile.name || oidcUser.profile.preferred_username || 'Unknown',
            email: oidcUser.profile.email || '',
            username: oidcUser.profile.preferred_username || oidcUser.profile.sub || '',
          })
          setHasApiSession(true)
        }

        // Handle redirect from OIDC provider
        if (window.location.search.includes('code=') || window.location.search.includes('state=')) {
          try {
            const oidcUser = await manager.signinRedirectCallback()
            setUserFromOidc(oidcUser)
            authenticated = true
            // Clean up URL
            window.history.replaceState({}, document.title, window.location.pathname)
          } catch (error) {
            console.error('Error handling OIDC callback:', error)
            setHasApiSession(false)
          }
        } else {
          // Check if user is already authenticated
          const oidcUser = await manager.getUser()
          if (oidcUser && !oidcUser.expired) {
            setUserFromOidc(oidcUser)
            authenticated = true
          } else {
            setIsAuthenticated(false)
            setUser(null)
            setHasApiSession(false)
          }
        }

        if (!authenticated && APP_CONFIG.auth.oidcAutoLogin && !autoLoginAttemptedRef.current) {
          autoLoginAttemptedRef.current = true
          try {
            await manager.signinRedirect()
          } catch (error) {
            console.error('Error triggering automatic OIDC login:', error)
          }
        }
      } catch (error) {
        console.error('OIDC initialization error:', error)
      } finally {
        setIsLoading(false)
      }
    }

    initAuth()
  }, [])

  const login = async () => {
    const manager = getUserManager()
    await manager.signinRedirect()
  }

  const logout = () => {
    const manager = getUserManager()
    manager.signoutRedirect()
    setIsAuthenticated(false)
    setUser(null)
    setHasApiSession(false)
  }

  const value: OidcAuthContextType = {
    isAuthenticated,
    isLoading,
    user,
    login,
    logout,
    hasApiSession,
  }

  return <OidcAuthContext.Provider value={value}>{children}</OidcAuthContext.Provider>
}

export function useOidcAuth() {
  const context = useContext(OidcAuthContext)
  if (context === undefined) {
    throw new Error('useOidcAuth must be used within an OidcAuthProvider')
  }
  return context
}

// Get access token for API calls
export async function getOidcAccessToken(): Promise<string | null> {
  try {
    const manager = getUserManager()
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
