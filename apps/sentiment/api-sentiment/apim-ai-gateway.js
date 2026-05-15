import { SentimentLabel, normalizeSentimentLabel } from './sentiment-label.js'

const DEFAULT_CONFIDENCE = 0.5
const SENTIMENT_SYSTEM_PROMPT =
  'You are a sentiment classifier. Return only compact JSON with keys "label" and "confidence". The "label" value must be exactly "positive", "negative", or "neutral". Example: {"label":"positive","confidence":0.9}.'

function clampConfidence(value, fallback = DEFAULT_CONFIDENCE) {
  const parsed = Number.parseFloat(String(value ?? ''))
  if (!Number.isFinite(parsed)) return fallback
  return Math.max(0, Math.min(1, parsed))
}

function stripJsonFence(value) {
  const trimmed = String(value || '').trim()
  const fenced = trimmed.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/i)
  return fenced ? fenced[1].trim() : trimmed
}

export function parseApimSentimentContent(content) {
  const text = String(content || '').trim()
  if (!text) {
    return {
      label: SentimentLabel.NEUTRAL,
      confidence: DEFAULT_CONFIDENCE,
    }
  }

  try {
    const payload = JSON.parse(stripJsonFence(text))
    const label = normalizeSentimentLabel(payload.label ?? payload.sentiment ?? payload.classification)
    const confidence = clampConfidence(payload.confidence ?? payload.score ?? payload.probability, 0.75)
    return { label, confidence }
  } catch {
    const label = normalizeSentimentLabel(text)
    const explicitLabel =
      text.toLowerCase().includes(SentimentLabel.POSITIVE) ||
      text.toLowerCase().includes(SentimentLabel.NEGATIVE) ||
      text.toLowerCase().includes(SentimentLabel.NEUTRAL)
    return {
      label,
      confidence: explicitLabel ? 0.7 : DEFAULT_CONFIDENCE,
    }
  }
}

export function extractChatCompletionContent(payload) {
  const choice = Array.isArray(payload?.choices) ? payload.choices[0] : undefined
  return (
    choice?.message?.content ??
    choice?.text ??
    payload?.output_text ??
    payload?.content ??
    ''
  )
}

export async function analyzeWithApimAiGateway(text, config, options = {}) {
  const fetchImpl = options.fetchImpl ?? globalThis.fetch
  if (!fetchImpl) {
    throw new Error('fetch is required for SENTIMENT_ANALYZER=apim-ai-gateway')
  }
  if (!config.sentimentApimAiGatewayUrl) {
    throw new Error('SENTIMENT_APIM_AI_GATEWAY_URL is required for SENTIMENT_ANALYZER=apim-ai-gateway')
  }

  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), config.sentimentApimAiGatewayTimeoutMs)
  const startedAt = Date.now()

  try {
    const headers = {
      Accept: 'application/json',
      'Content-Type': 'application/json',
    }
    if (config.sentimentApimSubscriptionKey) {
      headers['Ocp-Apim-Subscription-Key'] = config.sentimentApimSubscriptionKey
    }

    const response = await fetchImpl(config.sentimentApimAiGatewayUrl, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        model: config.sentimentApimAiGatewayModel,
        temperature: 0,
        max_tokens: 64,
        messages: [
          { role: 'system', content: SENTIMENT_SYSTEM_PROMPT },
          { role: 'user', content: text },
        ],
      }),
      signal: controller.signal,
    })

    const responseText = await response.text()
    if (!response.ok) {
      throw new Error(`APIM AI gateway returned ${response.status}: ${responseText.slice(0, 240)}`)
    }

    let payload
    try {
      payload = JSON.parse(responseText)
    } catch {
      payload = { content: responseText }
    }

    const parsed = parseApimSentimentContent(extractChatCompletionContent(payload))
    return {
      ...parsed,
      latency_ms: Date.now() - startedAt,
    }
  } finally {
    clearTimeout(timeout)
  }
}
