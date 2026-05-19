package app

import (
	"os"
	"strings"
)

type Config struct {
	Port             string
	PublicBaseURL    string
	LLMBaseURL       string
	LLMModel         string
	OTLPEndpoint     string
	ServiceName      string
	ServiceNamespace string
}

func ConfigFromEnv() Config {
	port := env("PORT", "8080")
	return Config{
		Port:             port,
		PublicBaseURL:    strings.TrimRight(env("PUBLIC_BASE_URL", "http://localhost:"+port), "/"),
		LLMBaseURL:       strings.TrimRight(env("LLM_BASE_URL", "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1"), "/"),
		LLMModel:         env("LLM_MODEL", ""),
		OTLPEndpoint:     strings.TrimRight(env("OTEL_EXPORTER_OTLP_ENDPOINT", ""), "/"),
		ServiceName:      env("OTEL_SERVICE_NAME", "platform-mcp"),
		ServiceNamespace: env("OTEL_SERVICE_NAMESPACE", "platform"),
	}
}

func env(key, fallback string) string {
	if value := strings.TrimSpace(os.Getenv(key)); value != "" {
		return value
	}
	return fallback
}
