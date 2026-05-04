package tui

import "strings"

func hasLabel(items []menuItem, label string) bool {
	for _, item := range items {
		if item.Label == label {
			return true
		}
	}
	return false
}

func indexOfLabel(items []menuItem, label string) int {
	for index, item := range items {
		if item.Label == label {
			return index
		}
	}
	return -1
}

func contains(values []string, want string) bool {
	for _, value := range values {
		if value == want {
			return true
		}
	}
	return false
}

func containsString(value, want string) bool {
	return strings.Contains(value, want)
}

func stringCount(value, needle string) int {
	return strings.Count(value, needle)
}

func lineContaining(value, needle string) string {
	for _, line := range strings.Split(value, "\n") {
		if strings.Contains(line, needle) {
			return line
		}
	}
	return ""
}
