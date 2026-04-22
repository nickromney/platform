import { PublicClientApplication } from '@azure/msal-browser'
import { MsalProvider } from '@azure/msal-react'
import type { ReactNode } from 'react'
import { AuthContext, type AuthContextType } from './AuthContext'
import { MsalAuthProvider } from './msalAuthProvider'
import { msalConfig } from './msalConfig'

const msalInstance = msalConfig.auth.clientId ? new PublicClientApplication(msalConfig) : null

function FallbackMsalAuthProvider({ children }: { children: ReactNode }) {
  const value: AuthContextType = {
    isAuthenticated: false,
    isLoading: false,
    user: null,
    login: () => {},
    logout: () => {},
    authMethod: 'msal',
    hasApiSession: false,
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export default function MsalAuthWrapper({ children }: { children: ReactNode }) {
  if (!msalInstance) {
    return <FallbackMsalAuthProvider>{children}</FallbackMsalAuthProvider>
  }

  return (
    <MsalProvider instance={msalInstance}>
      <MsalAuthProvider>{children}</MsalAuthProvider>
    </MsalProvider>
  )
}
