package app

import (
	"net"
	"path/filepath"
	"strings"
)

func pathMatches(prefix, requestPath string) bool {
	cleanPrefix := "/" + strings.Trim(prefix, "/")
	if cleanPrefix == "/" {
		return true
	}
	return requestPath == cleanPrefix || strings.HasPrefix(requestPath, cleanPrefix+"/")
}

func hostMatches(patterns []string, host string) bool {
	host = stripPort(strings.ToLower(host))
	for _, pattern := range patterns {
		pattern = strings.ToLower(strings.TrimSpace(pattern))
		if pattern == "" {
			continue
		}
		if pattern == host || stripPort(pattern) == host {
			return true
		}
		if ok, _ := filepath.Match(pattern, host); ok {
			return true
		}
	}
	return false
}

func stripPort(host string) string {
	host = strings.TrimSpace(strings.Split(host, ",")[0])
	if host == "" {
		return ""
	}
	if strings.HasPrefix(host, "[") {
		if parsed, _, err := net.SplitHostPort(host); err == nil {
			return parsed
		}
		return host
	}
	if parsed, _, err := net.SplitHostPort(host); err == nil {
		return parsed
	}
	if i := strings.LastIndex(host, ":"); i > -1 {
		if allDigits(host[i+1:]) {
			return host[:i]
		}
	}
	return host
}

func allDigits(value string) bool {
	if value == "" {
		return false
	}
	for _, r := range value {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
