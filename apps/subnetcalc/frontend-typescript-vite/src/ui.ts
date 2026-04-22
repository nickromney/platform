/**
 * UI utilities and rendering
 */

import { API_CONFIG, getNetworkHops } from './config'
import { type ClientPrincipal, getUserDisplayName, login, logout } from './entraid-auth'
import { loginWithOidc, logoutFromOidc } from './oidc-auth'
import type { ApiResults, NetworkDiagnosticsResponse } from './types'

export function showElement(id: string): void {
  const element = document.getElementById(id)
  if (element) element.style.display = 'block'
}

export function hideElement(id: string): void {
  const element = document.getElementById(id)
  if (element) element.style.display = 'none'
}

export function showLoading(): void {
  showElement('loading')
  hideElement('results')
  hideElement('error')
}

export function hideLoading(): void {
  hideElement('loading')
}

export function showError(message: string): void {
  const errorDiv = document.getElementById('error')
  if (errorDiv) {
    errorDiv.textContent = message
    showElement('error')
  }
  hideElement('results')
  hideLoading()
}

export function showApiStatus(healthy: boolean, service?: string, version?: string, endpoint?: string): void {
  const statusDiv = document.getElementById('api-status')
  if (!statusDiv) return

  if (healthy && service && version) {
    const apiIngress = endpoint && endpoint !== '' ? endpoint : `${window.location.origin}/api`
    const backendPathDetail = API_CONFIG.apiStatus.backendPathDetail
      ? `<br><small>${API_CONFIG.apiStatus.backendPathLabel}: <code>${escapeHtml(API_CONFIG.apiStatus.backendPathDetail)}</code></small>`
      : ''

    statusDiv.className = 'alert alert-success'
    statusDiv.innerHTML = `
      <strong>API Status:</strong> healthy |
      <strong>Service:</strong> ${service} |
      <strong>Version:</strong> ${version}<br>
      <small>${API_CONFIG.apiStatus.frontendLabel}: <code>${window.location.origin}/</code> | ${API_CONFIG.apiStatus.ingressLabel}: <code>${escapeHtml(apiIngress)}</code></small>
      ${backendPathDetail}
    `
  } else {
    statusDiv.className = 'alert alert-error'
    statusDiv.innerHTML = `
      <strong>API Unavailable:</strong> Unable to connect to backend<br>
      <small>The calculator may not function correctly</small>
    `
  }
  showElement('api-status')
}

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;')
}

function formatCodeList(values: string[]): string {
  if (values.length === 0) {
    return '<em>none</em>'
  }

  return values.map((value) => `<code>${escapeHtml(value)}</code>`).join(', ')
}

