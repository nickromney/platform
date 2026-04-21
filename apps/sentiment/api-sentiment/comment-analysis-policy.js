import { SentimentLabel, normalizeSentimentLabel } from './sentiment-label.js'

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

function parseFiniteNumber(value, fallback) {
  const parsed = Number.parseFloat(String(value ?? ''))
  return Number.isFinite(parsed) ? parsed : fallback
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
    [SentimentLabel.POSITIVE]: 0,
    [SentimentLabel.NEGATIVE]: 0,
  }

  for (const entry of entries) {
    const label = normalizeSentimentLabel(entry?.label)
    const score = Number(entry?.score)
    if (
      (label === SentimentLabel.POSITIVE || label === SentimentLabel.NEGATIVE) &&
      Number.isFinite(score)
    ) {
      scores[label] = score
    }
  }

  const topLabel =
    scores[SentimentLabel.POSITIVE] >= scores[SentimentLabel.NEGATIVE]
      ? SentimentLabel.POSITIVE
      : SentimentLabel.NEGATIVE
  const topScore = scores[topLabel]
  const margin = Math.abs(scores[SentimentLabel.POSITIVE] - scores[SentimentLabel.NEGATIVE])
  const neutralMargin = parseFiniteNumber(options.neutralMargin, 0.45)
  const mixedSignals = detectMixedSignals(options.text)
  const label =
    mixedSignals || margin < neutralMargin ? SentimentLabel.NEUTRAL : topLabel
  const confidence = mixedSignals
    ? Math.max(0.65, 1 - margin / 2)
    : label === SentimentLabel.NEUTRAL
      ? Math.max(0.5, 1 - margin)
      : topScore

  return {
    label,
    confidence: Number(confidence.toFixed(3)),
    scores,
    margin,
  }
}

export const commentAnalysisPolicy = Object.freeze({
  detectMixedSignals,
  resolveClassifierResult,
})
