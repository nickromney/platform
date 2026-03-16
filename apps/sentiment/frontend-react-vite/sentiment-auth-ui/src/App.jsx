import React, { useEffect, useMemo, useState } from 'react'

const SAMPLE_TEXTS = {
  positive: 'I absolutely love this. Great work and fantastic experience.',
  negative: 'This is terrible. I want a refund and I will not use this again.',
  mixed: 'Some parts are fine, but overall I am disappointed and frustrated.',
}

function toDisplay(value) {
  if (value === null || value === undefined) return ''
  if (typeof value === 'string') return value
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  if (typeof value === 'object' && typeof value.text === 'string') return value.text
  try {
    return JSON.stringify(value)
  } catch {
    return String(value)
  }
}

async function httpJson(url, options = {}) {
  const res = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(options.headers || {}),
    },
  })
  const text = await res.text()
  if (!res.ok) {
    throw new Error(`HTTP ${res.status}: ${text || res.statusText}`)
  }
  return text ? JSON.parse(text) : null
}

export function App() {
  const origin = window.location.origin
  const [text, setText] = useState('')
  const [userInfo, setUserInfo] = useState(null)
  const [status, setStatus] = useState({ state: 'idle', message: '' })
  const [lastResult, setLastResult] = useState(null)
  const [comments, setComments] = useState([])

  const apiBase = ''

  async function logout() {
    const rd = encodeURIComponent('/oauth2/sign_in')
    window.location.href = `${origin}/oauth2/sign_out?rd=${rd}`
  }

  const curlExample = useMemo(() => {
    const payload = JSON.stringify({ text: 'hello' })
    return `curl -sk -X POST "${origin}/api/v1/comments" -H "Content-Type: application/json" -d '${payload}'`
  }, [origin])

  async function loadUserInfo() {
    try {
      // oauth2-proxy exposes this endpoint.
      const res = await fetch('/oauth2/userinfo', { headers: { Accept: 'application/json' } })
      if (!res.ok) return
      const data = await res.json()
      setUserInfo(data)
    } catch {
      // Ignore; user is still authenticated (forced by oauth2-proxy).
    }
  }

  async function loadComments() {
    try {
      const data = await httpJson(`${apiBase}/api/v1/comments?limit=25`)
      setComments(data?.items || [])
    } catch (e) {
      setStatus({ state: 'error', message: e.message })
    }
  }

  async function analyze() {
    const trimmed = text.trim()
    if (!trimmed) return
    setStatus({ state: 'loading', message: 'Analyzing…' })
    try {
      const result = await httpJson(`${apiBase}/api/v1/comments`, {
        method: 'POST',
        body: JSON.stringify({ text: trimmed }),
      })
      setLastResult(result)
      await loadComments()
      setStatus({ state: 'ok', message: 'Saved.' })
    } catch (e) {
      setStatus({ state: 'error', message: e.message })
    }
  }

  useEffect(() => {
    void loadUserInfo()
    void loadComments()
  }, [])

  const label = toDisplay(lastResult?.label)
  const confidence = lastResult?.confidence
  const latencyMs = lastResult?.latency_ms
  const classification = label
  const classificationClass = classification === 'positive' ? 'ok' : classification === 'negative' ? 'bad' : ''

  const userDisplayValue =
    (typeof userInfo === 'string' ? userInfo : null) || userInfo?.email || userInfo?.preferred_username || userInfo?.user || userInfo?.text || 'authenticated'

  const userDisplay = toDisplay(userDisplayValue) || 'authenticated'

  return (
    <div className="container">
      <div className="header">
        <div>
          <div className="title">Sentiment Analysis (Authenticated UI)</div>
          <div className="subtitle">
            Forced login via <code className="mono">oauth2-proxy</code> + OIDC. API calls go to <code className="mono">/api</code> via APIM.
          </div>
        </div>
        <div className="pill">
          <span>User:</span>
          <strong>{userDisplay}</strong>
          <button className="btn danger" type="button" onClick={logout}>
            Logout
          </button>
        </div>
      </div>

      <div className="grid">
        <div className="panel">
          <h3>Analyze & Save</h3>
          <textarea value={text} onChange={(e) => setText(e.target.value)} placeholder="Type a comment to analyze…" />
          <div className="row">
            <div className="left">
              <button className="btn" type="button" onClick={() => setText(SAMPLE_TEXTS.positive)}>
                Sample: Positive
              </button>
              <button className="btn" type="button" onClick={() => setText(SAMPLE_TEXTS.negative)}>
                Sample: Negative
              </button>
              <button className="btn" type="button" onClick={() => setText(SAMPLE_TEXTS.mixed)}>
                Sample: Mixed
              </button>
            </div>
            <div className="left">
              <button className="btn primary" type="button" onClick={analyze} disabled={status.state === 'loading'}>
                Analyze
              </button>
            </div>
          </div>

          <div className="status">
            <div>
              <div className="label">Last result</div>
              <div className={`value ${classificationClass}`}>{classification || '—'}</div>
              <div className="footnote">
                {typeof confidence === 'number' ? (
                  <>
                    Confidence: <code className="mono">{confidence.toFixed(3)}</code>
                  </>
                ) : (
                  'No result yet'
                )}
                {typeof latencyMs === 'number' ? (
                  <>
                    {' '}
                    · Latency: <code className="mono">{latencyMs}ms</code>
                  </>
                ) : null}
              </div>
            </div>
            <div className="tag">
              <span>Status:</span>
              <strong>{status.state}</strong>
              <span className="mono">{toDisplay(status.message)}</span>
            </div>
          </div>

          <div className="footnote">
            Curl example:
            <div className="mono">
              <code>
                {curlExample}
              </code>
            </div>
          </div>
        </div>

        <div className="panel">
          <h3>Recent Comments</h3>
          <div className="row" style={{ marginTop: 0 }}>
            <div className="left">
              <button className="btn" type="button" onClick={loadComments}>
                Refresh
              </button>
            </div>
          </div>
          <div className="list" style={{ marginTop: 10 }}>
            {comments.length === 0 ? (
              <div className="item">
                <div className="meta">
                  <span>No items yet</span>
                  <span className="mono">/api/v1/comments</span>
                </div>
              </div>
            ) : (
              comments.map((c, idx) => {
                const cLabel = toDisplay(c?.label) || 'unknown'
                const cTimestamp = toDisplay(c?.timestamp)
                const cText = toDisplay(c?.text)
                const cKey = toDisplay(c?.id) || cTimestamp || `${idx}`

                return (
                  <div className="item" key={cKey}>
                  <div className="meta">
                    <span className={`mono ${cLabel === 'positive' ? 'ok' : cLabel === 'negative' ? 'bad' : ''}`}>
                      {cLabel}
                    </span>
                    <span className="mono">{cTimestamp}</span>
                  </div>
                  <div className="text">{cText}</div>
                </div>
                )
              })
            )}
          </div>
        </div>
      </div>
    </div>
  )
}