function renderNetworkDiagnostics(
  title: string,
  diagnostics: NetworkDiagnosticsResponse | null,
  timing?: { duration: number; requestTime: string; responseTime: string }
): string {
  if (!diagnostics) {
    return ''
  }

  const peerRows =
    diagnostics.tunnel.peers.length > 0
      ? diagnostics.tunnel.peers
          .map((peer) => {
            const endpoint =
              peer.endpoint_ip && peer.endpoint_port
                ? `${peer.endpoint_ip}:${peer.endpoint_port}`
                : peer.endpoint_ip || 'n/a'

            return `<tr>
              <td><code>${escapeHtml(`${peer.public_key.slice(0, 12)}...`)}</code></td>
              <td><code>${escapeHtml(endpoint)}</code></td>
              <td><code>${escapeHtml(peer.tunnel_peer_ip || 'n/a')}</code></td>
              <td>${formatCodeList(peer.allowed_ips)}</td>
            </tr>`
          })
          .join('')
      : '<tr><td colspan="4"><em>No tunnel peers discovered</em></td></tr>'

  return `
    <details>
      <summary>${escapeHtml(title)} (${diagnostics.traceroute.hop_count} traceroute hops)</summary>
      <table>
        ${
          diagnostics.viewpoint
            ? `<tr><th>Viewpoint</th><td><code>${escapeHtml(diagnostics.viewpoint)}</code></td></tr>`
            : ''
        }
        <tr><th>Generated (UTC)</th><td>${escapeHtml(diagnostics.generated_at)}</td></tr>
        <tr><th>Target</th><td><code>${escapeHtml(diagnostics.target)}</code></td></tr>
        <tr><th>DNS Resolver</th><td><code>${escapeHtml(diagnostics.dns.resolver)}</code></td></tr>
        <tr><th>DNS A Answers</th><td>${formatCodeList(diagnostics.dns.answers)}</td></tr>
        <tr><th>Tunnel Local IP</th><td><code>${escapeHtml(diagnostics.tunnel.local_tunnel_ip || 'n/a')}</code></td></tr>
        <tr><th>Tunnel Peer IPs</th><td>${formatCodeList(diagnostics.tunnel.peer_tunnel_ips)}</td></tr>
        <tr><th>Tunnel Endpoint IPs</th><td>${formatCodeList(diagnostics.tunnel.peer_endpoint_ips)}</td></tr>
        ${
          timing
            ? `<tr><th>Diagnostics API Time</th><td><strong>${timing.duration.toFixed(0)}ms</strong> (${timing.requestTime} → ${timing.responseTime})</td></tr>`
            : ''
        }
      </table>
      <details>
        <summary>Tunnel Peer Details</summary>
        <table>
          <tr><th>Peer Key</th><th>Endpoint</th><th>Tunnel IP</th><th>Allowed IPs</th></tr>
          ${peerRows}
        </table>
      </details>
      <details>
        <summary>DNS Raw</summary>
        <p><code>${escapeHtml(diagnostics.dns.command)}</code> (exit ${diagnostics.dns.exit_code})</p>
        <pre><code>${escapeHtml(diagnostics.dns.raw_output || '(no output)')}</code></pre>
      </details>
      <details>
        <summary>Traceroute Raw</summary>
        <p><code>${escapeHtml(diagnostics.traceroute.command)}</code> (exit ${diagnostics.traceroute.exit_code})</p>
        <pre><code>${escapeHtml(diagnostics.traceroute.raw_output || '(no output)')}</code></pre>
      </details>
    </details>
  `
}

