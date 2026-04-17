import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react'
import { App } from './App.jsx'

const originalFetch = globalThis.fetch

function jsonResponse(body, status = 200) {
  return {
    ok: status >= 200 && status < 300,
    status,
    statusText: status === 200 ? 'OK' : 'Error',
    json: async () => body,
    text: async () => JSON.stringify(body),
  }
}

afterEach(() => {
  cleanup()
  vi.restoreAllMocks()
  if (originalFetch === undefined) {
    delete globalThis.fetch
  } else {
    globalThis.fetch = originalFetch
  }
})

describe('sentiment-auth-ui', () => {
  it('loads user info and recent comments on startup', async () => {
    const fetchMock = vi.fn(async (url) => {
      if (url === '/oauth2/userinfo') {
        return jsonResponse({ email: 'demo@dev.test' })
      }
      if (url === '/api/v1/comments?limit=25') {
        return jsonResponse({
          items: [
            {
              id: 'comment-1',
              label: 'positive',
              timestamp: '2026-03-15T12:00:00Z',
              text: 'Great work',
            },
          ],
        })
      }
      throw new Error(`Unhandled request: ${String(url)}`)
    })
    globalThis.fetch = fetchMock

    render(<App />)

    await expect(screen.findByText('demo@dev.test')).resolves.toBeInTheDocument()
    await expect(screen.findByText('Great work')).resolves.toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith('/oauth2/userinfo', { headers: { Accept: 'application/json' } })
  })

  it('populates the textarea from the sample buttons', async () => {
    globalThis.fetch = vi.fn(async (url) => {
      if (url === '/oauth2/userinfo') {
        return jsonResponse({ email: 'demo@dev.test' })
      }
      if (url === '/api/v1/comments?limit=25') {
        return jsonResponse({ items: [] })
      }
      throw new Error(`Unhandled request: ${String(url)}`)
    })

    render(<App />)

    const textarea = await screen.findByPlaceholderText(/Type a comment to analyze/i)
    fireEvent.click(screen.getByRole('button', { name: /Sample: Positive/i }))
    expect(textarea).toHaveValue('I absolutely love this. Great work and fantastic experience.')

    fireEvent.click(screen.getByRole('button', { name: /Sample: Mixed/i }))
    expect(textarea).toHaveValue('Some parts are fine, but overall I am disappointed and frustrated.')
  })

  it('posts a new comment and refreshes the recent list', async () => {
    let commentsRequestCount = 0
    const fetchMock = vi.fn(async (url, options) => {
      if (url === '/oauth2/userinfo') {
        return jsonResponse({ email: 'demo@dev.test' })
      }
      if (url === '/api/v1/comments?limit=25' && options === undefined) {
        commentsRequestCount += 1
        if (commentsRequestCount === 1) {
          return jsonResponse({ items: [] })
        }
        return jsonResponse({
          items: [
            {
              id: 'comment-2',
              label: 'positive',
              timestamp: '2026-03-15T12:10:00Z',
              text: 'Great work',
            },
          ],
        })
      }
      if (url === '/api/v1/comments' && options?.method === 'POST') {
        return jsonResponse({
          id: 'comment-2',
          label: 'positive',
          confidence: 0.991,
          latency_ms: 42,
          text: 'Great work',
        })
      }
      throw new Error(`Unhandled request: ${String(url)}`)
    })
    globalThis.fetch = fetchMock

    render(<App />)

    const textarea = await screen.findByPlaceholderText(/Type a comment to analyze/i)
    fireEvent.change(textarea, { target: { value: 'Great work' } })
    fireEvent.click(screen.getByRole('button', { name: /^Analyze$/i }))

    await waitFor(() => {
      expect(screen.getByText(/Saved\./i)).toBeInTheDocument()
    })
    expect(screen.getByText(/^positive$/i)).toBeInTheDocument()
    expect(screen.getByText(/Latency:/i)).toBeInTheDocument()
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/v1/comments',
      expect.objectContaining({
        method: 'POST',
      })
    )
  })
})
