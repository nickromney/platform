/**
 * @typedef {'positive' | 'negative' | 'neutral'} SentimentLabelValue
 */

export const SentimentLabel = Object.freeze({
  POSITIVE: 'positive',
  NEGATIVE: 'negative',
  NEUTRAL: 'neutral',
})

/**
 * @param {unknown} label
 * @returns {SentimentLabelValue}
 */
export function normalizeSentimentLabel(label) {
  const value = String(label || '').toLowerCase().trim()
  if (value === SentimentLabel.POSITIVE || value.startsWith(SentimentLabel.POSITIVE)) {
    return SentimentLabel.POSITIVE
  }
  if (value === SentimentLabel.NEGATIVE || value.startsWith(SentimentLabel.NEGATIVE)) {
    return SentimentLabel.NEGATIVE
  }
  if (value === SentimentLabel.NEUTRAL || value.startsWith(SentimentLabel.NEUTRAL)) {
    return SentimentLabel.NEUTRAL
  }
  if (value.includes(SentimentLabel.POSITIVE)) {
    return SentimentLabel.POSITIVE
  }
  if (value.includes(SentimentLabel.NEGATIVE)) {
    return SentimentLabel.NEGATIVE
  }
  return SentimentLabel.NEUTRAL
}
