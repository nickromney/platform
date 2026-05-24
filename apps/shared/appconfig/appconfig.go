package appconfig

import (
	"os"
	"strconv"
	"strings"
	"time"
)

func Env(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}

func EnvURL(key, fallback string) string {
	return NormalizeURL(Env(key, fallback))
}

func NormalizeURL(value string) string {
	value = strings.TrimSpace(value)
	trimmed := strings.TrimRight(value, "/")
	if trimmed == "" && value == "/" {
		return "/"
	}
	return trimmed
}

func FirstEnv(keys ...string) string {
	for _, key := range keys {
		if value := strings.TrimSpace(os.Getenv(key)); value != "" {
			return value
		}
	}
	return ""
}

func EnvBool(key string, fallback bool) bool {
	switch strings.ToLower(Env(key, "")) {
	case "1", "true", "yes", "on":
		return true
	case "0", "false", "no", "off":
		return false
	default:
		return fallback
	}
}

func EnvSeconds(key string, fallback time.Duration) time.Duration {
	raw := Env(key, "")
	if raw == "" {
		return fallback
	}
	seconds, err := strconv.ParseFloat(raw, 64)
	if err != nil || seconds <= 0 {
		return fallback
	}
	return time.Duration(seconds * float64(time.Second))
}

func EnvInt(key string, fallback int) int {
	raw := Env(key, "")
	if raw == "" {
		return fallback
	}
	value, err := strconv.Atoi(raw)
	if err != nil || value <= 0 {
		return fallback
	}
	return value
}

func NormalizeAddr(addr string) string {
	addr = strings.TrimSpace(addr)
	if addr == "" {
		return ":8080"
	}
	if strings.Contains(addr, ":") {
		return addr
	}
	return ":" + addr
}

func StringDefault(value, fallback string) string {
	if value == "" {
		return fallback
	}
	return value
}

func FirstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}
