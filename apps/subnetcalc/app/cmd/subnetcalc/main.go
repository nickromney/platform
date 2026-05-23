package main

import (
	"context"
	"log"

	"platform.local/apphttp"
	"platform.local/idpauth"
	"platform.local/subnetcalc/internal/app"
)

func main() {
	if apphttp.HandleHealthcheckCommand("8080", "/api/v1/health") {
		return
	}

	auth := idpauth.RuntimeAuthConfigFromEnv("all")
	cfg := app.Config{
		Addr:            apphttp.NormalizeAddr(apphttp.Env("PORT", "8080")),
		AuthMode:        auth.AuthMode,
		APIAuthMode:     auth.APIAuthMode,
		RuntimeRole:     auth.RuntimeRole,
		BackendURL:      apphttp.Env("BACKEND_URL", ""),
		OIDCIssuer:      auth.OIDCIssuer,
		OIDCClientID:    auth.OIDCClientID,
		OIDCAudience:    auth.OIDCAudience,
		OIDCJWKSURI:     auth.OIDCJWKSURI,
		OIDCRedirect:    auth.OIDCRedirect,
		NetworkHops:     apphttp.Env("NETWORK_HOPS", ""),
		ShowNetworkPath: apphttp.Env("SHOW_NETWORK_PATH", ""),
	}

	var verifier idpauth.TokenVerifier
	if auth.ShouldVerifyOIDC("frontend") {
		oidcVerifier, err := idpauth.NewOIDCVerifier(context.Background(), cfg.OIDCIssuer, auth.VerifierAudience(), cfg.OIDCJWKSURI)
		if err != nil {
			log.Fatalf("configure oidc: %v", err)
		}
		verifier = oidcVerifier
	}

	log.Printf("subnetcalc listening on %s auth=%s", cfg.Addr, cfg.AuthMode)
	if err := apphttp.ListenAndServe(cfg.Addr, app.NewServer(cfg, verifier)); err != nil {
		log.Fatal(err)
	}
}
