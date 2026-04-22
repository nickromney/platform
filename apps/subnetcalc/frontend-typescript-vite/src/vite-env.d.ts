/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL?: string
  readonly VITE_AUTH_ENABLED?: string
  readonly VITE_JWT_USERNAME?: string
  readonly VITE_JWT_PASSWORD?: string
  readonly VITE_AUTH_METHOD?: 'none' | 'jwt' | 'entraid' | 'gateway' | 'oidc'
  readonly VITE_APIM_SUBSCRIPTION_KEY?: string
  readonly VITE_OIDC_AUTHORITY?: string
  readonly VITE_OIDC_CLIENT_ID?: string
  readonly VITE_OIDC_REDIRECT_URI?: string
  readonly VITE_OIDC_AUTO_LOGIN?: string
  readonly VITE_OIDC_PROMPT?: string
  readonly VITE_OIDC_FORCE_REAUTH?: string
  readonly VITE_SHOW_NETWORK_PATH?: string
  readonly VITE_NETWORK_HOPS?: string
  readonly VITE_STACK_DESCRIPTION?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
