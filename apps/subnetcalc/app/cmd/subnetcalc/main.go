package main

import (
	"log"

	"platform.local/appconfig"
	"platform.local/apphealth"
	"platform.local/apphttp"
	"platform.local/idpauth"
	"platform.local/subnetcalc/internal/app"
)

func main() {
	if apphealth.HandleHealthcheckCommand("8080", "/api/v1/health") {
		return
	}

	auth := idpauth.RuntimeAuthConfigFromEnv("all")
	cfg := app.Config{
		Addr:            appconfig.NormalizeAddr(appconfig.Env("PORT", "8080")),
		AuthMode:        auth.AuthMode,
		APIAuthMode:     auth.APIAuthMode,
		RuntimeRole:     auth.RuntimeRole,
		BackendURL:      appconfig.Env("BACKEND_URL", ""),
		OIDCIssuer:      auth.OIDCIssuer,
		OIDCClientID:    auth.OIDCClientID,
		OIDCAudience:    auth.OIDCAudience,
		OIDCJWKSURI:     auth.OIDCJWKSURI,
		OIDCRedirect:    auth.OIDCRedirect,
		NetworkHops:     appconfig.Env("NETWORK_HOPS", ""),
		ShowNetworkPath: appconfig.Env("SHOW_NETWORK_PATH", ""),
	}

	verifier, err := idpauth.BootstrapVerifier(auth.OIDCIssuer, auth.VerifierAudience(), auth.OIDCJWKSURI, auth.ShouldVerifyOIDC("frontend"))
	if err != nil {
		log.Fatalf("configure oidc: %v", err)
	}

	log.Printf("subnetcalc listening on %s auth=%s", cfg.Addr, cfg.AuthMode)
	if err := apphttp.ListenAndServe(cfg.Addr, app.NewServer(cfg, verifier)); err != nil {
		log.Fatal(err)
	}
}
