package main

import (
	"log"
	"net/http"
	"strings"

	"platform.local/platform-mcp/internal/app"
)

func main() {
	cfg := app.ConfigFromEnv()
	if cfg.MetricsEnabled {
		metricsAddr := cfg.MetricsPort
		if !strings.Contains(metricsAddr, ":") {
			metricsAddr = ":" + metricsAddr
		}
		go func() {
			log.Printf("platform-mcp metrics listening on %s", metricsAddr)
			if err := http.ListenAndServe(metricsAddr, app.NewMetricsHandler()); err != nil {
				log.Printf("platform-mcp metrics server stopped: %v", err)
			}
		}()
	}
	addr := cfg.Port
	if !strings.Contains(addr, ":") {
		addr = ":" + addr
	}
	log.Printf("platform-mcp listening on %s llm_base_url=%s", addr, cfg.LLMBaseURL)
	if err := http.ListenAndServe(addr, app.NewServer(cfg)); err != nil {
		log.Fatal(err)
	}
}
