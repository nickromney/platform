package app

import "platform.local/apphttp"

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
	port := apphttp.Env("PORT", "8080")
	return Config{
		Port:             port,
		MetricsEnabled:   apphttp.EnvBool("PLATFORM_MCP_METRICS_ENABLED", true),
		MetricsPort:      apphttp.Env("PLATFORM_MCP_METRICS_PORT", "9090"),
		PublicBaseURL:    apphttp.EnvURL("PUBLIC_BASE_URL", "http://localhost:"+port),
		LLMBaseURL:       apphttp.EnvURL("LLM_BASE_URL", "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1"),
		LLMModel:         apphttp.Env("LLM_MODEL", ""),
		OTLPEndpoint:     apphttp.EnvURL("OTEL_EXPORTER_OTLP_ENDPOINT", ""),
		ServiceName:      apphttp.Env("OTEL_SERVICE_NAME", "platform-mcp"),
		ServiceNamespace: apphttp.Env("OTEL_SERVICE_NAMESPACE", "platform"),
	}
}
