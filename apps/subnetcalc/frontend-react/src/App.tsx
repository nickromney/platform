import { PublicClientApplication } from '@azure/msal-browser'
import { MsalProvider } from '@azure/msal-react'
import { useEffect, useState } from 'react'
import { AuthProvider } from './auth/AuthContext'
import { msalConfig } from './auth/msalConfig'
import { SubnetCalculator } from './components/SubnetCalculator'
import { APP_CONFIG } from './config'
import '../../shared-frontend/src/styles.css'

// Initialize MSAL instance only if using MSAL auth
const msalInstance =
  APP_CONFIG.auth.method === 'msal' && APP_CONFIG.auth.clientId ? new PublicClientApplication(msalConfig) : null

function App() {
  const [theme, setTheme] = useState<'light' | 'dark'>('dark')

  // Load theme preference from localStorage
  useEffect(() => {
    const savedTheme = localStorage.getItem('theme') as 'light' | 'dark' | null
    if (savedTheme) {
      setTheme(savedTheme)
      document.documentElement.setAttribute('data-theme', savedTheme)
    }
  }, [])

  useEffect(() => {
    document.documentElement.setAttribute('data-auth-method', APP_CONFIG.auth.method)
    document.documentElement.setAttribute('data-oidc-auto-login', APP_CONFIG.auth.oidcAutoLogin ? 'true' : 'false')
  }, [])

  const toggleTheme = () => {
    const newTheme = theme === 'dark' ? 'light' : 'dark'
    setTheme(newTheme)
    localStorage.setItem('theme', newTheme)
    document.documentElement.setAttribute('data-theme', newTheme)
  }

  const debugMetadata = (
    <div
      id="auth-debug"
      data-auth-method={APP_CONFIG.auth.method}
      data-oidc-auto-login={APP_CONFIG.auth.oidcAutoLogin ? 'true' : 'false'}
      style={{ display: 'none' }}
    />
  )

  // Wrap with MsalProvider only if using MSAL
  if (APP_CONFIG.auth.method === 'msal' && msalInstance) {
    return (
      <MsalProvider instance={msalInstance}>
        <AuthProvider>
          <SubnetCalculator theme={theme} onToggleTheme={toggleTheme} />
          {debugMetadata}
        </AuthProvider>
      </MsalProvider>
    )
  }

  // For Easy Auth, SWA, or no auth - use AuthProvider directly
  return (
    <AuthProvider>
      <SubnetCalculator theme={theme} onToggleTheme={toggleTheme} />
      {debugMetadata}
    </AuthProvider>
  )
}

export default App
