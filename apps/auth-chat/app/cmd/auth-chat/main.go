package main

import (
	"log"
	"net/http"

	"platform.local/apphttp"
	"platform.local/auth-chat/internal/app"
	"platform.local/idpauth"
)

func main() {
	if apphttp.HandleHealthcheckCommand("8080", "/health") {
		return
	}

	cfg := app.ConfigFromEnv()
	verifier, err := idpauth.BootstrapVerifier(cfg.OIDCIssuer, cfg.OIDCAudience, cfg.OIDCJWKSURI, cfg.APIAuthMode == "oidc")
	if err != nil {
		log.Fatalf("configure oidc: %v", err)
	}

	log.Printf("starting auth-chat addr=:%s api_auth=%s llm=%s model=%s", cfg.Port, cfg.APIAuthMode, cfg.LLMURL, cfg.LLMModel)
	if err := apphttp.ListenAndServe(cfg.Port, app.NewServer(cfg, http.DefaultClient, verifier)); err != nil {
		log.Fatal(err)
	}
}
