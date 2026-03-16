import './telemetry.js'

import express from 'express'
import { createReadStream } from 'node:fs'
import fs from 'node:fs/promises'
import path from 'node:path'
import readline from 'node:readline'
import { pathToFileURL } from 'node:url'

import { env as transformersEnv, pipeline } from '@huggingface/transformers'
import { SpanStatusCode, metrics, trace } from '@opentelemetry/api'
import apiLogs from '@opentelemetry/api-logs'
import { DEFAULT_SENTIMENT_MODEL_ID } from './config.js'

const { logs } = apiLogs

const tracer = trace.getTracer('sentiment-api')
const meter = metrics.getMeter('sentiment-api')
const sentimentInferenceLatencyMs = meter.createHistogram('sentiment_inference_latency_ms', {
  unit: 'ms',
})
const sentimentWrites = meter.createCounter('sentiment_comments_created_total')
const otelLogger = logs.getLogger('sentiment-api')

const SENTIMENT_SYSTEM_PROMPT =
  'You are a sentiment classifier. Return exactly one lowercase label: positive, negative, or neutral. Use neutral when the text contains both positive and negative sentiment or mixed feelings. Return only the label.'
const SENTIMENT_EXAMPLES = [
  'Examples:',
  'Text: I love this product. It is excellent and delightful.',
  'Label: positive',
  'Text: This is awful, broken, and frustrating.',
  'Label: negative',
  'Text: Some parts are fine, but overall I am disappointed and frustrated.',
  'Label: neutral',
]
const POSITIVE_MIXED_CUES = [
  'love',
  'great',
  'excellent',
  'delightful',
  'fine',
  'good',
  'happy',
  'satisfied',
  'fast',
  'helpful',
  'amazing',
  'fantastic',
]
const NEGATIVE_MIXED_CUES = [
  'awful',
  'broken',
  'frustrating',
  'terrible',
  'refund',
  'disappointed',
  'frustrated',
  'bad',
  'hate',
  'poor',
  'angry',
]

function csvEscape(value) {
  const s = String(value ?? '')
  const escaped = s.replaceAll('"', '""')
  return `"${escaped}"`
}

function csvParseLine(line) {
  const out = []
  let cur = ''
  let inQuotes = false

  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (inQuotes) {
      if (ch === '"') {
        const next = line[i + 1]
        if (next === '"') {
          cur += '"'
          i++
        } else {
          inQuotes = false
        }
      } else {
        cur += ch
      }
      continue
    }

    if (ch === '"') {
      inQuotes = true
      continue
    }

    if (ch === ',') {
      out.push(cur)
      cur = ''
      continue
    }

    cur += ch
  }

  out.push(cur)
  return out
}

function normalizeLabel(label) {
  const s = String(label || '').toLowerCase().trim()
  if (s === 'positive' || s.startsWith('positive')) return 'positive'
  if (s === 'negative' || s.startsWith('negative')) return 'negative'
  if (s === 'neutral' || s.startsWith('neutral')) return 'neutral'
  if (s.includes('positive')) return 'positive'
  if (s.includes('negative')) return 'negative'
  return 'neutral'
}

function parseFiniteNumber(value, fallback) {
  const parsed = Number.parseFloat(String(value ?? ''))
  return Number.isFinite(parsed) ? parsed : fallback
}

function parseBoolean(value, fallback = false) {
  if (value === undefined || value === null || value === '') return fallback
  const normalized = String(value).trim().toLowerCase()
  if (['1', 'true', 'yes', 'on'].includes(normalized)) return true
  if (['0', 'false', 'no', 'off'].includes(normalized)) return false
  return fallback
}

function flattenClassifierOutput(output) {
  if (!Array.isArray(output)) return [output]
  return output.flatMap((item) => (Array.isArray(item) ? flattenClassifierOutput(item) : [item]))
}

