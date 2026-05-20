package main

import (
	"log"
	"net/http"
	"os"
	"strings"

	"platform.local/platform-mcp/internal/app"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		resp, err := http.Get("http://127.0.0.1:" + env("PORT", "8080") + "/health")
		if err != nil || resp.StatusCode >= http.StatusBadRequest {
			os.Exit(1)
		}
		_ = resp.Body.Close()
		return
	}
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

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
