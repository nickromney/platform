import './telemetry.js'

import express from 'express'
import { createReadStream } from 'node:fs'
import fs from 'node:fs/promises'
import path from 'node:path'
import readline from 'node:readline'
import { pathToFileURL } from 'node:url'

import { SpanStatusCode, metrics, trace } from '@opentelemetry/api'
import apiLogs from '@opentelemetry/api-logs'

const { logs } = apiLogs

const tracer = trace.getTracer('sentiment-api')
const meter = metrics.getMeter('sentiment-api')
const llmLatencyMs = meter.createHistogram('llm_inference_latency_ms', {
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

function createConfig(options = {}) {
  const port = Number.parseInt(String(options.port ?? process.env.PORT ?? '8080'), 10)
  const dataDir = options.dataDir ?? process.env.DATA_DIR ?? '/data'
  const csvPath = options.csvPath ?? path.join(dataDir, 'comments.csv')
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
    llmGatewayMode,
    llmBaseUrl,
    llmModel,
  }
}

export function createApp(options = {}) {
  const config = createConfig(options)
  let resolvedModel = null

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

            llmLatencyMs.record(latencyMs, {
              'llm.model': modelId,
              'sentiment.label': label,
            })

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
      const { label, confidence, latency_ms } = await analyzeWithLlm(text)

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
    analyzeWithLlm,
  }
}

export async function startServer(options = {}) {
  const runtime = createApp(options)
  await runtime.ensureCsv()

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