export function renderResults(
  results: ApiResults,
  timingInfo?: {
    overallDuration: number
    overallRequestTimestamp: string
    overallResponseTimestamp: string
    address: string
    mode: string
    apiCalls: Array<{ call: string; requestTime: string; responseTime: string; duration: number }>
  },
  networkDiagnostics: NetworkDiagnosticsResponse | null = null,
  secondaryNetworkDiagnostics: NetworkDiagnosticsResponse | null = null
): void {
  const resultsContent = document.getElementById('results-content')
  if (!resultsContent) return

  let html = ''

  // Overall Performance Timing (if provided)
  if (timingInfo) {
    const overallSeconds = (timingInfo.overallDuration / 1000).toFixed(3)
    const requestPayload = escapeHtml(JSON.stringify({ address: timingInfo.address, mode: timingInfo.mode }))
    const networkHops = getNetworkHops()
    const diagnosticsTiming = timingInfo.apiCalls.find((call) => call.call === 'networkDiagnostics')
    const secondaryDiagnosticsTiming = timingInfo.apiCalls.find((call) => call.call === 'secondaryNetworkDiagnostics')
    const networkPathDetails =
      networkHops && networkHops.length > 0
        ? `<details>
          <summary>Network Path (${networkHops.length} hops)</summary>
          <div class="network-path">
            ${networkHops
              .map((hop, index) => {
                const hopArrow =
                  index > 0 ? `<div class="hop-arrow">↓${hop.detail.includes('mTLS') ? ' mTLS' : ''}</div>` : ''
                const hopRole = hop.role ? `<br><em>${hop.role}</em>` : ''
                return `${hopArrow}<div class="hop"><strong>${hop.label}</strong><br><small>${hop.detail}</small>${hopRole}</div>`
              })
              .join('')}
          </div>
        </details>`
        : ''
    const secondaryNetworkDiagnosticsDetails =
      secondaryNetworkDiagnostics && API_CONFIG.networkDiagnostics.secondaryLabel
        ? renderNetworkDiagnostics(
            API_CONFIG.networkDiagnostics.secondaryLabel,
            secondaryNetworkDiagnostics,
            secondaryDiagnosticsTiming
          )
        : ''
    const networkDiagnosticsDetails = renderNetworkDiagnostics(
      API_CONFIG.networkDiagnostics.primaryLabel,
      networkDiagnostics,
      diagnosticsTiming
    )

    html += `
      <article class="performance-timing">
        <h3>Performance - Overall</h3>
        <table>
          <tr><th>Total Response Time</th><td><strong>${timingInfo.overallDuration.toFixed(0)}ms</strong> (${overallSeconds}s)</td></tr>
          <tr><th>First Request Sent (UTC)</th><td>${timingInfo.overallRequestTimestamp}</td></tr>
          <tr><th>Last Response Received (UTC)</th><td>${timingInfo.overallResponseTimestamp}</td></tr>
          <tr><th>Request Payload</th><td><code>${requestPayload}</code></td></tr>
        </table>
        ${networkPathDetails}
        ${secondaryNetworkDiagnosticsDetails}
        ${networkDiagnosticsDetails}
      </article>
    `
  }

  // Validation
  if (results.validate) {
    const validateTiming = timingInfo?.apiCalls.find((c) => c.call === 'validate')
    html += `
      <article>
        <h3>Validation</h3>
        <table>
          <tr><th>Valid</th><td>${results.validate.valid ? '✓ Yes' : '✗ No'}</td></tr>
          <tr><th>Type</th><td>${results.validate.type}</td></tr>
          <tr><th>Address</th><td><code>${results.validate.address}</code></td></tr>
          <tr><th>IP Version</th><td>${results.validate.is_ipv4 ? 'IPv4' : 'IPv6'}</td></tr>
        </table>
        ${
          validateTiming
            ? `<details>
          <summary>API Call Timing</summary>
          <table>
            <tr><th>Duration</th><td><strong>${validateTiming.duration.toFixed(0)}ms</strong></td></tr>
            <tr><th>Request (UTC)</th><td>${validateTiming.requestTime}</td></tr>
            <tr><th>Response (UTC)</th><td>${validateTiming.responseTime}</td></tr>
          </table>
        </details>`
            : ''
        }
      </article>
    `
  }

  // Private check
  if (results.private) {
    const privateTiming = timingInfo?.apiCalls.find((c) => c.call === 'checkPrivate')
    html += `
      <article>
        <h3>Private Address Check</h3>
        <table>
          <tr><th>RFC1918 (Private)</th><td>${results.private.is_rfc1918 ? '✓ Yes' : '✗ No'}</td></tr>
          ${results.private.matched_rfc1918_range ? `<tr><th>Matched Range</th><td><code>${results.private.matched_rfc1918_range}</code></td></tr>` : ''}
          <tr><th>RFC6598 (Shared)</th><td>${results.private.is_rfc6598 ? '✓ Yes' : '✗ No'}</td></tr>
          ${results.private.matched_rfc6598_range ? `<tr><th>Matched Range</th><td><code>${results.private.matched_rfc6598_range}</code></td></tr>` : ''}
        </table>
        ${
          privateTiming
            ? `<details>
          <summary>API Call Timing</summary>
          <table>
            <tr><th>Duration</th><td><strong>${privateTiming.duration.toFixed(0)}ms</strong></td></tr>
            <tr><th>Request (UTC)</th><td>${privateTiming.requestTime}</td></tr>
            <tr><th>Response (UTC)</th><td>${privateTiming.responseTime}</td></tr>
          </table>
        </details>`
            : ''
        }
      </article>
    `
  }

  // Cloudflare check
  if (results.cloudflare) {
    const cloudflareTiming = timingInfo?.apiCalls.find((c) => c.call === 'checkCloudflare')
    html += `
      <article>
        <h3>Cloudflare Check</h3>
        <table>
          <tr><th>Is Cloudflare</th><td>${results.cloudflare.is_cloudflare ? '✓ Yes' : '✗ No'}</td></tr>
          <tr><th>IP Version</th><td>IPv${results.cloudflare.ip_version}</td></tr>
          ${results.cloudflare.matched_ranges ? `<tr><th>Matched Ranges</th><td><code>${results.cloudflare.matched_ranges.join(', ')}</code></td></tr>` : ''}
        </table>
        ${
          cloudflareTiming
            ? `<details>
          <summary>API Call Timing</summary>
          <table>
            <tr><th>Duration</th><td><strong>${cloudflareTiming.duration.toFixed(0)}ms</strong></td></tr>
            <tr><th>Request (UTC)</th><td>${cloudflareTiming.requestTime}</td></tr>
            <tr><th>Response (UTC)</th><td>${cloudflareTiming.responseTime}</td></tr>
          </table>
        </details>`
            : ''
        }
      </article>
    `
  }

  // Subnet info
  if (results.subnet) {
    const s = results.subnet
    const subnetTiming = timingInfo?.apiCalls.find((c) => c.call === 'subnetInfo')
    html += `
      <article>
        <h3>Subnet Information (${s.mode} Mode)</h3>
        <table>
          <tr><th>Network</th><td><code>${s.network}</code></td></tr>
          <tr><th>Network Address</th><td><code>${s.network_address}</code></td></tr>
          ${s.broadcast_address ? `<tr><th>Broadcast Address</th><td><code>${s.broadcast_address}</code></td></tr>` : ''}
          <tr><th>Netmask</th><td><code>${s.netmask}</code></td></tr>
          <tr><th>Wildcard Mask</th><td><code>${s.wildcard_mask}</code></td></tr>
          <tr><th>Prefix Length</th><td>/${s.prefix_length}</td></tr>
          <tr><th>Total Addresses</th><td>${s.total_addresses.toLocaleString()}</td></tr>
          <tr><th>Usable Addresses</th><td>${s.usable_addresses.toLocaleString()}</td></tr>
          <tr><th>First Usable IP</th><td><code>${s.first_usable_ip}</code></td></tr>
          <tr><th>Last Usable IP</th><td><code>${s.last_usable_ip}</code></td></tr>
          ${s.note ? `<tr><th>Note</th><td>${s.note}</td></tr>` : ''}
        </table>
        ${
          subnetTiming
            ? `<details>
          <summary>API Call Timing</summary>
          <table>
            <tr><th>Duration</th><td><strong>${subnetTiming.duration.toFixed(0)}ms</strong></td></tr>
            <tr><th>Request (UTC)</th><td>${subnetTiming.requestTime}</td></tr>
            <tr><th>Response (UTC)</th><td>${subnetTiming.responseTime}</td></tr>
          </table>
        </details>`
            : ''
        }
      </article>
    `
  }

  resultsContent.innerHTML = html
  showElement('results')
  hideLoading()
  hideElement('error')
}

