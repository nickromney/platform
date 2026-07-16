package app

import (
	"time"

	"platform.local/apphttp"
)

type Config struct {
	Role              string
	Port              string
	PublicBaseURL     string
	LangfuseHost      string
	LangfusePublicKey string
	LangfuseSecretKey string
	OpenAIBaseURL     string
	OpenAIAPIKey      string
	OpenAIModel       string
	MCPBaseURL        string
	MCPToolName       string
	DemoName          string
	LLMTimeout        time.Duration
	LangfuseTimeout   time.Duration
	MCPTimeout        time.Duration
}

func ConfigFromEnv() Config {
	role := apphttp.Env("DEMO_ROLE", "trace-chat")
	return Config{
		Role:              role,
		Port:              apphttp.Env("PORT", "8080"),
		PublicBaseURL:     apphttp.EnvURL("PUBLIC_BASE_URL", "http://localhost:8080"),
		LangfuseHost:      apphttp.EnvURL("LANGFUSE_HOST", "http://langfuse-web.langfuse.svc.cluster.local:3000"),
		LangfusePublicKey: apphttp.Env("LANGFUSE_PUBLIC_KEY", "pk-lf-local-platform"),
		LangfuseSecretKey: apphttp.Env("LANGFUSE_SECRET_KEY", "sk-lf-local-platform"),
		OpenAIBaseURL:     apphttp.EnvURL("OPENAI_BASE_URL", "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1"),
		OpenAIAPIKey:      apphttp.Env("OPENAI_API_KEY", ""),
		OpenAIModel:       apphttp.Env("OPENAI_MODEL", "auto"),
		MCPBaseURL:        apphttp.EnvURL("MCP_BASE_URL", "http://platform-mcp.mcp.svc.cluster.local:8080/mcp"),
		MCPToolName:       apphttp.Env("MCP_TOOL_NAME", "d2_validate"),
		DemoName:          apphttp.Env("DEMO_NAME", role),
		LLMTimeout:        apphttp.EnvSeconds("LLM_TIMEOUT_SECONDS", 10*time.Second),
		LangfuseTimeout:   apphttp.EnvSeconds("LANGFUSE_TIMEOUT_SECONDS", 15*time.Second),
		MCPTimeout:        apphttp.EnvSeconds("MCP_TIMEOUT_SECONDS", 10*time.Second),
	}
}
