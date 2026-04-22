import type { ReactNode } from 'react'
import { AuthContext, type AuthContextType } from './AuthContext'
import { JwtAuthProvider, useJwtAuth } from './jwtAuthProvider'

function JwtAuthBridge({ children }: { children: ReactNode }) {
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

export default function JwtAuthWrapper({ children }: { children: ReactNode }) {
  return (
    <JwtAuthProvider>
      <JwtAuthBridge>{children}</JwtAuthBridge>
    </JwtAuthProvider>
  )
}
