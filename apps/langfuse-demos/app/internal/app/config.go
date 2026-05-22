package app

import (
	"os"
	"strconv"
	"strings"
	"time"
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
	role := getenv("DEMO_ROLE", "trace-chat")
	return Config{
		Role:              role,
		Port:              getenv("PORT", "8080"),
		PublicBaseURL:     getenv("PUBLIC_BASE_URL", "http://localhost:8080"),
		LangfuseHost:      strings.TrimRight(getenv("LANGFUSE_HOST", "http://langfuse-web.langfuse.svc.cluster.local:3000"), "/"),
		LangfusePublicKey: getenv("LANGFUSE_PUBLIC_KEY", "pk-lf-local-platform"),
		LangfuseSecretKey: getenv("LANGFUSE_SECRET_KEY", "sk-lf-local-platform"),
		OpenAIBaseURL:     strings.TrimRight(getenv("OPENAI_BASE_URL", "http://agentgateway-ai-gateway.agentgateway-system.svc.cluster.local/v1"), "/"),
		OpenAIAPIKey:      os.Getenv("OPENAI_API_KEY"),
		OpenAIModel:       getenv("OPENAI_MODEL", "local-omlx"),
		DemoName:          getenv("DEMO_NAME", role),
		LLMTimeout:        secondsDuration("LLM_TIMEOUT_SECONDS", 30*time.Second),
		LangfuseTimeout:   secondsDuration("LANGFUSE_TIMEOUT_SECONDS", 5*time.Second),
	}
}

func getenv(key, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func secondsDuration(key string, fallback time.Duration) time.Duration {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback
	}
	seconds, err := strconv.ParseFloat(raw, 64)
	if err != nil || seconds <= 0 {
		return fallback
	}
	return time.Duration(seconds * float64(time.Second))
}
