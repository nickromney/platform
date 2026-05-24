package app

import (
	"platform.local/appconfig"
)

type Config struct {
	Port             string
	MetricsEnabled   bool
	MetricsPort      string
	PublicBaseURL    string
	LLMBaseURL       string
	LLMModel         string
	OTLPEndpoint     string
	ServiceName      string
	ServiceNamespace string
}

func ConfigFromEnv() Config {
	port := appconfig.Env("PORT", "8080")
	return Config{
		Port:             port,
		MetricsEnabled:   appconfig.EnvBool("PLATFORM_MCP_METRICS_ENABLED", true),
		MetricsPort:      appconfig.Env("PLATFORM_MCP_METRICS_PORT", "9090"),
		PublicBaseURL:    appconfig.EnvURL("PUBLIC_BASE_URL", "http://localhost:"+port),
		LLMBaseURL:       appconfig.EnvURL("LLM_BASE_URL", "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1"),
		LLMModel:         appconfig.Env("LLM_MODEL", ""),
		OTLPEndpoint:     appconfig.EnvURL("OTEL_EXPORTER_OTLP_ENDPOINT", ""),
		ServiceName:      appconfig.Env("OTEL_SERVICE_NAME", "platform-mcp"),
		ServiceNamespace: appconfig.Env("OTEL_SERVICE_NAMESPACE", "platform"),
	}
}
