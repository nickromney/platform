package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"platform.local/apim-simulator/internal/app"
	"platform.local/idpauth"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		healthcheck()
		return
	}

	cfg := app.Config{
		Addr: ":" + strings.TrimPrefix(env("PORT", "8000"), ":"),
	}
	if path := firstExistingPath(env("APIM_CONFIG_PATH", ""), env("APIM_CONFIG_SOURCE_PATH", "")); path != "" {
		loaded, err := app.LoadConfig(path)
		if err != nil {
			log.Fatalf("load config: %v", err)
		}
		cfg = loaded
		cfg.Addr = ":" + strings.TrimPrefix(env("PORT", "8000"), ":")
	}
	cfg.ApplyRuntimeDefaults()

	var verifier idpauth.TokenVerifier
	if cfg.OIDC.Issuer != "" && !cfg.AllowAnonymous {
		oidcVerifier, err := idpauth.NewOIDCVerifier(context.Background(), cfg.OIDC.Issuer, cfg.OIDC.Audience, cfg.OIDC.JWKSURI)
		if err != nil {
			log.Fatalf("configure oidc: %v", err)
		}
		verifier = oidcVerifier
	}

	log.Printf("apim-simulator listening on %s", cfg.Addr)
	if err := http.ListenAndServe(cfg.Addr, app.NewServer(cfg, verifier)); err != nil {
		log.Fatal(err)
	}
}

func healthcheck() {
	port := strings.TrimPrefix(env("PORT", "8000"), ":")
	client := http.Client{Timeout: 2 * time.Second}
	resp, err := client.Get("http://127.0.0.1:" + port + "/apim/health")
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

func firstExistingPath(paths ...string) string {
	for _, path := range paths {
		if path == "" {
			continue
		}
		if _, err := os.Stat(path); err == nil {
			return path
		}
	}
	for _, path := range paths {
		if path != "" {
			return path
		}
	}
	return ""
}
