import type { UserInfo } from '@subnetcalc/shared-frontend'
import { createContext, useContext } from 'react'

export interface AuthContextType {
  isAuthenticated: boolean
  isLoading: boolean
  user: UserInfo | null
  login: () => void
  logout: () => void
  authMethod: string
  hasApiSession: boolean
}

export const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function useAuth() {
  const context = useContext(AuthContext)
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider')
  }
  return context
}
