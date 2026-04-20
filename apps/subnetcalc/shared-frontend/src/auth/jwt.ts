/**
 * JWT Authentication Manager
 *
 * Handles JWT token lifecycle:
 * - Login to API and obtain token
 * - Cache token with expiration
 * - Automatic token refresh
 * - Provide auth headers for API requests
 *
 * This module is shared between React and TypeScript Vite frontends.
 */

interface LoginResponse {
  access_token: string
  token_type: string
}

interface TokenCache {
  token: string
  expiresAt: Date
}

export class TokenManager {
  private cache: TokenCache | null = null
  private readonly baseUrl: string
  private readonly username: string
  private readonly password: string

  constructor(baseUrl: string, username: string, password: string) {
    this.baseUrl = baseUrl
    this.username = username
    this.password = password
  }

  /**
   * Check if authentication is configured
   */
  isAuthEnabled(): boolean {
    return this.username !== '' && this.password !== ''
  }

  /**
   * Get cached token if valid, otherwise login and cache
   */
  async getToken(): Promise<string | null> {
    // If auth not configured, return null
    if (!this.isAuthEnabled()) {
      return null
    }

    // Return cached token if still valid
    if (this.cache && new Date() < this.cache.expiresAt) {
      return this.cache.token
    }

    // Login and cache new token
    try {
      const token = await this.login()
      return token
    } catch (error) {
      console.error('Failed to obtain JWT token:', error)
      this.cache = null
      throw error
    }
  }

  /**
   * Login to API and obtain JWT token
   * Retries once on connection errors (handles Azure Functions cold start)
   */
  private async login(): Promise<string> {
    const formData = new URLSearchParams()
    formData.append('username', this.username)
    formData.append('password', this.password)

    const makeLoginRequest = async (): Promise<Response> => {
      return await fetch(`${this.baseUrl}/api/v1/auth/login`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: formData,
        signal: AbortSignal.timeout(5000), // 5 second timeout
      })
    }

    let response: Response
    try {
      response = await makeLoginRequest()
    } catch (error) {
      // Retry once on network errors (connection reset, timeout, etc.)
      console.warn('JWT login failed, retrying...', error)
      await new Promise((resolve) => setTimeout(resolve, 500)) // Wait 500ms
      response = await makeLoginRequest()
    }

    if (!response.ok) {
      throw new Error(`Login failed: HTTP ${response.status}`)
    }

    const data: LoginResponse = await response.json()

    // Cache token for 25 minutes (tokens expire in 30, refresh before that)
    const expiresAt = new Date()
    expiresAt.setMinutes(expiresAt.getMinutes() + 25)

    this.cache = {
      token: data.access_token,
      expiresAt,
    }

    return data.access_token
  }

  /**
   * Get authentication headers for API requests
   * Returns empty object if auth not configured
   */
  async getAuthHeaders(): Promise<Record<string, string>> {
    if (!this.isAuthEnabled()) {
      return {}
    }

    const token = await this.getToken()
    if (!token) {
      return {}
    }

    return {
      Authorization: `Bearer ${token}`,
    }
  }

  /**
   * Clear cached token (useful for logout or testing)
   */
  clearCache(): void {
    this.cache = null
  }
}
