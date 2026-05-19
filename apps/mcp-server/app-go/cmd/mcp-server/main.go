package main

import (
	"log"
	"net/http"
	"strings"

	"platform.local/mcp-server/internal/app"
)

func main() {
	cfg := app.ConfigFromEnv()
	addr := cfg.Port
	if !strings.Contains(addr, ":") {
		addr = ":" + addr
	}
	log.Printf("mcp-server listening on %s llm_base_url=%s", addr, cfg.LLMBaseURL)
	if err := http.ListenAndServe(addr, app.NewServer(cfg)); err != nil {
		log.Fatal(err)
	}
}
