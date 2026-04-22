import { lazy, Suspense, useEffect, useState, type ComponentType, type ReactNode } from 'react'
import { SubnetCalculator } from './components/SubnetCalculator'
import { APP_CONFIG } from './config'
import '../../shared-frontend/src/styles.css'

type AuthWrapperProps = {
  children: ReactNode
}

type AuthWrapperModule = {
  default: ComponentType<AuthWrapperProps>
}

function loadAuthWrapper(): Promise<AuthWrapperModule> {
  switch (APP_CONFIG.auth.method) {
    case 'jwt':
      return import('./auth/jwtAuthWrapper')
    case 'msal':
      return import('./auth/msalAuthWrapper')
    case 'oidc':
      return import('./auth/oidcAuthWrapper')
    default:
      return import('./auth/basicAuthWrapper')
  }
}

const AuthWrapper = lazy(loadAuthWrapper)

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

  return (
    <Suspense
      fallback={
        <div className="container loading-center">
          <div aria-busy="true">Loading...</div>
        </div>
      }
    >
      <AuthWrapper>
        <SubnetCalculator theme={theme} onToggleTheme={toggleTheme} />
        {debugMetadata}
      </AuthWrapper>
    </Suspense>
  )
}

export default App
