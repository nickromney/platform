package app

import (
	"strings"
	"time"
)

var positiveWords = []string{"love", "great", "fantastic", "excellent", "useful", "small", "fast", "clear", "good", "happy", "fine"}
var negativeWords = []string{"disappointed", "frustrated", "bad", "slow", "broken", "hate", "poor", "awful", "terrible", "angry"}
var mixedMarkers = []string{" but ", "however", "although", "though", "overall"}

func classify(text string) classifyResponse {
	start := time.Now()
	lower := " " + strings.ToLower(text) + " "
	positive := countMatches(lower, positiveWords)
	negative := countMatches(lower, negativeWords)
	mixed := hasAny(lower, mixedMarkers) && positive > 0 && negative > 0

	label := Neutral
	confidence := 0.65
	switch {
	case mixed:
		label = Neutral
		confidence = 0.65
	case positive > negative:
		label = Positive
		confidence = confidenceFor(positive, negative)
	case negative > positive:
		label = Negative
		confidence = confidenceFor(negative, positive)
	}

	return classifyResponse{
		Text:       text,
		Label:      label,
		Confidence: confidence,
		LatencyMS:  max(1, time.Since(start).Milliseconds()),
	}
}

func countMatches(text string, words []string) int {
	count := 0
	for _, word := range words {
		if strings.Contains(text, word) {
			count++
		}
	}
	return count
}

func hasAny(text string, markers []string) bool {
	for _, marker := range markers {
		if strings.Contains(text, marker) {
			return true
		}
	}
	return false
}

func confidenceFor(winning, losing int) float64 {
	score := 0.7 + float64(winning-losing)*0.1
	if score > 0.97 {
		return 0.97
	}
	if score < 0.7 {
		return 0.7
	}
	return score
}

func max(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}
