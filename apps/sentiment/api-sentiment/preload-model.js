import fs from 'node:fs/promises'

import { env as transformersEnv, pipeline } from '@huggingface/transformers'
import { DEFAULT_SENTIMENT_MODEL_ID } from './config.js'

const modelId = process.env.SENTIMENT_MODEL_ID || DEFAULT_SENTIMENT_MODEL_ID
const cacheDir = process.env.SENTIMENT_MODEL_CACHE_DIR || '/opt/transformers-cache'

await fs.mkdir(cacheDir, { recursive: true })

transformersEnv.cacheDir = cacheDir
transformersEnv.allowRemoteModels = true

console.log(`preloading sentiment model ${modelId} into ${cacheDir}`)
const classifier = await pipeline('sentiment-analysis', modelId)
await classifier('warmup', { top_k: null })
console.log('sentiment model preloaded')
