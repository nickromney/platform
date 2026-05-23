package main

import (
	"log"
	"net/http"
	"time"

	"platform.local/apphttp"
	"platform.local/langfuse-demos/internal/app"
)

func main() {
	if apphttp.HandleHealthcheckCommand("8080", "/health") {
		return
	}
	cfg := app.ConfigFromEnv()
	log.Printf("langfuse demo role=%s listening on :%s", cfg.Role, cfg.Port)
	if err := apphttp.ListenAndServe(cfg.Port, app.NewServer(cfg, &http.Client{Timeout: 45 * time.Second})); err != nil {
		log.Fatal(err)
	}
}
