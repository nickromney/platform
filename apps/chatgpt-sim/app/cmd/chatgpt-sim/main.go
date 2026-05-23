package main

import (
	"context"
	"log"
	"net/http"

	"platform.local/apphttp"
	"platform.local/chatgpt-sim/internal/app"
	"platform.local/idpauth"
)

func main() {
	if apphttp.HandleHealthcheckCommand("8080", "/health") {
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
	if err := apphttp.ListenAndServe(cfg.Port, app.NewServer(cfg, http.DefaultClient, verifier)); err != nil {
		log.Fatal(err)
	}
}
