const SAMPLE_TEXTS = {
  positive: 'I absolutely love this. Great work and fantastic experience.',
  negative: 'This is terrible. I want a refund and I will not use this again.',
  mixed: 'Some parts are fine, but overall I am disappointed and frustrated.',
} as const

type SampleKey = keyof typeof SAMPLE_TEXTS

type StatusState = 'idle' | 'loading' | 'ok' | 'error'

type Status = {
  state: StatusState
  message: string
}

type CommentItem = {
  id?: unknown
  label?: unknown
  timestamp?: unknown
  text?: unknown
}

type AnalyzeResult = {
  label?: unknown
  confidence?: number
  latency_ms?: number
  text?: unknown
}

type CommentsResponse = {
  items?: CommentItem[]
}

type UserInfo = Record<string, unknown> | string | null

type AppState = {
  text: string
  userInfo: UserInfo
  status: Status
  lastResult: AnalyzeResult | null
  comments: CommentItem[]
}

export type MountAppOptions = {
  fetchImpl?: typeof fetch
  origin?: string
  navigate?: (url: string) => void
}

type Child = Node | string | null | undefined

const INITIAL_STATE: AppState = {
  text: '',
  userInfo: null,
  status: { state: 'idle', message: '' },
  lastResult: null,
  comments: [],
}

export function toDisplay(value: unknown): string {
  if (value === null || value === undefined) return ''
  if (typeof value === 'string') return value
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  if (typeof value === 'object' && value !== null && 'text' in value && typeof value.text === 'string') {
    return value.text
  }
  try {
    return JSON.stringify(value)
  } catch {
    return String(value)
  }
}

