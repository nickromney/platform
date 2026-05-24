package app

import (
	"time"

	"platform.local/appconfig"
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
	DemoName          string
	LLMTimeout        time.Duration
	LangfuseTimeout   time.Duration
}

func ConfigFromEnv() Config {
	role := appconfig.Env("DEMO_ROLE", "trace-chat")
	return Config{
		Role:              role,
		Port:              appconfig.Env("PORT", "8080"),
		PublicBaseURL:     appconfig.EnvURL("PUBLIC_BASE_URL", "http://localhost:8080"),
		LangfuseHost:      appconfig.EnvURL("LANGFUSE_HOST", "http://langfuse-web.langfuse.svc.cluster.local:3000"),
		LangfusePublicKey: appconfig.Env("LANGFUSE_PUBLIC_KEY", "pk-lf-local-platform"),
		LangfuseSecretKey: appconfig.Env("LANGFUSE_SECRET_KEY", "sk-lf-local-platform"),
		OpenAIBaseURL:     appconfig.EnvURL("OPENAI_BASE_URL", "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1"),
		OpenAIAPIKey:      appconfig.Env("OPENAI_API_KEY", ""),
		OpenAIModel:       appconfig.Env("OPENAI_MODEL", "auto"),
		DemoName:          appconfig.Env("DEMO_NAME", role),
		LLMTimeout:        appconfig.EnvSeconds("LLM_TIMEOUT_SECONDS", 10*time.Second),
		LangfuseTimeout:   appconfig.EnvSeconds("LANGFUSE_TIMEOUT_SECONDS", 15*time.Second),
	}
}
