package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"platform.local/sentiment/internal/app"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		healthcheck()
		return
	}

	cfg := app.Config{
		AuthMode:     strings.ToLower(env("AUTH_METHOD", "none")),
		APIAuthMode:  strings.ToLower(env("API_AUTH_METHOD", "")),
		RuntimeRole:  strings.ToLower(env("RUNTIME_ROLE", "all")),
		BackendURL:   env("BACKEND_URL", ""),
		OIDCIssuer:   firstEnv("OIDC_ISSUER_URL", "OIDC_AUTHORITY"),
		OIDCAudience: env("OIDC_AUDIENCE", ""),
		OIDCJWKSURI:  env("OIDC_JWKS_URI", ""),
		DataDir:      env("DATA_DIR", "/tmp/sentiment"),
		CSVPath:      env("CSV_PATH", ""),
	}
	if cfg.APIAuthMode == "" {
		cfg.APIAuthMode = cfg.AuthMode
	}
	addr := env("PORT", "8080")
	if !strings.Contains(addr, ":") {
		addr = ":" + addr
	}
	var verifier app.TokenVerifier
	if cfg.AuthMode == "oidc" && cfg.RuntimeRole != "frontend" {
		oidcVerifier, err := app.NewOIDCVerifier(context.Background(), cfg.OIDCIssuer, cfg.OIDCAudience, cfg.OIDCJWKSURI)
		if err != nil {
			log.Fatalf("configure oidc: %v", err)
		}
		verifier = oidcVerifier
	}

	log.Printf("sentiment listening on %s role=%s auth=%s api_auth=%s", addr, cfg.RuntimeRole, cfg.AuthMode, cfg.APIAuthMode)
	if err := http.ListenAndServe(addr, app.NewServer(cfg, verifier)); err != nil {
		log.Fatal(err)
	}
}

func healthcheck() {
	port := env("PORT", "8080")
	client := http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + strings.TrimPrefix(port, ":") + "/health")
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

func firstEnv(keys ...string) string {
	for _, key := range keys {
		if value := os.Getenv(key); value != "" {
			return value
		}
	}
	return ""
}
