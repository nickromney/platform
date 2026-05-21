package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"platform.local/idpauth"
	"platform.local/subnetcalc/internal/app"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		healthcheck()
		return
	}

	cfg := app.Config{
		Addr:            env("PORT", "8080"),
		AuthMode:        strings.ToLower(env("AUTH_METHOD", "none")),
		APIAuthMode:     strings.ToLower(env("API_AUTH_METHOD", "")),
		RuntimeRole:     strings.ToLower(env("RUNTIME_ROLE", "all")),
		BackendURL:      env("BACKEND_URL", ""),
		OIDCIssuer:      firstEnv("OIDC_ISSUER_URL", "OIDC_AUTHORITY"),
		OIDCClientID:    env("OIDC_CLIENT_ID", ""),
		OIDCAudience:    env("OIDC_AUDIENCE", ""),
		OIDCJWKSURI:     env("OIDC_JWKS_URI", ""),
		OIDCRedirect:    env("OIDC_REDIRECT_URI", ""),
		NetworkHops:     env("NETWORK_HOPS", ""),
		ShowNetworkPath: env("SHOW_NETWORK_PATH", ""),
	}
	if !strings.Contains(cfg.Addr, ":") {
		cfg.Addr = ":" + cfg.Addr
	}
	if cfg.APIAuthMode == "" {
		cfg.APIAuthMode = cfg.AuthMode
	}

	var verifier idpauth.TokenVerifier
	if cfg.AuthMode == "oidc" && cfg.RuntimeRole != "frontend" {
		oidcVerifier, err := idpauth.NewOIDCVerifier(context.Background(), cfg.OIDCIssuer, firstString(cfg.OIDCAudience, cfg.OIDCClientID), cfg.OIDCJWKSURI)
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

func firstEnv(keys ...string) string {
	for _, key := range keys {
		if value := os.Getenv(key); value != "" {
			return value
		}
	}
	return ""
}

func firstString(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