function escapeRegex(value) {
  return value.replaceAll(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function containsCue(text, cues) {
  const source = String(text || '').toLowerCase()
  return cues.some((cue) => new RegExp(`\\b${escapeRegex(cue)}\\b`, 'i').test(source))
}

export function detectMixedSignals(text) {
  return containsCue(text, POSITIVE_MIXED_CUES) && containsCue(text, NEGATIVE_MIXED_CUES)
}

export function resolveClassifierResult(output, options = {}) {
  const entries = flattenClassifierOutput(output)
  const scores = {
    positive: 0,
    negative: 0,
  }

  for (const entry of entries) {
    const label = normalizeLabel(entry?.label)
    const score = Number(entry?.score)
    if ((label === 'positive' || label === 'negative') && Number.isFinite(score)) {
      scores[label] = score
    }
  }

  const topLabel = scores.positive >= scores.negative ? 'positive' : 'negative'
  const topScore = scores[topLabel]
  const margin = Math.abs(scores.positive - scores.negative)
  const neutralMargin = parseFiniteNumber(options.neutralMargin, 0.45)
  const mixedSignals = detectMixedSignals(options.text)
  const label = mixedSignals || margin < neutralMargin ? 'neutral' : topLabel
  const confidence = mixedSignals ? Math.max(0.65, 1 - margin / 2) : label === 'neutral' ? Math.max(0.5, 1 - margin) : topScore

  return {
    label,
    confidence: Number(confidence.toFixed(3)),
    scores,
    margin,
  }
}

function createConfig(options = {}) {
  const port = Number.parseInt(String(options.port ?? process.env.PORT ?? '8080'), 10)
  const dataDir = options.dataDir ?? process.env.DATA_DIR ?? '/data'
  const csvPath = options.csvPath ?? path.join(dataDir, 'comments.csv')
  const sentimentBackendMode = (options.sentimentBackendMode ?? process.env.SENTIMENT_BACKEND_MODE ?? 'sst').toLowerCase()
  const sentimentModelId =
    options.sentimentModelId ??
    process.env.SENTIMENT_MODEL_ID ??
    DEFAULT_SENTIMENT_MODEL_ID
  const sentimentModelCacheDir =
    options.sentimentModelCacheDir ?? process.env.SENTIMENT_MODEL_CACHE_DIR ?? path.join(dataDir, '.models')
  const sentimentModelLocalOnly = parseBoolean(
    options.sentimentModelLocalOnly ?? process.env.SENTIMENT_MODEL_LOCAL_ONLY,
    false,
  )
  const sentimentWarmOnStart = parseBoolean(
    options.sentimentWarmOnStart ?? process.env.SENTIMENT_WARM_ON_START,
    true,
  )
  const sentimentNeutralMargin = parseFiniteNumber(
    options.sentimentNeutralMargin ?? process.env.SENTIMENT_NEUTRAL_MARGIN,
    0.45,
  )
  const llmGatewayMode = (options.llmGatewayMode ?? process.env.LLM_GATEWAY_MODE ?? 'direct').toLowerCase()
  const llmBaseUrl =
    options.llmBaseUrl ??
    process.env.LLM_BASE_URL ??
    (llmGatewayMode === 'litellm'
      ? process.env.LITELLM_BASE_URL || 'http://litellm:4000'
      : process.env.LLM_BACKEND_BASE_URL || 'http://host.docker.internal:12434/engines')
  const llmModel =
    options.llmModel ??
    process.env.LLM_MODEL ??
    (llmGatewayMode === 'litellm' ? process.env.LITELLM_MODEL_ALIAS || 'sentiment-default' : 'auto')

  return {
    port,
    dataDir,
    csvPath,
    sentimentBackendMode,
    sentimentModelId,
    sentimentModelCacheDir,
    sentimentModelLocalOnly,
    sentimentWarmOnStart,
    sentimentNeutralMargin,
    llmGatewayMode,
    llmBaseUrl,
    llmModel,
  }
}

export function createApp(options = {}) {
  const config = createConfig(options)
  let resolvedModel = null
  let classifierPromise = null

  async function resolveModelId() {
    if (config.llmModel !== 'auto') return config.llmModel
    if (resolvedModel) return resolvedModel

    const res = await fetch(`${config.llmBaseUrl}/v1/models`, {
      headers: { 'Content-Type': 'application/json' },
    })
    if (!res.ok) {
      const msg = await res.text().catch(() => '')
      throw new Error(`llm models HTTP ${res.status}: ${msg}`)
    }

    const data = await res.json()
    const id = data?.data?.[0]?.id
    if (typeof id !== 'string' || !id.trim()) {
      throw new Error('llm models: failed to resolve model id from /v1/models')
    }

    resolvedModel = id
    return resolvedModel
  }

  async function ensureCsv() {
    await fs.mkdir(config.dataDir, { recursive: true })
    try {
      await fs.access(config.csvPath)
    } catch {
      await fs.writeFile(config.csvPath, 'timestamp,text,label,confidence,latency_ms\n', 'utf8')
    }
  }

  async function appendRecord(record) {
    const line = [
      csvEscape(record.timestamp),
      csvEscape(record.text),
      csvEscape(record.label),
      csvEscape(record.confidence),
      csvEscape(record.latency_ms),
    ].join(',')
    await fs.appendFile(config.csvPath, `${line}\n`, 'utf8')
  }

  async function readLastRecords(limit) {
    await ensureCsv()

    const records = []
    const rl = readline.createInterface({
      input: createReadStream(config.csvPath, { encoding: 'utf8' }),
      crlfDelay: Number.POSITIVE_INFINITY,
    })

    let isHeader = true
    for await (const line of rl) {
      if (isHeader) {
        isHeader = false
        continue
      }
      if (!line.trim()) continue
      const [timestamp, text, label, confidence, latencyMs] = csvParseLine(line)
      records.push({
        timestamp,
        text,
        label,
        confidence: Number.parseFloat(confidence),
        latency_ms: Number.parseInt(latencyMs, 10),
      })
    }

    records.sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1))
    return records.slice(0, limit)
  }

  async function getClassifier() {
    if (!classifierPromise) {
      classifierPromise = (async () => {
        await fs.mkdir(config.sentimentModelCacheDir, { recursive: true })
        transformersEnv.cacheDir = config.sentimentModelCacheDir
        transformersEnv.allowRemoteModels = !config.sentimentModelLocalOnly
        return await pipeline('sentiment-analysis', config.sentimentModelId)
      })()
    }

    return await classifierPromise
  }

  const analyzeWithSst =
    options.analyzeWithSst ??
    (async (text) =>
      tracer.startActiveSpan(
        'sentiment.classify',
        {
          attributes: {
            'sentiment.backend': 'sst',
            'sentiment.model': config.sentimentModelId,
          },
        },
        async (span) => {
          const start = Date.now()
          try {
            const classifier = await getClassifier()
            const output = await classifier(text, { top_k: null })
            const result = resolveClassifierResult(output, {
              neutralMargin: config.sentimentNeutralMargin,
              text,
            })
            const latencyMs = Date.now() - start

            sentimentInferenceLatencyMs.record(latencyMs, {
              'sentiment.backend': 'sst',
              'sentiment.label': result.label,
            })

            span.setAttribute('sentiment.latency_ms', latencyMs)
            span.setAttribute('sentiment.label', result.label)
            span.setAttribute('sentiment.confidence', result.confidence)
            span.setAttribute('sentiment.score.positive', result.scores.positive)
            span.setAttribute('sentiment.score.negative', result.scores.negative)

            otelLogger.emit({
              severityText: 'INFO',
              body: 'sst sentiment inference complete',
              attributes: {
                'sentiment.backend': 'sst',
                'sentiment.model': config.sentimentModelId,
                'sentiment.label': result.label,
              },
            })

            return {
              label: result.label,
              confidence: result.confidence,
              latency_ms: latencyMs,
            }
          } catch (error) {
            span.recordException(error)
            span.setStatus({
              code: SpanStatusCode.ERROR,
              message: error?.message || 'sst_error',
            })
            throw error
          } finally {
            span.end()
          }
        },
      ))

  const analyzeWithLlm =
    options.analyzeWithLlm ??
    (async (text) =>
      tracer.startActiveSpan(
        'llm.chat',
        {
          attributes: {
            'llm.model': config.llmModel,
          },
        },
        async (span) => {
          const start = Date.now()
          try {
            const modelId = await resolveModelId()
            const body = {
              model: modelId,
              stream: false,
              temperature: 0,
              max_tokens: 8,
              messages: [
                {
                  role: 'system',
                  content: SENTIMENT_SYSTEM_PROMPT,
                },
                {
                  role: 'user',
                  content: [...SENTIMENT_EXAMPLES, '', `Text: ${text}`, 'Label:'].join('\n'),
                },
              ],
            }

            const res = await fetch(`${config.llmBaseUrl}/v1/chat/completions`, {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(body),
            })

            const latencyMs = Date.now() - start
            span.setAttribute('llm.latency_ms', latencyMs)

            if (!res.ok) {
              const msg = await res.text().catch(() => '')
              throw new Error(`llm HTTP ${res.status}: ${msg}`)
            }

            const data = await res.json()
            const content = data?.choices?.[0]?.message?.content
            const raw = typeof content === 'string' ? content.trim() : ''
            const label = normalizeLabel(raw)
            const confidence = raw === label ? 1 : 0.75

            sentimentInferenceLatencyMs.record(latencyMs, {
              'sentiment.backend': 'llm',
              'llm.model': modelId,
              'sentiment.label': label,
            })

            span.setAttribute('sentiment.backend', 'llm')
            span.setAttribute('sentiment.label', label)
            span.setAttribute('sentiment.confidence', confidence)

            otelLogger.emit({
              severityText: 'INFO',
              body: 'llm sentiment inference complete',
              attributes: {
                'llm.model': modelId,
                'sentiment.label': label,
              },
            })

            return { label, confidence, latency_ms: latencyMs }
          } catch (error) {
            span.recordException(error)
            span.setStatus({
              code: SpanStatusCode.ERROR,
              message: error?.message || 'llm_error',
            })
            throw error
          } finally {
            span.end()
          }
        },
      ))

  const analyzeSentiment =
    options.analyzeSentiment ??
    options.analyzeWithLlm ??
    (config.sentimentBackendMode === 'llm' ? analyzeWithLlm : analyzeWithSst)

  const warmSentimentBackend =
    options.warmSentimentBackend ??
    (async () => {
      if (config.sentimentBackendMode === 'llm' || !config.sentimentWarmOnStart) {
        return
      }

      const classifier = await getClassifier()
      await classifier('warmup', { top_k: null })
    })

  const app = express()
  app.use(express.json({ limit: '1mb' }))

  app.get('/api/v1/health', async (_req, res) => {
    try {
      await ensureCsv()
      res.json({ status: 'ok' })
    } catch (error) {
      res.status(500).json({ status: 'error', error: error?.message || String(error) })
    }
  })

  app.get('/api/v1/comments', async (req, res) => {
    const limit = Math.max(1, Math.min(200, Number.parseInt(String(req.query.limit || '25'), 10)))
    const items = await readLastRecords(limit)
    res.json({ items })
  })

  app.post('/api/v1/comments', async (req, res) => {
    try {
      const text = req.body?.text
      if (typeof text !== 'string' || !text.trim()) {
        res.status(400).json({ error: 'text is required' })
        return
      }

      await ensureCsv()
      const timestamp = new Date().toISOString()
      const { label, confidence, latency_ms } = await analyzeSentiment(text)

      const record = {
        timestamp,
        text,
        label,
        confidence,
        latency_ms,
      }

      await appendRecord(record)
      sentimentWrites.add(1, {
        'sentiment.label': record.label,
      })
      res.json(record)
    } catch (error) {
      res.status(500).json({ error: error?.message || String(error) })
    }
  })

  return {
    app,
    config,
    ensureCsv,
    readLastRecords,
    appendRecord,
    analyzeSentiment,
    analyzeWithSst,
    analyzeWithLlm,
    warmSentimentBackend,
  }
}

export async function startServer(options = {}) {
  const runtime = createApp(options)
  await runtime.ensureCsv()
  await runtime.warmSentimentBackend()

  return await new Promise((resolve) => {
    const server = runtime.app.listen(runtime.config.port, () => {
      resolve({ ...runtime, server })
    })
  })
}

const isEntrypoint = process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href

if (isEntrypoint) {
  try {
    const { config } = await startServer()
    // eslint-disable-next-line no-console
    console.log(`sentiment-api listening on :${config.port}`)
  } catch (error) {
    // eslint-disable-next-line no-console
    console.error(error)
    process.exitCode = 1
  }
}
