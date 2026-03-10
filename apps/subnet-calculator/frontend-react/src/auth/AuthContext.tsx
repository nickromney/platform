/**
 * Unified Authentication Context
 * Provides authentication state and methods for all auth providers:
 * - Easy Auth (Azure Web App / Container Apps)
 * - MSAL (Local development)
 * - Static Web Apps (Entra ID via SWA)
 * - None (no authentication)
 */

import type { AccountInfo } from '@azure/msal-browser'
import { MsalContext } from '@azure/msal-react'
import type { UserInfo } from '@subnet-calculator/shared-frontend'
import type React from 'react'
import { createContext, useContext, useEffect, useState } from 'react'
import { APP_CONFIG } from '../config'
import { easyAuthLogin, easyAuthLogout, getEasyAuthUser, isEasyAuthAuthenticated } from './easyAuthProvider'
import { JwtAuthProvider, useJwtAuth } from './jwtAuthProvider'
import { loginRequest } from './msalConfig'
import { OidcAuthProvider, useOidcAuth } from './oidcAuthProvider'

interface AuthContextType {
  isAuthenticated: boolean
  isLoading: boolean
  user: UserInfo | null
  login: () => void
  logout: () => void
  authMethod: string
  hasApiSession: boolean
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)
const EMPTY_ACCOUNTS: AccountInfo[] = []

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const authMethod = APP_CONFIG.auth.method
  ;(window as Window & { __AUTH_METHOD__?: string }).__AUTH_METHOD__ = authMethod

  // For JWT auth, use the specialized JWT provider
  if (authMethod === 'jwt') {
    return (
      <JwtAuthProvider>
        <JwtAuthBridge>{children}</JwtAuthBridge>
      </JwtAuthProvider>
    )
  }

  // For OIDC auth, use the specialized OIDC provider
  if (authMethod === 'oidc') {
    return (
      <OidcAuthProvider>
        <OidcAuthBridge>{children}</OidcAuthBridge>
      </OidcAuthProvider>
    )
  }

  // For other auth methods, use the standard flow
  return <StandardAuthProvider>{children}</StandardAuthProvider>
}

// Bridge component to adapt JWT context to standard Auth context
function JwtAuthBridge({ children }: { children: React.ReactNode }) {
  const jwtAuth = useJwtAuth()

  const value: AuthContextType = {
    isAuthenticated: jwtAuth.isAuthenticated,
    isLoading: jwtAuth.isLoading,
    user: jwtAuth.user,
    login: () => {
      jwtAuth.login().catch(console.error)
    },
    logout: jwtAuth.logout,
    authMethod: 'jwt',
    hasApiSession: jwtAuth.isAuthenticated,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

// Bridge component to adapt OIDC context to standard Auth context
function OidcAuthBridge({ children }: { children: React.ReactNode }) {
  const oidcAuth = useOidcAuth()

  const value: AuthContextType = {
    isAuthenticated: oidcAuth.isAuthenticated,
    isLoading: oidcAuth.isLoading,
    user: oidcAuth.user,
    login: () => {
      oidcAuth.login().catch(console.error)
    },
    logout: oidcAuth.logout,
    authMethod: 'oidc',
    hasApiSession: oidcAuth.hasApiSession,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

// Standard auth provider for Easy Auth, MSAL, SWA, and none
function StandardAuthProvider({ children }: { children: React.ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [user, setUser] = useState<UserInfo | null>(null)

  const authMethod = APP_CONFIG.auth.method

  // Access MSAL context directly so non-MSAL flows don't throw when the provider is absent
  const msalContext = useContext(MsalContext)
  const instance = authMethod === 'msal' ? (msalContext?.instance ?? null) : null
  const accounts = authMethod === 'msal' ? (msalContext?.accounts ?? []) : EMPTY_ACCOUNTS

  // Initialize authentication based on method
  useEffect(() => {
    const initAuth = async () => {
      setIsLoading(true)

      try {
        switch (authMethod) {
          case 'easyauth': {
            // Easy Auth - check /.auth/me endpoint
            const authenticated = await isEasyAuthAuthenticated()
            setIsAuthenticated(authenticated)

            if (authenticated) {
              const userInfo = await getEasyAuthUser()
              setUser(userInfo)
            }
            break
          }

          case 'msal': {
            // MSAL - check for active account
            if (accounts && accounts.length > 0) {
              setIsAuthenticated(true)
              const account = accounts[0]
              if (account) {
                setUser({
                  name: account.name || account.username,
                  email: account.username,
                  username: account.username,
                })
              }
            }
            break
          }

          case 'entraid-swa': {
            // Static Web Apps - check /.auth/me endpoint (same as Easy Auth)
            const authenticated = await isEasyAuthAuthenticated()
            setIsAuthenticated(authenticated)

            if (authenticated) {
              const userInfo = await getEasyAuthUser()
              setUser(userInfo)
            }
            break
          }
          default:
            // No authentication
            setIsAuthenticated(true) // Allow access without auth
            break
        }
      } catch (error) {
        console.error('Auth initialization error:', error)
        setIsAuthenticated(false)
      } finally {
        setIsLoading(false)
      }
    }

    initAuth()
  }, [authMethod, accounts])

  const login = () => {
    switch (authMethod) {
      case 'easyauth':
      case 'entraid-swa':
        easyAuthLogin()
        break

      case 'msal':
        if (instance) {
          instance.loginRedirect(loginRequest)
        }
        break
      default:
        // No-op
        break
    }
  }

  const logout = () => {
    switch (authMethod) {
      case 'easyauth':
      case 'entraid-swa':
        easyAuthLogout()
        break

      case 'msal':
        if (instance) {
          instance.logoutRedirect()
        }
        break
      default:
        // No-op
        break
    }
  }

  const value: AuthContextType = {
    isAuthenticated,
    isLoading,
    user,
    login,
    logout,
    authMethod,
    hasApiSession: isAuthenticated,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
