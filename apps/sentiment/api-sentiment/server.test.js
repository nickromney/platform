import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'

import { createApp, detectMixedSignals, resolveClassifierResult, startServer } from './server.js'

async function withServer(options, run) {
  const runtime = createApp(options)
  await runtime.ensureCsv()

  const server = await new Promise((resolve) => {
    const instance = runtime.app.listen(0, () => resolve(instance))
  })

  const address = server.address()
  const baseUrl = `http://127.0.0.1:${address.port}`

  try {
    await run({ baseUrl, runtime })
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error)
          return
        }
        resolve()
      })
    })
  }
}

test('health creates the CSV store on first request', async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'sentiment-api-'))
  const csvPath = path.join(tempDir, 'comments.csv')

  await withServer({ dataDir: tempDir, csvPath }, async ({ baseUrl }) => {
    const response = await fetch(`${baseUrl}/api/v1/health`)

    assert.equal(response.status, 200)
    assert.deepEqual(await response.json(), { status: 'ok' })

    const csv = await fs.readFile(csvPath, 'utf8')
    assert.match(csv, /^timestamp,text,label,confidence,latency_ms/m)
  })
})

test('comments endpoint rejects empty text payloads', async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'sentiment-api-'))

  await withServer({ dataDir: tempDir }, async ({ baseUrl }) => {
    const response = await fetch(`${baseUrl}/api/v1/comments`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ text: '   ' }),
    })

    assert.equal(response.status, 400)
    assert.deepEqual(await response.json(), { error: 'text is required' })
  })
})

test('comments endpoints persist and return the newest records first', async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'sentiment-api-'))
  let counter = 0

  await withServer(
    {
      dataDir: tempDir,
      analyzeWithLlm: async (text) => {
        counter += 1
        return {
          label: counter === 1 ? 'positive' : 'negative',
          confidence: 0.95,
          latency_ms: 12,
          echoed: text,
        }
      },
    },
    async ({ baseUrl }) => {
      const firstResponse = await fetch(`${baseUrl}/api/v1/comments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: 'first comment' }),
      })
      const secondResponse = await fetch(`${baseUrl}/api/v1/comments`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text: 'second comment' }),
      })

      assert.equal(firstResponse.status, 200)
      assert.equal(secondResponse.status, 200)

      const listResponse = await fetch(`${baseUrl}/api/v1/comments?limit=1`)
      assert.equal(listResponse.status, 200)

      const payload = await listResponse.json()
      assert.equal(payload.items.length, 1)
      assert.equal(payload.items[0].text, 'second comment')
      assert.equal(payload.items[0].label, 'negative')
    },
  )
})

test('resolveClassifierResult returns neutral for near-even polar scores', () => {
  const result = resolveClassifierResult([
    { label: 'POSITIVE', score: 0.58 },
    { label: 'NEGATIVE', score: 0.42 },
  ])

  assert.equal(result.label, 'neutral')
  assert.equal(result.confidence, 0.84)
})

test('detectMixedSignals finds obvious mixed wording', () => {
  assert.equal(detectMixedSignals('Some parts are fine, but overall I am disappointed and frustrated.'), true)
  assert.equal(detectMixedSignals('I love how small and fast this is.'), false)
})

test('resolveClassifierResult can force neutral for mixed wording even with strong polar scores', () => {
  const result = resolveClassifierResult(
    [
      { label: 'NEGATIVE', score: 0.999 },
      { label: 'POSITIVE', score: 0.001 },
    ],
    {
      text: 'Some parts are fine, but overall I am disappointed and frustrated.',
    },
  )

  assert.equal(result.label, 'neutral')
  assert.equal(result.confidence, 0.65)
})

test('resolveClassifierResult preserves clear positive and negative outcomes', () => {
  const positive = resolveClassifierResult([
    { label: 'POSITIVE', score: 0.93 },
    { label: 'NEGATIVE', score: 0.07 },
  ])
  const negative = resolveClassifierResult([
    { label: 'NEGATIVE', score: 0.91 },
    { label: 'POSITIVE', score: 0.09 },
  ])

  assert.equal(positive.label, 'positive')
  assert.equal(positive.confidence, 0.93)
  assert.equal(negative.label, 'negative')
  assert.equal(negative.confidence, 0.91)
})

test('startServer warms the sentiment backend before listening', async () => {
  const tempDir = await fs.mkdtemp(path.join(os.tmpdir(), 'sentiment-api-'))
  let warmed = 0

  const runtime = await startServer({
    dataDir: tempDir,
    warmSentimentBackend: async () => {
      warmed += 1
    },
  })

  assert.equal(warmed, 1)

  await new Promise((resolve, reject) => {
    runtime.server.close((error) => {
      if (error) {
        reject(error)
        return
      }
      resolve()
    })
  })
})
