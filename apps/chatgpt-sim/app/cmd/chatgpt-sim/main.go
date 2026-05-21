package main

import (
	"context"
	"log"
	"net/http"
	"os"

	"platform.local/chatgpt-sim/internal/app"
	"platform.local/idpauth"
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

	var verifier idpauth.TokenVerifier
	if cfg.AuthMode == "oidc" && cfg.Role == "shell" {
		oidcVerifier, err := idpauth.NewOIDCVerifier(context.Background(), cfg.OIDCIssuer, cfg.OIDCAudience, cfg.OIDCJWKSURI)
		if err != nil {
			log.Fatalf("configure oidc: %v", err)
		}
		verifier = oidcVerifier
	}

	log.Printf("starting role=%s addr=:%s auth=%s", cfg.Role, cfg.Port, cfg.AuthMode)
	if err := http.ListenAndServe(":"+cfg.Port, app.NewServer(cfg, http.DefaultClient, verifier)); err != nil {
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
