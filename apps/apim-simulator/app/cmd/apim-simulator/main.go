package main

import (
	"context"
	"log"
	"os"

	"platform.local/apim-simulator/internal/app"
	"platform.local/apphttp"
	"platform.local/idpauth"
)

func main() {
	if apphttp.HandleHealthcheckCommand("8000", "/apim/health") {
		return
	}

	cfg := app.Config{
		Addr: apphttp.NormalizeAddr(apphttp.Env("PORT", "8000")),
	}
	if path := firstExistingPath(apphttp.Env("APIM_CONFIG_PATH", ""), apphttp.Env("APIM_CONFIG_SOURCE_PATH", "")); path != "" {
		loaded, err := app.LoadConfig(path)
		if err != nil {
			log.Fatalf("load config: %v", err)
		}
		cfg = loaded
		cfg.Addr = apphttp.NormalizeAddr(apphttp.Env("PORT", "8000"))
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
	if err := apphttp.ListenAndServe(cfg.Addr, app.NewServer(cfg, verifier)); err != nil {
		log.Fatal(err)
	}
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
