package app

import (
	"encoding/json"
	"strings"
	"time"

	"platform.local/appconfig"
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
	role := appconfig.Env("ROLE", "")
	if role == "" {
		role = appconfig.Env("PCE_GO_APP_ROLE", "shell")
	}
	port := appconfig.Env("PORT", "8080")
	publicBaseURL := appconfig.EnvURL("PUBLIC_BASE_URL", "http://localhost:"+port)
	mcpURL := appconfig.Env("MCP_URL", "http://localhost:18082/mcp")
	mcpInternalURL := appconfig.Env("MCP_INTERNAL_URL", "")
	mcpConnectors := parseConnectorConfigs(appconfig.Env("MCP_CONNECTORS", ""))
	llmURL := appconfig.Env("LLM_URL", "")
	llmModel := appconfig.Env("LLM_MODEL", "")
	llmMaxTokens := appconfig.EnvInt("LLM_MAX_TOKENS", 32)
	langfuseHost := appconfig.EnvURL("LANGFUSE_HOST", "")
	showNetworkPath := appconfig.Env("SHOW_NETWORK_PATH", "")
	networkHops := appconfig.Env("NETWORK_HOPS", "")
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
		LLMTimeout:        appconfig.EnvSeconds("LLM_TIMEOUT_SECONDS", time.Second),
		LLMMaxTokens:      llmMaxTokens,
		LangfuseHost:      langfuseHost,
		LangfusePublicKey: appconfig.Env("LANGFUSE_PUBLIC_KEY", ""),
		LangfuseSecretKey: appconfig.Env("LANGFUSE_SECRET_KEY", ""),
		LangfuseTimeout:   appconfig.EnvSeconds("LANGFUSE_TIMEOUT_SECONDS", time.Second),
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