async function httpJson<T>(fetchImpl: typeof fetch, url: string, options?: RequestInit): Promise<T> {
  const response = options ? await fetchImpl(url, options) : await fetchImpl(url)
  const text = await response.text()

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${text || response.statusText}`)
  }

  return text ? (JSON.parse(text) as T) : (null as T)
}

function appendChildren(parent: HTMLElement, children: Child[]): void {
  for (const child of children) {
    if (child === null || child === undefined) {
      continue
    }
    parent.append(child instanceof Node ? child : parent.ownerDocument.createTextNode(child))
  }
}

function createElement<K extends keyof HTMLElementTagNameMap>(
  documentRef: Document,
  tagName: K,
  options: {
    className?: string
    text?: string
    attrs?: Record<string, string>
    children?: Child[]
    onClick?: () => void
    onInput?: (event: Event) => void
  } = {},
): HTMLElementTagNameMap[K] {
  const element = documentRef.createElement(tagName)

  if (options.className) {
    element.className = options.className
  }

  if (options.text !== undefined) {
    element.textContent = options.text
  }

  if (options.attrs) {
    for (const [name, value] of Object.entries(options.attrs)) {
      element.setAttribute(name, value)
    }
  }

  if (options.children) {
    appendChildren(element, options.children)
  }

  if (options.onClick) {
    element.addEventListener('click', options.onClick)
  }

  if (options.onInput) {
    element.addEventListener('input', options.onInput)
  }

  return element
}

function createCommentItem(
  documentRef: Document,
  item: CommentItem,
  fallbackKey: string,
): HTMLDivElement {
  const label = toDisplay(item.label) || 'unknown'
  const timestamp = toDisplay(item.timestamp)
  const text = toDisplay(item.text)
  const key = toDisplay(item.id) || timestamp || fallbackKey

  const itemElement = createElement(documentRef, 'div', { className: 'item', attrs: { 'data-comment-key': key } })
  const meta = createElement(documentRef, 'div', { className: 'meta' })
  const labelClass = label === 'positive' ? 'mono ok' : label === 'negative' ? 'mono bad' : 'mono'
  const labelElement = createElement(documentRef, 'span', { className: labelClass, text: label })
  const timestampElement = createElement(documentRef, 'span', { className: 'mono', text: timestamp })
  const textElement = createElement(documentRef, 'div', { className: 'text', text })

  meta.append(labelElement, timestampElement)
  itemElement.append(meta, textElement)
  return itemElement
}

// Build the UI tree with DOM nodes so API-returned text never gets interpolated into innerHTML.
function buildApp(
  documentRef: Document,
  state: AppState,
  origin: string,
  actions: {
    logout: () => void
    refreshComments: () => void
    analyze: () => void
    setSample: (sample: SampleKey) => void
    updateText: (value: string) => void
  },
): HTMLDivElement {
  const container = createElement(documentRef, 'div', { className: 'container' })
  const header = createElement(documentRef, 'div', { className: 'header' })
  const headerText = createElement(documentRef, 'div')
  const title = createElement(documentRef, 'div', { className: 'title', text: 'Sentiment Analysis (Authenticated UI)' })
  const subtitle = createElement(documentRef, 'div', {
    className: 'subtitle',
    children: [
      'Forced login via ',
      createElement(documentRef, 'code', { className: 'mono', text: 'oauth2-proxy' }),
      ' + OIDC. API calls go to ',
      createElement(documentRef, 'code', { className: 'mono', text: '/api' }),
      ' via APIM.',
    ],
  })
  headerText.append(title, subtitle)

  const pill = createElement(documentRef, 'div', { className: 'pill' })
  const userDisplayValue =
    (typeof state.userInfo === 'string' ? state.userInfo : null) ||
    (state.userInfo && typeof state.userInfo === 'object' ? toDisplay(state.userInfo.email) : '') ||
    (state.userInfo && typeof state.userInfo === 'object' ? toDisplay(state.userInfo.preferred_username) : '') ||
    (state.userInfo && typeof state.userInfo === 'object' ? toDisplay(state.userInfo.user) : '') ||
    (state.userInfo && typeof state.userInfo === 'object' ? toDisplay(state.userInfo.text) : '') ||
    'authenticated'
  pill.append(
    createElement(documentRef, 'span', { text: 'User:' }),
    createElement(documentRef, 'strong', { text: userDisplayValue }),
    createElement(documentRef, 'button', {
      className: 'btn danger',
      text: 'Logout',
      attrs: { type: 'button', 'data-action': 'logout' },
      onClick: actions.logout,
    }),
  )

  header.append(headerText, pill)

  const grid = createElement(documentRef, 'div', { className: 'grid' })
  const analyzePanel = createElement(documentRef, 'div', { className: 'panel' })
  analyzePanel.append(createElement(documentRef, 'h3', { text: 'Analyze & Save' }))

  const textarea = createElement(documentRef, 'textarea', {
    attrs: { placeholder: 'Type a comment to analyze…' },
    onInput: (event) => {
      const target = event.currentTarget
      if (target instanceof HTMLTextAreaElement) {
        actions.updateText(target.value)
      }
    },
  })
  textarea.value = state.text
  analyzePanel.append(textarea)

  const row = createElement(documentRef, 'div', { className: 'row' })
  const sampleButtons = createElement(documentRef, 'div', { className: 'left' })
  ;(['positive', 'negative', 'mixed'] as const).forEach((sample) => {
    sampleButtons.append(
      createElement(documentRef, 'button', {
        className: 'btn',
        text: `Sample: ${sample.charAt(0).toUpperCase()}${sample.slice(1)}`,
        attrs: { type: 'button', 'data-sample': sample },
        onClick: () => actions.setSample(sample),
      }),
    )
  })

  const analyzeActions = createElement(documentRef, 'div', { className: 'left' })
  analyzeActions.append(
    createElement(documentRef, 'button', {
      className: 'btn primary',
      text: 'Analyze',
      attrs: {
        type: 'button',
        'data-action': 'analyze',
        ...(state.status.state === 'loading' ? { disabled: 'disabled' } : {}),
      },
      onClick: actions.analyze,
    }),
  )
  row.append(sampleButtons, analyzeActions)
  analyzePanel.append(row)

  const statusCard = createElement(documentRef, 'div', { className: 'status' })
  const resultBlock = createElement(documentRef, 'div')
  const classification = toDisplay(state.lastResult?.label)
  const classificationClass =
    classification === 'positive' ? 'value ok' : classification === 'negative' ? 'value bad' : 'value'
  const resultFootnote = createElement(documentRef, 'div', { className: 'footnote' })

  if (typeof state.lastResult?.confidence === 'number') {
    resultFootnote.append(
      'Confidence: ',
      createElement(documentRef, 'code', {
        className: 'mono',
        text: state.lastResult.confidence.toFixed(3),
      }),
    )
  } else {
    resultFootnote.textContent = 'No result yet'
  }

  if (typeof state.lastResult?.latency_ms === 'number') {
    resultFootnote.append(
      ' · Latency: ',
      createElement(documentRef, 'code', {
        className: 'mono',
        text: `${state.lastResult.latency_ms}ms`,
      }),
    )
  }

  resultBlock.append(
    createElement(documentRef, 'div', { className: 'label', text: 'Last result' }),
    createElement(documentRef, 'div', { className: classificationClass, text: classification || '—' }),
    resultFootnote,
  )

  const statusTag = createElement(documentRef, 'div', { className: 'tag' })
  statusTag.append(
    createElement(documentRef, 'span', { text: 'Status:' }),
    createElement(documentRef, 'strong', { text: state.status.state }),
    createElement(documentRef, 'span', { className: 'mono', text: toDisplay(state.status.message) }),
  )
  statusCard.append(resultBlock, statusTag)
  analyzePanel.append(statusCard)

  const curlExample = `curl -sk -X POST "${origin}/api/v1/comments" -H "Content-Type: application/json" -d '${JSON.stringify({ text: 'hello' })}'`
  const curlFootnote = createElement(documentRef, 'div', { className: 'footnote' })
  curlFootnote.append(
    'Curl example:',
    createElement(documentRef, 'div', {
      className: 'mono',
      children: [createElement(documentRef, 'code', { text: curlExample })],
    }),
  )
  analyzePanel.append(curlFootnote)

  const commentsPanel = createElement(documentRef, 'div', { className: 'panel' })
  commentsPanel.append(createElement(documentRef, 'h3', { text: 'Recent Comments' }))

  const refreshRow = createElement(documentRef, 'div', { className: 'row', attrs: { style: 'margin-top: 0' } })
  const refreshActions = createElement(documentRef, 'div', { className: 'left' })
  refreshActions.append(
    createElement(documentRef, 'button', {
      className: 'btn',
      text: 'Refresh',
      attrs: { type: 'button', 'data-action': 'refresh' },
      onClick: actions.refreshComments,
    }),
  )
  refreshRow.append(refreshActions)
  commentsPanel.append(refreshRow)

  const list = createElement(documentRef, 'div', { className: 'list', attrs: { style: 'margin-top: 10px' } })
  if (state.comments.length === 0) {
    const emptyItem = createElement(documentRef, 'div', { className: 'item' })
    const meta = createElement(documentRef, 'div', { className: 'meta' })
    meta.append(
      createElement(documentRef, 'span', { text: 'No items yet' }),
      createElement(documentRef, 'span', { className: 'mono', text: '/api/v1/comments' }),
    )
    emptyItem.append(meta)
    list.append(emptyItem)
  } else {
    state.comments.forEach((comment, index) => {
      list.append(createCommentItem(documentRef, comment, String(index)))
    })
  }

  commentsPanel.append(list)
  grid.append(analyzePanel, commentsPanel)
  container.append(header, grid)
  return container
}

export function mountApp(root: HTMLElement, options: MountAppOptions = {}): void {
  const documentRef = root.ownerDocument
  const fetchImpl = options.fetchImpl ?? globalThis.fetch?.bind(globalThis)

  if (!fetchImpl) {
    throw new Error('fetch is required to mount the app')
  }

  const origin = options.origin ?? window.location.origin
  const navigate = options.navigate ?? ((url: string) => window.location.assign(url))
  const state: AppState = structuredClone(INITIAL_STATE)

  const render = () => {
    root.replaceChildren(
      buildApp(documentRef, state, origin, {
        logout: () => {
          const redirect = encodeURIComponent('/oauth2/sign_in')
          navigate(`${origin}/oauth2/sign_out?rd=${redirect}`)
        },
        refreshComments: () => {
          void loadComments()
        },
        analyze: () => {
          void analyze()
        },
        setSample: (sample) => {
          state.text = SAMPLE_TEXTS[sample]
          render()
        },
        updateText: (value) => {
          state.text = value
        },
      }),
    )
  }

  const loadUserInfo = async () => {
    try {
      const response = await fetchImpl('/oauth2/userinfo', { headers: { Accept: 'application/json' } })
      if (!response.ok) {
        return
      }
      state.userInfo = (await response.json()) as UserInfo
      render()
    } catch {
      // oauth2-proxy already enforced authentication; missing userinfo should not break the UI.
    }
  }

  const loadComments = async () => {
    try {
      const response = await httpJson<CommentsResponse>(fetchImpl, '/api/v1/comments?limit=25')
      state.comments = response?.items ?? []
    } catch (error) {
      state.status = {
        state: 'error',
        message: error instanceof Error ? error.message : String(error),
      }
    } finally {
      render()
    }
  }

  const analyze = async () => {
    const trimmed = state.text.trim()
    if (!trimmed) {
      return
    }

    state.status = { state: 'loading', message: 'Analyzing…' }
    render()

    try {
      state.lastResult = await httpJson<AnalyzeResult>(fetchImpl, '/api/v1/comments', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: trimmed }),
      })
      await loadComments()
      state.status = { state: 'ok', message: 'Saved.' }
    } catch (error) {
      state.status = {
        state: 'error',
        message: error instanceof Error ? error.message : String(error),
      }
    } finally {
      render()
    }
  }

  render()
  void loadUserInfo()
  void loadComments()
}
