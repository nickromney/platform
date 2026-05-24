package main

import (
	"context"
	"log"

	"platform.local/appconfig"
	"platform.local/apphealth"
	"platform.local/apphttp"
	"platform.local/idpauth"
	"platform.local/sentiment/internal/app"
)

func main() {
	if apphealth.HandleHealthcheckCommand("8080", "/health") {
		return
	}

	auth := idpauth.RuntimeAuthConfigFromEnv("all")
	cfg := app.Config{
		AuthMode:        auth.AuthMode,
		APIAuthMode:     auth.APIAuthMode,
		RuntimeRole:     auth.RuntimeRole,
		BackendURL:      appconfig.Env("BACKEND_URL", ""),
		APIBasePath:     appconfig.Env("API_BASE_PATH", "/api/v1"),
		OIDCIssuer:      auth.OIDCIssuer,
		OIDCAudience:    auth.OIDCAudience,
		OIDCJWKSURI:     auth.OIDCJWKSURI,
		DataDir:         appconfig.Env("DATA_DIR", "/tmp/sentiment"),
		CSVPath:         appconfig.Env("CSV_PATH", ""),
		NetworkHops:     appconfig.Env("NETWORK_HOPS", ""),
		ShowNetworkPath: appconfig.Env("SHOW_NETWORK_PATH", ""),
	}
	addr := appconfig.NormalizeAddr(appconfig.Env("PORT", "8080"))
	var verifier idpauth.TokenVerifier
	if auth.ShouldVerifyOIDC("frontend") {
		oidcVerifier, err := idpauth.NewOIDCVerifier(context.Background(), cfg.OIDCIssuer, auth.VerifierAudience(), cfg.OIDCJWKSURI)
		if err != nil {
			log.Fatalf("configure oidc: %v", err)
		}
		verifier = oidcVerifier
	}

	log.Printf("sentiment listening on %s role=%s auth=%s api_auth=%s", addr, cfg.RuntimeRole, cfg.AuthMode, cfg.APIAuthMode)
	if err := apphttp.ListenAndServe(addr, app.NewServer(cfg, verifier)); err != nil {
		log.Fatal(err)
	}
}
