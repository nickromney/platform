package main

import (
	"log"
	"net/http"
	"os"
	"strings"

	"platform.local/sentiment/internal/app"
)

func main() {
	cfg := app.Config{
		RuntimeRole: strings.ToLower(env("RUNTIME_ROLE", "all")),
		BackendURL:  env("BACKEND_URL", ""),
		DataDir:     env("DATA_DIR", "/tmp/sentiment"),
		CSVPath:     env("CSV_PATH", ""),
	}
	addr := env("PORT", "8080")
	if !strings.Contains(addr, ":") {
		addr = ":" + addr
	}
	log.Printf("sentiment listening on %s role=%s", addr, cfg.RuntimeRole)
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
