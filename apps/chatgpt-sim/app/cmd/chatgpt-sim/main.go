package main

import (
	"log"
	"net/http"
	"os"

	"platform.local/chatgpt-sim/internal/app"
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
	log.Printf("starting role=%s addr=:%s", cfg.Role, cfg.Port)
	if err := http.ListenAndServe(":"+cfg.Port, app.NewServer(cfg, http.DefaultClient)); err != nil {
		log.Fatal(err)
	}
	_ = os.Stdout.Sync()
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
