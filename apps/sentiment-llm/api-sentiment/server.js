import './telemetry.js'

import express from 'express'
import fs from 'node:fs/promises'
import { createReadStream } from 'node:fs'
import path from 'node:path'
import readline from 'node:readline'

import { SpanStatusCode, metrics, trace } from '@opentelemetry/api'
import apiLogs from '@opentelemetry/api-logs'

const app = express()
app.use(express.json({ limit: '1mb' }))

const { logs } = apiLogs

const tracer = trace.getTracer('sentiment-api')
const meter = metrics.getMeter('sentiment-api')
const llmLatencyMs = meter.createHistogram('llm_inference_latency_ms', {
  unit: 'ms',
})
const sentimentWrites = meter.createCounter('sentiment_comments_created_total')
const otelLogger = logs.getLogger('sentiment-api')

const port = Number.parseInt(process.env.PORT || '8080', 10)
const dataDir = process.env.DATA_DIR || '/data'
const csvPath = process.env.CSV_PATH || path.join(dataDir, 'comments.csv')

const llmGatewayMode = (process.env.LLM_GATEWAY_MODE || 'direct').toLowerCase()
const llmBaseUrl =
  process.env.LLM_BASE_URL ||
  (llmGatewayMode === 'litellm'
    ? process.env.LITELLM_BASE_URL || 'http://litellm:4000'
    : process.env.LLM_BACKEND_BASE_URL || 'http://host.docker.internal:12434/engines')
const llmModel =
  process.env.LLM_MODEL ||
  (llmGatewayMode === 'litellm'
    ? process.env.LITELLM_MODEL_ALIAS || 'sentiment-default'
    : 'auto')

let resolvedModel = null
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

async function resolveModelId() {
  if (llmModel !== 'auto') return llmModel
  if (resolvedModel) return resolvedModel

  const res = await fetch(`${llmBaseUrl}/v1/models`, {
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

function csvEscape(value) {
  const s = String(value ?? '')
  const escaped = s.replaceAll('"', '""')
  return `"${escaped}"`
}

function csvParseLine(line) {
  // Minimal CSV parser for: timestamp,text,label,confidence,latency_ms
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

async function ensureCsv() {
  await fs.mkdir(dataDir, { recursive: true })
  try {
    await fs.access(csvPath)
  } catch {
    await fs.writeFile(csvPath, 'timestamp,text,label,confidence,latency_ms\n', 'utf8')
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
  await fs.appendFile(csvPath, `${line}\n`, 'utf8')
}

async function readLastRecords(limit) {
  await ensureCsv()

  const records = []
  const rl = readline.createInterface({
    input: createReadStream(csvPath, { encoding: 'utf8' }),
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

  // Return newest first.
  records.sort((a, b) => (a.timestamp < b.timestamp ? 1 : -1))
  return records.slice(0, limit)
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

async function analyzeWithLlm(text) {
  return tracer.startActiveSpan(
    'llm.chat',
    {
      attributes: {
        'llm.model': llmModel,
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

        const res = await fetch(`${llmBaseUrl}/v1/chat/completions`, {
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
      } catch (e) {
        span.recordException(e)
        span.setStatus({
          code: SpanStatusCode.ERROR,
          message: e?.message || 'llm_error',
        })
        throw e
      } finally {
        span.end()
      }
    },
  )
}

app.get('/api/v1/health', async (_req, res) => {
  try {
    await ensureCsv()
    res.json({ status: 'ok' })
  } catch (e) {
    res.status(500).json({ status: 'error', error: e?.message || String(e) })
  }
})

app.get('/api/v1/comments', async (req, res) => {
  const limit = Math.max(1, Math.min(200, Number.parseInt(req.query.limit || '25', 10)))
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
  } catch (e) {
    res.status(500).json({ error: e?.message || String(e) })
  }
})

await ensureCsv()
app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`sentiment-api listening on :${port}`)
})
