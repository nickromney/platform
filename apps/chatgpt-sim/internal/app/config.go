package app

import (
	"os"
	"strings"
)

type Config struct {
	Role           string
	Port           string
	PublicBaseURL  string
	MCPURL         string
	MCPInternalURL string
	LLMURL         string
	LLMModel       string
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
	llmURL := strings.TrimSpace(os.Getenv("LLM_URL"))
	llmModel := strings.TrimSpace(os.Getenv("LLM_MODEL"))
	return Config{
		Role:           role,
		Port:           port,
		PublicBaseURL:  publicBaseURL,
		MCPURL:         mcpURL,
		MCPInternalURL: mcpInternalURL,
		LLMURL:         llmURL,
		LLMModel:       llmModel,
	}
}
