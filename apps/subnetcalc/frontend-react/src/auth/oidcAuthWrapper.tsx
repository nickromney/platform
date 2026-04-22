import type { ReactNode } from 'react'
import { AuthContext, type AuthContextType } from './AuthContext'
import { OidcAuthProvider, useOidcAuth } from './oidcAuthProvider'

function OidcAuthBridge({ children }: { children: ReactNode }) {
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

export default function OidcAuthWrapper({ children }: { children: ReactNode }) {
  return (
    <OidcAuthProvider>
      <OidcAuthBridge>{children}</OidcAuthBridge>
    </OidcAuthProvider>
  )
}
