import type { ReactNode } from 'react'
import { useEffect, useState } from 'react'
import { APP_CONFIG } from '../config'
import { AuthContext, type AuthContextType } from './AuthContext'
import { easyAuthLogin, easyAuthLogout, getEasyAuthUser, isEasyAuthAuthenticated } from './easyAuthProvider'

export function StandardAuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [user, setUser] = useState<AuthContextType['user']>(null)

  const authMethod = APP_CONFIG.auth.method

  useEffect(() => {
    const initAuth = async () => {
      setIsLoading(true)

      try {
        switch (authMethod) {
          case 'easyauth':
          case 'entraid-swa': {
            const authenticated = await isEasyAuthAuthenticated()
            setIsAuthenticated(authenticated)

            if (authenticated) {
              const userInfo = await getEasyAuthUser()
              setUser(userInfo)
            } else {
              setUser(null)
            }
            break
          }

          default:
            setIsAuthenticated(true)
            setUser(null)
            break
        }
      } catch (error) {
        console.error('Auth initialization error:', error)
        setIsAuthenticated(false)
        setUser(null)
      } finally {
        setIsLoading(false)
      }
    }

    initAuth()
  }, [authMethod])

  const login = () => {
    switch (authMethod) {
      case 'easyauth':
      case 'entraid-swa':
        easyAuthLogin()
        break
      default:
        break
    }
  }

  const logout = () => {
    switch (authMethod) {
      case 'easyauth':
      case 'entraid-swa':
        easyAuthLogout()
        break
      default:
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
