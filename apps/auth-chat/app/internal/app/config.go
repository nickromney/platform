package app

import (
	"strings"
	"time"

	"platform.local/appconfig"
	"platform.local/apphttp"
	"platform.local/idpauth"
)

const defaultModel = "Qwen3.5-9B-MLX-4bit"

type Config struct {
	Port            string
	PublicBaseURL   string
	LLMURL          string
	LLMModel        string
	LLMAPIKey       string
	LLMTimeout      time.Duration
	LLMMaxTokens    int
	LLMTemperature  float64
	ShowNetworkPath string
	NetworkHops     string
	AuthMode        string
	APIAuthMode     string
	OIDCIssuer      string
	OIDCAudience    string
	OIDCJWKSURI     string
	OIDCClientID    string
	OIDCRedirect    string
}

func ConfigFromEnv() Config {
	port := appconfig.FirstNonEmpty(apphttp.Env("PORT", ""), apphttp.Env("AUTH_CHAT_PORT", ""), "8080")
	publicBaseURL := apphttp.EnvURL("PUBLIC_BASE_URL", "http://localhost:"+port)
	auth := idpauth.RuntimeAuthConfigFromEnv("frontend")
	apiAuthMode := appconfig.FirstNonEmpty(apphttp.Env("AUTH_CHAT_API_AUTH_METHOD", ""), auth.APIAuthMode)
	if strings.TrimSpace(apiAuthMode) == "" {
		apiAuthMode = "none"
	}
	return Config{
		Port:           port,
		PublicBaseURL:  publicBaseURL,
		LLMURL:         apphttp.EnvURL("AUTH_CHAT_LLM_URL", apphttp.EnvURL("LLM_URL", "http://127.0.0.1:8000/v1/chat/completions")),
		LLMModel:       appconfig.FirstNonEmpty(apphttp.Env("AUTH_CHAT_LLM_MODEL", ""), apphttp.Env("LLM_MODEL", ""), defaultModel),
		LLMAPIKey:      appconfig.FirstNonEmpty(apphttp.Env("AUTH_CHAT_LLM_API_KEY", ""), apphttp.Env("LLM_API_KEY", "")),
		LLMTimeout:     apphttp.EnvSeconds("AUTH_CHAT_LLM_TIMEOUT_SECONDS", apphttp.EnvSeconds("LLM_TIMEOUT_SECONDS", 45*time.Second)),
		LLMMaxTokens:   apphttp.EnvInt("AUTH_CHAT_LLM_MAX_TOKENS", apphttp.EnvInt("LLM_MAX_TOKENS", 512)),
		LLMTemperature: envFloat("AUTH_CHAT_LLM_TEMPERATURE", 0.2),
		ShowNetworkPath: appconfig.FirstNonEmpty(
			apphttp.Env("AUTH_CHAT_SHOW_NETWORK_PATH", ""),
			apphttp.Env("SHOW_NETWORK_PATH", ""),
		),
		NetworkHops:  appconfig.FirstNonEmpty(apphttp.Env("AUTH_CHAT_NETWORK_HOPS", ""), apphttp.Env("NETWORK_HOPS", "")),
		AuthMode:     auth.AuthMode,
		APIAuthMode:  strings.ToLower(strings.TrimSpace(apiAuthMode)),
		OIDCIssuer:   auth.OIDCIssuer,
		OIDCAudience: auth.OIDCAudience,
		OIDCJWKSURI:  auth.OIDCJWKSURI,
		OIDCClientID: auth.OIDCClientID,
		OIDCRedirect: auth.OIDCRedirect,
	}
}
