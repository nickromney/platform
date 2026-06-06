package app

import (
	"encoding/json"
	"strings"
	"time"

	"platform.local/apphttp"
	"platform.local/idpauth"
)

type Config struct {
	Role              string
	Port              string
	PublicBaseURL     string
	MCPURL            string
	MCPInternalURL    string
	MCPConnectors     []ConnectorConfig
	LLMURL            string
	LLMModel          string
	LLMTimeout        time.Duration
	LLMMaxTokens      int
	LangfuseHost      string
	LangfusePublicKey string
	LangfuseSecretKey string
	LangfuseTimeout   time.Duration
	ShowNetworkPath   string
	NetworkHops       string
	AuthMode          string
	APIAuthMode       string
	OIDCIssuer        string
	OIDCAudience      string
	OIDCJWKSURI       string
	OIDCClientID      string
	OIDCRedirect      string
}

type ConnectorConfig struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	URL         string `json:"url"`
	InternalURL string `json:"internal_url"`
	Auth        string `json:"auth"`
}

func ConfigFromEnv() Config {
	role := apphttp.Env("ROLE", "")
	if role == "" {
		role = apphttp.Env("PCE_GO_APP_ROLE", "shell")
	}
	port := apphttp.Env("PORT", "8080")
	publicBaseURL := apphttp.EnvURL("PUBLIC_BASE_URL", "http://localhost:"+port)
	mcpURL := apphttp.Env("MCP_URL", "http://localhost:18082/mcp")
	mcpInternalURL := apphttp.Env("MCP_INTERNAL_URL", "")
	mcpConnectors := parseConnectorConfigs(apphttp.Env("MCP_CONNECTORS", ""))
	llmURL := apphttp.Env("LLM_URL", "")
	llmModel := apphttp.Env("LLM_MODEL", "")
	llmMaxTokens := apphttp.EnvInt("LLM_MAX_TOKENS", 32)
	langfuseHost := apphttp.EnvURL("LANGFUSE_HOST", "")
	showNetworkPath := apphttp.Env("SHOW_NETWORK_PATH", "")
	networkHops := apphttp.Env("NETWORK_HOPS", "")
	auth := idpauth.RuntimeAuthConfigFromEnv("shell")
	return Config{
		Role:              role,
		Port:              port,
		PublicBaseURL:     publicBaseURL,
		MCPURL:            mcpURL,
		MCPInternalURL:    mcpInternalURL,
		MCPConnectors:     mcpConnectors,
		LLMURL:            llmURL,
		LLMModel:          llmModel,
		LLMTimeout:        apphttp.EnvSeconds("LLM_TIMEOUT_SECONDS", time.Second),
		LLMMaxTokens:      llmMaxTokens,
		LangfuseHost:      langfuseHost,
		LangfusePublicKey: apphttp.Env("LANGFUSE_PUBLIC_KEY", ""),
		LangfuseSecretKey: apphttp.Env("LANGFUSE_SECRET_KEY", ""),
		LangfuseTimeout:   apphttp.EnvSeconds("LANGFUSE_TIMEOUT_SECONDS", time.Second),
		ShowNetworkPath:   showNetworkPath,
		NetworkHops:       networkHops,
		AuthMode:          auth.AuthMode,
		APIAuthMode:       auth.APIAuthMode,
		OIDCIssuer:        auth.OIDCIssuer,
		OIDCAudience:      auth.OIDCAudience,
		OIDCJWKSURI:       auth.OIDCJWKSURI,
		OIDCClientID:      auth.OIDCClientID,
		OIDCRedirect:      auth.OIDCRedirect,
	}
}

func parseConnectorConfigs(raw string) []ConnectorConfig {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil
	}
	var configs []ConnectorConfig
	if err := json.Unmarshal([]byte(raw), &configs); err != nil {
		return nil
	}
	out := make([]ConnectorConfig, 0, len(configs))
	for _, cfg := range configs {
		cfg.ID = strings.TrimSpace(cfg.ID)
		cfg.Name = strings.TrimSpace(cfg.Name)
		cfg.URL = normalizeConnectorURL(cfg.URL)
		cfg.InternalURL = normalizeConnectorURL(cfg.InternalURL)
		cfg.Auth = strings.TrimSpace(cfg.Auth)
		if cfg.URL == "" {
			continue
		}
		out = append(out, cfg)
	}
	return out
}
