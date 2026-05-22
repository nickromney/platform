package main

import (
	"log"
	"net/http"
	"os"
	"time"

	"platform.local/langfuse-demos/internal/app"
)

func main() {
	cfg := app.ConfigFromEnv()
	srv := &http.Server{
		Addr:              ":" + cfg.Port,
		Handler:           app.NewServer(cfg, &http.Client{Timeout: 45 * time.Second}),
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("langfuse demo role=%s listening on :%s", cfg.Role, cfg.Port)
	if err := srv.ListenAndServe(); err != nil && err != http.ErrServerClosed {
		log.Printf("server failed: %v", err)
		os.Exit(1)
	}
}
