/**
 * Main Subnet Calculator Component
 * Handles the complete subnet calculator UI and logic
 * Uses Pico CSS with minimal inline styles
 */

import { useEffect, useState } from 'react'
import { apiClient } from '../api/client'
import { useAuth } from '../auth/AuthContext'
import { APP_CONFIG } from '../config'
import type { CloudMode, HealthResponse, LookupResult } from '../types'

interface SubnetCalculatorProps {
  theme: 'light' | 'dark'
  onToggleTheme: () => void
}

export function SubnetCalculator({ theme, onToggleTheme }: SubnetCalculatorProps) {
  const { user, isAuthenticated, isLoading: authLoading, login, logout, hasApiSession } = useAuth()

  const stage = APP_CONFIG.deploymentStage

  const [ipAddress, setIpAddress] = useState('')
  const [cloudMode, setCloudMode] = useState<CloudMode>('Azure')
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [results, setResults] = useState<LookupResult | null>(null)
  const [apiHealth, setApiHealth] = useState<HealthResponse | null>(null)
  const [apiError, setApiError] = useState<string | null>(null)
  const [apiChecked, setApiChecked] = useState(false)

  useEffect(() => {
    if (APP_CONFIG.auth.method !== 'oidc') {
      return
    }

    if (authLoading) {
      return
    }

    if (!isAuthenticated && !hasApiSession) {
      window.location.replace('/logged-out.html')
    }
  }, [authLoading, isAuthenticated, hasApiSession])

  const shouldShowLoginButton =
    !isAuthenticated && APP_CONFIG.auth.method !== 'none' && APP_CONFIG.auth.method !== 'oidc'

  // Check API health when authentication state permits it
  useEffect(() => {
    let cancelled = false

    const requiresSpaLogin = APP_CONFIG.auth.method === 'oidc' && !hasApiSession
    if (requiresSpaLogin) {
      setApiHealth(null)
      setApiError(null)
      setApiChecked(false)
      return () => {
        cancelled = true
      }
    }

    const shouldCheckHealth = APP_CONFIG.auth.method === 'none' || isAuthenticated
    if (!shouldCheckHealth) {
      setApiHealth(null)
      setApiError(null)
      setApiChecked(false)
      return () => {
        cancelled = true
      }
    }

    const checkHealthWithRetry = async () => {
      // First load after (re)deploy can be slow (image pulls / cold start).
      // Retry a few times before surfacing an error.
      const maxAttempts = 5
      const baseDelayMs = 1000

      for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        if (cancelled) {
          return
        }

        try {
          const health = await apiClient.checkHealth()
          if (cancelled) {
            return
          }
          setApiHealth(health)
          setApiError(null)
          setApiChecked(true)
          return
        } catch (err) {
          if (cancelled) {
            return
          }

          if (err instanceof Error && err.message.includes('401')) {
            console.debug('API authentication required, waiting for user session')
            setApiHealth(null)
            setApiError(null)
            setApiChecked(false)
            return
          }

          if (attempt === maxAttempts) {
            setApiError(err instanceof Error ? err.message : 'API unavailable')
            setApiChecked(true)
            return
          }

          const delayMs = baseDelayMs * attempt
          await new Promise(resolve => setTimeout(resolve, delayMs))
        }
      }
    }

    setApiChecked(false)
    checkHealthWithRetry()

    return () => {
      cancelled = true
    }
  }, [isAuthenticated, hasApiSession])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    // Check authentication before making API call
    if (!isAuthenticated && APP_CONFIG.auth.method === 'oidc') {
      setError('authentication_required')
      return
    }

    setIsLoading(true)
    setError(null)
    setResults(null)

    try {
      const result = await apiClient.performLookup(ipAddress, cloudMode)
      setResults(result)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred')
    } finally {
      setIsLoading(false)
    }
  }

  const handleExampleClick = (address: string) => {
    setIpAddress(address)
  }

  if (authLoading) {
    return (
      <div className="container loading-center">
        <div aria-busy="true">Loading...</div>
      </div>
    )
  }

  return (
    <>
      {/* Top Bar - Fixed Position */}
      <div className="top-bar">
        {stage !== 'UNKNOWN' && (
          <div className={`stage-badge stage-badge--${stage.toLowerCase()}`} title={`Stage: ${stage}`}>
            {stage}
          </div>
        )}
        <button id="theme-switcher" type="button" onClick={onToggleTheme}>
          <span id="theme-icon">{theme === 'dark' ? '☀️' : '🌙'}</span> Toggle Theme
        </button>
        {isAuthenticated && hasApiSession && user && (
          <div id="user-info" className="user-info">
            <span>Welcome, {user.name}</span>
            <button type="button" onClick={logout}>
              Logout
            </button>
          </div>
        )}
        {shouldShowLoginButton && (
          <button type="button" onClick={login}>
            Login
          </button>
        )}
      </div>

      <main className="container">
        {/* Header */}
        <header>
          <h1>IPv4 Subnet Calculator</h1>
          <p id="stack-description">{APP_CONFIG.stackName}</p>
        </header>

        {/* API Status */}
        {APP_CONFIG.auth.method === 'oidc' && !hasApiSession && (
          <div id="api-status" className="alert" role="alert">
            <strong>Authentication Required:</strong> Click Login to finish signing in and load API status.
          </div>
        )}
        {apiChecked && apiHealth && (
          <div id="api-status" className="alert alert-success">
            <strong>API Status:</strong> healthy | <strong>Backend:</strong> {apiHealth.service} |{' '}
            <strong>Version:</strong> {apiHealth.version}
            <br />
            <small>
              Frontend: <code>{window.location.origin}/</code> | Backend:{' '}
              <code>{apiClient.getBaseUrl() || window.location.origin}</code>
            </small>
          </div>
        )}
        {apiChecked && apiError && (
          <div id="api-status" className="alert alert-error" role="alert">
            <strong>API Offline:</strong> {apiError}
          </div>
        )}

        {/* Input Form */}
        <section>
          <form id="lookup-form" onSubmit={handleSubmit}>
            <div>
              <label htmlFor="ip-address">IP Address or CIDR Range</label>
              <div className="form-row">
                <input
                  type="text"
                  id="ip-address"
                  value={ipAddress}
                  onChange={e => setIpAddress(e.target.value)}
                  placeholder="e.g., 192.168.1.1 or 10.0.0.0/24"
                  required
                />
                <select id="cloud-mode" value={cloudMode} onChange={e => setCloudMode(e.target.value as CloudMode)}>
                  <option value="Standard">Standard</option>
                  <option value="AWS">AWS</option>
                  <option value="Azure">Azure</option>
                  <option value="OCI">OCI</option>
                </select>
                <button type="submit" disabled={isLoading || !ipAddress}>
                  Lookup
                </button>
              </div>
            </div>

            {/* Example Buttons */}
            <div id="example-buttons" className="example-buttons">
              <button
                type="button"
                className="secondary outline example-btn btn-rfc1918"
                onClick={() => handleExampleClick('10.0.0.0/24')}
              >
                RFC1918: 10.0.0.0/24
              </button>
              <button
                type="button"
                className="outline example-btn btn-rfc6598"
                onClick={() => handleExampleClick('100.64.0.1')}
              >
                RFC6598: 100.64.0.1
              </button>
              <button
                type="button"
                className="contrast outline example-btn btn-public"
                onClick={() => handleExampleClick('8.8.8.8')}
              >
                Public: 8.8.8.8
              </button>
              <button
                type="button"
                className="secondary example-btn btn-cloudflare"
                onClick={() => handleExampleClick('104.16.1.1')}
              >
                Cloudflare: 104.16.1.1
              </button>
            </div>
          </form>
        </section>

        {/* Loading */}
        {isLoading && (
          <output id="loading" style={{ display: 'block', textAlign: 'center', margin: '2rem 0' }}>
            <div aria-busy="true"></div>
          </output>
        )}

        {/* Error */}
        {error && (
          <div id="error" className="alert alert-error" role="alert">
            {error === 'authentication_required' ? (
              <>
                <strong>Authentication Required:</strong> Please log in to use the calculator.{' '}
                <button type="button" onClick={login} className="ml-sm">
                  Log In
                </button>
              </>
            ) : (
              <>
                <strong>Error:</strong> {error}
              </>
            )}
          </div>
        )}

        {/* Results */}
        {results && (
          <section id="results" style={{ display: 'block' }}>
            <h2>Results</h2>
            <div id="results-content">
              {/* Validation */}
              {results.results.validate && (
                <article>
                  <h3>Validation</h3>
                  <table>
                    <tbody>
                      <tr>
                        <td>
                          <strong>Valid</strong>
                        </td>
                        <td>{results.results.validate.valid ? 'Yes' : 'No'}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>Type</strong>
                        </td>
                        <td>{results.results.validate.type}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>Address</strong>
                        </td>
                        <td>{results.results.validate.address}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>IP Version</strong>
                        </td>
                        <td>{results.results.validate.is_ipv6 ? 'IPv6' : 'IPv4'}</td>
                      </tr>
                    </tbody>
                  </table>
                </article>
              )}

              {/* Private Check (IPv4 only) */}
              {results.results.private && (
                <article>
                  <h3>RFC1918 Private Address Check</h3>
                  <table>
                    <tbody>
                      <tr>
                        <td>
                          <strong>Is RFC1918</strong>
                        </td>
                        <td>{results.results.private.is_rfc1918 ? 'Yes' : 'No'}</td>
                      </tr>
                      {results.results.private.matched_rfc1918_range && (
                        <tr>
                          <td>
                            <strong>Matched Range</strong>
                          </td>
                          <td>{results.results.private.matched_rfc1918_range}</td>
                        </tr>
                      )}
                    </tbody>
                  </table>
                </article>
              )}

              {/* Cloudflare Check */}
              {results.results.cloudflare && (
                <article>
                  <h3>Cloudflare Check</h3>
                  <table>
                    <tbody>
                      <tr>
                        <td>
                          <strong>Is Cloudflare</strong>
                        </td>
                        <td>{results.results.cloudflare.is_cloudflare ? 'Yes' : 'No'}</td>
                      </tr>
                      {results.results.cloudflare.matched_ranges &&
                        results.results.cloudflare.matched_ranges.length > 0 && (
                          <tr>
                            <td>
                              <strong>Matched Ranges</strong>
                            </td>
                            <td>{results.results.cloudflare.matched_ranges.join(', ')}</td>
                          </tr>
                        )}
                    </tbody>
                  </table>
                </article>
              )}

              {/* Subnet Info */}
              {results.results.subnet && (
                <article>
                  <h3>Subnet Information</h3>
                  <table>
                    <tbody>
                      <tr>
                        <td>
                          <strong>Network</strong>
                        </td>
                        <td>{results.results.subnet.network}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>Network Address</strong>
                        </td>
                        <td>{results.results.subnet.network_address}</td>
                      </tr>
                      {results.results.subnet.broadcast_address && (
                        <tr>
                          <td>
                            <strong>Broadcast Address</strong>
                          </td>
                          <td>{results.results.subnet.broadcast_address}</td>
                        </tr>
                      )}
                      <tr>
                        <td>
                          <strong>Netmask</strong>
                        </td>
                        <td>{results.results.subnet.netmask}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>Prefix Length</strong>
                        </td>
                        <td>/{results.results.subnet.prefix_length}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>Total Addresses</strong>
                        </td>
                        <td>{results.results.subnet.total_addresses.toLocaleString()}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>Usable Addresses</strong>
                        </td>
                        <td>{results.results.subnet.usable_addresses.toLocaleString()}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>First Usable IP</strong>
                        </td>
                        <td>{results.results.subnet.first_usable_ip}</td>
                      </tr>
                      <tr>
                        <td>
                          <strong>Last Usable IP</strong>
                        </td>
                        <td>{results.results.subnet.last_usable_ip}</td>
                      </tr>
                    </tbody>
                  </table>
                </article>
              )}

              {/* Performance Timing */}
              <article className="performance-timing">
                <h3>Performance Timing</h3>
                <table>
                  <tbody>
                    <tr>
                      <td>
                        <strong>Total Response Time</strong>
                      </td>
                      <td>
                        <strong>{results.timing.totalDuration}ms</strong> (
                        {(results.timing.totalDuration / 1000).toFixed(3)}s)
                      </td>
                    </tr>
                  </tbody>
                </table>

                {/* API Call Details */}
                <details>
                  <summary>API Call Details</summary>
                  <table>
                    <thead>
                      <tr>
                        <th>Call</th>
                        <th>Duration</th>
                        <th>Request Time (UTC)</th>
                        <th>Response Time (UTC)</th>
                      </tr>
                    </thead>
                    <tbody>
                      {results.timing.apiCalls.map(call => (
                        <tr key={`${call.call}-${call.requestTime}-${call.responseTime}`}>
                          <td>{call.call}</td>
                          <td>
                            <strong>{call.duration}ms</strong>
                          </td>
                          <td>{new Date(call.requestTime).toLocaleString()}</td>
                          <td>{new Date(call.responseTime).toLocaleString()}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </details>
              </article>
            </div>
          </section>
        )}
      </main>
    </>
  )
}
