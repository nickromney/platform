package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"platform.local/subnetcalc/internal/app"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		healthcheck()
		return
	}

	cfg := app.Config{
		Addr:         env("PORT", "8080"),
		AuthMode:     strings.ToLower(env("AUTH_METHOD", "none")),
		RuntimeRole:  strings.ToLower(env("RUNTIME_ROLE", "all")),
		BackendURL:   env("BACKEND_URL", ""),
		OIDCIssuer:   env("OIDC_ISSUER_URL", ""),
		OIDCClientID: env("OIDC_CLIENT_ID", ""),
	}
	if !strings.Contains(cfg.Addr, ":") {
		cfg.Addr = ":" + cfg.Addr
	}

	var verifier app.TokenVerifier
	if cfg.AuthMode == "oidc" {
		oidcVerifier, err := app.NewOIDCVerifier(context.Background(), cfg.OIDCIssuer, cfg.OIDCClientID)
		if err != nil {
			log.Fatalf("configure oidc: %v", err)
		}
		verifier = oidcVerifier
	}

	log.Printf("subnetcalc listening on %s auth=%s", cfg.Addr, cfg.AuthMode)
	if err := http.ListenAndServe(cfg.Addr, app.NewServer(cfg, verifier)); err != nil {
		log.Fatal(err)
	}
}

func healthcheck() {
	port := env("PORT", "8080")
	client := http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + strings.TrimPrefix(port, ":") + "/api/v1/health")
	if err != nil {
		os.Exit(1)
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode > 299 {
		os.Exit(1)
	}
}

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}