/**
 * Show user authentication status
 */
export function showUserInfo(
  user: ClientPrincipal | null,
  authMethod: 'none' | 'jwt' | 'entraid' | 'gateway' | 'oidc'
): void {
  const userInfoDiv = document.getElementById('user-info')
  if (!userInfoDiv) return

  if (authMethod === 'none' || authMethod === 'jwt') {
    hideElement('user-info')
    return
  }

  if (user) {
    const displayName = getUserDisplayName(user)
    userInfoDiv.innerHTML = `
      <div class="user-display">
        <span class="user-icon">👤</span>
        <span class="user-name">${displayName}</span>
        <button id="logout-btn" class="logout-btn">Logout</button>
      </div>
    `
    showElement('user-info')

    // Attach logout handler
    const logoutBtn = document.getElementById('logout-btn')
    if (logoutBtn) {
      logoutBtn.addEventListener('click', () => {
        if (authMethod === 'oidc') {
          void logoutFromOidc(`${window.location.origin}/logged-out.html`)
          return
        }

        logout('/logged-out.html')
      })
    }
  } else {
    const loginLabel =
      authMethod === 'entraid' ? 'Login with Entra ID' : authMethod === 'oidc' ? 'Login with OIDC' : 'Login with SSO'

    userInfoDiv.innerHTML = `
      <div class="user-display">
        <button id="login-btn" class="login-btn">${loginLabel}</button>
      </div>
    `
    showElement('user-info')

    // Attach login handler
    const loginBtn = document.getElementById('login-btn')
    if (loginBtn) {
      loginBtn.addEventListener('click', () => {
        if (authMethod === 'oidc') {
          void loginWithOidc(window.location.pathname || '/')
          return
        }

        login(authMethod, window.location.pathname || '/')
      })
    }
  }
}
