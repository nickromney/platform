import test from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs/promises'
import os from 'node:os'
import path from 'node:path'

import { createApp } from './server.js'

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
