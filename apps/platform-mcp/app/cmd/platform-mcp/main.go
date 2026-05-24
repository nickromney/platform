package main

import (
	"log"

	"platform.local/appconfig"
	"platform.local/apphealth"
	"platform.local/apphttp"
	"platform.local/platform-mcp/internal/app"
)

func main() {
	if apphealth.HandleHealthcheckCommand("8080", "/health") {
		return
	}
	cfg := app.ConfigFromEnv()
	if cfg.MetricsEnabled {
		metricsAddr := appconfig.NormalizeAddr(cfg.MetricsPort)
		go func() {
			log.Printf("platform-mcp metrics listening on %s", metricsAddr)
			if err := apphttp.ListenAndServe(metricsAddr, app.NewMetricsHandler()); err != nil {
				log.Printf("platform-mcp metrics server stopped: %v", err)
			}
		}()
	}
	addr := appconfig.NormalizeAddr(cfg.Port)
	log.Printf("platform-mcp listening on %s llm_base_url=%s", addr, cfg.LLMBaseURL)
	if err := apphttp.ListenAndServe(addr, app.NewServer(cfg)); err != nil {
		log.Fatal(err)
	}
}
