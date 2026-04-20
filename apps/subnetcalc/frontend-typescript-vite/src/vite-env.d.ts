/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_API_URL?: string
  readonly VITE_AUTH_ENABLED?: string
  readonly VITE_JWT_USERNAME?: string
  readonly VITE_JWT_PASSWORD?: string
  readonly VITE_AUTH_METHOD?: 'none' | 'jwt' | 'entraid' | 'oidc'
  readonly VITE_SHOW_NETWORK_PATH?: string
  readonly VITE_NETWORK_HOPS?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
