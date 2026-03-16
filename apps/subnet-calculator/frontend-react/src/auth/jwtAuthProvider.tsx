/**
 * JWT Authentication Provider for React
 * Uses the shared TokenManager from @subnet-calculator/shared-frontend
 */

import { TokenManager, type UserInfo } from '@subnet-calculator/shared-frontend'
import type React from 'react'
import { createContext, useContext, useEffect, useMemo, useState } from 'react'
import { APP_CONFIG } from '../config'

interface JwtAuthContextType {
  isAuthenticated: boolean
  isLoading: boolean
  user: UserInfo | null
  tokenManager: TokenManager
  login: () => Promise<void>
  logout: () => void
  error: string | null
}

const JwtAuthContext = createContext<JwtAuthContextType | undefined>(undefined)

export function JwtAuthProvider({ children }: { children: React.ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [user, setUser] = useState<UserInfo | null>(null)
  const [error, setError] = useState<string | null>(null)

  // Extract config values to avoid Proxy in dependency array
  const apiBaseUrl = APP_CONFIG.apiBaseUrl
  const jwtUsername = APP_CONFIG.auth.jwtUsername || ''
  const jwtPassword = APP_CONFIG.auth.jwtPassword || ''

  // Initialize TokenManager with useMemo to prevent recreation on every render
  const tokenManager = useMemo(() => new TokenManager(apiBaseUrl, jwtUsername, jwtPassword), [jwtUsername, jwtPassword])

  // Check authentication on mount
  useEffect(() => {
    const checkAuth = async () => {
      try {
        if (tokenManager.isAuthEnabled()) {
          // Try to get token (will use cache if available)
          const token = await tokenManager.getToken()
          if (token) {
            setIsAuthenticated(true)
            setUser({
              username: APP_CONFIG.auth.jwtUsername || 'demo@dev.test',
              name: APP_CONFIG.auth.jwtUsername || 'Demo User',
            })
          }
        }
      } catch (err) {
        console.error('JWT auth check failed:', err)
        setError(err instanceof Error ? err.message : 'Authentication failed')
      } finally {
        setIsLoading(false)
      }
    }

    checkAuth()
  }, [tokenManager])

  const login = async () => {
    setIsLoading(true)
    setError(null)
    try {
      const token = await tokenManager.getToken()
      if (token) {
        setIsAuthenticated(true)
        setUser({
          username: APP_CONFIG.auth.jwtUsername || 'demo@dev.test',
          name: APP_CONFIG.auth.jwtUsername || 'Demo User',
        })
      }
    } catch (err) {
      console.error('JWT login failed:', err)
      setError(err instanceof Error ? err.message : 'Login failed')
      throw err
    } finally {
      setIsLoading(false)
    }
  }

  const logout = () => {
    tokenManager.clearCache()
    setIsAuthenticated(false)
    setUser(null)
    setError(null)
  }

  const value: JwtAuthContextType = {
    isAuthenticated,
    isLoading,
    user,
    tokenManager,
    login,
    logout,
    error,
  }

  return <JwtAuthContext.Provider value={value}>{children}</JwtAuthContext.Provider>
}

export function useJwtAuth() {
  const context = useContext(JwtAuthContext)
  if (context === undefined) {
    throw new Error('useJwtAuth must be used within a JwtAuthProvider')
  }
  return context
}
