import { afterEach, describe, expect, it, vi } from 'vitest'
import { mountApp } from './app'

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

async function waitFor(assertion: () => void, timeoutMs = 1_000): Promise<void> {
  const deadline = Date.now() + timeoutMs
  let lastError: unknown

  while (Date.now() < deadline) {
    try {
      assertion()
      return
    } catch (error) {
      lastError = error
      await new Promise((resolve) => setTimeout(resolve, 10))
    }
  }

  throw lastError
}

function getRoot(): HTMLElement {
  document.body.innerHTML = '<div id="root"></div>'
  const root = document.getElementById('root')
  if (!root) {
    throw new Error('Missing root element')
  }
  return root
}

afterEach(() => {
  document.body.innerHTML = ''
  vi.restoreAllMocks()
})

describe('sentiment-auth-ui', () => {
  it('loads user info and recent comments on startup', async () => {
    const fetchMock = vi.fn(async (url: string) => {
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

    mountApp(getRoot(), {
      fetchImpl: fetchMock as unknown as typeof fetch,
      origin: 'https://sentiment.dev.test',
      navigate: vi.fn(),
    })

    await waitFor(() => {
      expect(document.body.textContent).toContain('demo@dev.test')
      expect(document.body.textContent).toContain('Great work')
    })

    expect(fetchMock).toHaveBeenCalledWith('/oauth2/userinfo', { headers: { Accept: 'application/json' } })
  })

  it('populates the textarea from the sample buttons', async () => {
    const fetchMock = vi.fn(async (url: string) => {
      if (url === '/oauth2/userinfo') {
        return jsonResponse({ email: 'demo@dev.test' })
      }
      if (url === '/api/v1/comments?limit=25') {
        return jsonResponse({ items: [] })
      }
      throw new Error(`Unhandled request: ${String(url)}`)
    })

    mountApp(getRoot(), {
      fetchImpl: fetchMock as unknown as typeof fetch,
      origin: 'https://sentiment.dev.test',
      navigate: vi.fn(),
    })

    await waitFor(() => {
      expect(document.querySelector('textarea')).not.toBeNull()
    })

    const positiveButton = document.querySelector<HTMLButtonElement>('[data-sample="positive"]')
    const mixedButton = document.querySelector<HTMLButtonElement>('[data-sample="mixed"]')
    if (!positiveButton || !mixedButton) {
      throw new Error('Expected sample controls to exist')
    }

    positiveButton.click()
    expect(document.querySelector<HTMLTextAreaElement>('textarea')?.value).toBe(
      'I absolutely love this. Great work and fantastic experience.',
    )

    mixedButton.click()
    expect(document.querySelector<HTMLTextAreaElement>('textarea')?.value).toBe(
      'Some parts are fine, but overall I am disappointed and frustrated.',
    )
  })

  it('posts a new comment and refreshes the recent list', async () => {
    let commentsRequestCount = 0
    const fetchMock = vi.fn(async (url: string, options?: RequestInit) => {
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

    mountApp(getRoot(), {
      fetchImpl: fetchMock as unknown as typeof fetch,
      origin: 'https://sentiment.dev.test',
      navigate: vi.fn(),
    })

    await waitFor(() => {
      expect(document.querySelector('textarea')).not.toBeNull()
    })

    const textarea = document.querySelector<HTMLTextAreaElement>('textarea')
    const analyzeButton = document.querySelector<HTMLButtonElement>('[data-action="analyze"]')

    if (!textarea || !analyzeButton) {
      throw new Error('Expected analyze controls to exist')
    }

    textarea.value = 'Great work'
    textarea.dispatchEvent(new Event('input', { bubbles: true }))
    analyzeButton.click()

    await waitFor(() => {
      expect(document.body.textContent).toContain('Saved.')
      expect(document.body.textContent).toContain('positive')
      expect(document.body.textContent).toContain('Latency: 42ms')
    })

    expect(fetchMock).toHaveBeenCalledWith(
      '/api/v1/comments',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({ text: 'Great work' }),
      }),
    )
  })
})
