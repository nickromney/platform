package app

import (
	"encoding/json"
	"os"
	"strings"
)

type Config struct {
	Role            string
	Port            string
	PublicBaseURL   string
	MCPURL          string
	MCPInternalURL  string
	MCPConnectors   []ConnectorConfig
	LLMURL          string
	LLMModel        string
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

type ConnectorConfig struct {
	ID          string `json:"id"`
	Name        string `json:"name"`
	URL         string `json:"url"`
	InternalURL string `json:"internal_url"`
	Auth        string `json:"auth"`
}

func ConfigFromEnv() Config {
	role := strings.TrimSpace(os.Getenv("ROLE"))
	if role == "" {
		role = strings.TrimSpace(os.Getenv("PCE_GO_APP_ROLE"))
	}
	if role == "" {
		role = "shell"
	}
	port := strings.TrimSpace(os.Getenv("PORT"))
	if port == "" {
		port = "8080"
	}
	publicBaseURL := strings.TrimRight(strings.TrimSpace(os.Getenv("PUBLIC_BASE_URL")), "/")
	if publicBaseURL == "" {
		publicBaseURL = "http://localhost:" + port
	}
	mcpURL := strings.TrimSpace(os.Getenv("MCP_URL"))
	if mcpURL == "" {
		mcpURL = "http://localhost:18082/mcp"
	}
	mcpInternalURL := strings.TrimSpace(os.Getenv("MCP_INTERNAL_URL"))
	mcpConnectors := parseConnectorConfigs(os.Getenv("MCP_CONNECTORS"))
	llmURL := strings.TrimSpace(os.Getenv("LLM_URL"))
	llmModel := strings.TrimSpace(os.Getenv("LLM_MODEL"))
	showNetworkPath := strings.TrimSpace(os.Getenv("SHOW_NETWORK_PATH"))
	networkHops := strings.TrimSpace(os.Getenv("NETWORK_HOPS"))
	authMode := strings.ToLower(strings.TrimSpace(os.Getenv("AUTH_METHOD")))
	if authMode == "" {
		authMode = "none"
	}
	apiAuthMode := strings.ToLower(strings.TrimSpace(os.Getenv("API_AUTH_METHOD")))
	if apiAuthMode == "" {
		apiAuthMode = authMode
	}
	oidcIssuer := firstEnv("OIDC_ISSUER_URL", "OIDC_AUTHORITY")
	return Config{
		Role:            role,
		Port:            port,
		PublicBaseURL:   publicBaseURL,
		MCPURL:          mcpURL,
		MCPInternalURL:  mcpInternalURL,
		MCPConnectors:   mcpConnectors,
		LLMURL:          llmURL,
		LLMModel:        llmModel,
		ShowNetworkPath: showNetworkPath,
		NetworkHops:     networkHops,
		AuthMode:        authMode,
		APIAuthMode:     apiAuthMode,
		OIDCIssuer:      oidcIssuer,
		OIDCAudience:    strings.TrimSpace(os.Getenv("OIDC_AUDIENCE")),
		OIDCJWKSURI:     strings.TrimSpace(os.Getenv("OIDC_JWKS_URI")),
		OIDCClientID:    strings.TrimSpace(os.Getenv("OIDC_CLIENT_ID")),
		OIDCRedirect:    strings.TrimSpace(os.Getenv("OIDC_REDIRECT_URI")),
	}
}

func firstEnv(keys ...string) string {
	for _, key := range keys {
		if value := os.Getenv(key); value != "" {
			return value
		}
	}
	return ""
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
