import type { AccountInfo } from '@azure/msal-browser'
import { MsalContext } from '@azure/msal-react'
import type { ReactNode } from 'react'
import { useContext, useEffect, useState } from 'react'
import { AuthContext, type AuthContextType } from './AuthContext'
import { loginRequest } from './msalConfig'

const EMPTY_ACCOUNTS: AccountInfo[] = []

export function MsalAuthProvider({ children }: { children: ReactNode }) {
  const [isAuthenticated, setIsAuthenticated] = useState(false)
  const [isLoading, setIsLoading] = useState(true)
  const [user, setUser] = useState<AuthContextType['user']>(null)

  const msalContext = useContext(MsalContext)
  const instance = msalContext?.instance ?? null
  const accounts = msalContext?.accounts ?? EMPTY_ACCOUNTS

  useEffect(() => {
    setIsLoading(true)

    if (accounts.length > 0) {
      const account = accounts[0]
      setIsAuthenticated(true)
      setUser(
        account
          ? {
              name: account.name || account.username,
              email: account.username,
              username: account.username,
            }
          : null
      )
    } else {
      setIsAuthenticated(false)
      setUser(null)
    }

    setIsLoading(false)
  }, [accounts])

  const value: AuthContextType = {
    isAuthenticated,
    isLoading,
    user,
    login: () => {
      if (instance) {
        instance.loginRedirect(loginRequest)
      }
    },
    logout: () => {
      if (instance) {
        instance.logoutRedirect()
      }
    },
    authMethod: 'msal',
    hasApiSession: isAuthenticated,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
