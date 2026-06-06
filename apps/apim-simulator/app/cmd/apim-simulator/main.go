package main

import (
	"log"
	"os"

	"platform.local/apim-simulator/internal/app"
	"platform.local/appconfig"
	"platform.local/apphttp"
	"platform.local/idpauth"
)

func main() {
	if apphttp.HandleHealthcheckCommand("8000", "/apim/health") {
		return
	}

	cfg := app.Config{
		Addr: appconfig.NormalizeAddr(appconfig.Env("PORT", "8000")),
	}
	if path := firstExistingPath(appconfig.Env("APIM_CONFIG_PATH", ""), appconfig.Env("APIM_CONFIG_SOURCE_PATH", "")); path != "" {
		loaded, err := app.LoadConfig(path)
		if err != nil {
			log.Fatalf("load config: %v", err)
		}
		cfg = loaded
		cfg.Addr = appconfig.NormalizeAddr(appconfig.Env("PORT", "8000"))
	}
	cfg.ApplyRuntimeDefaults()

	verifier, err := idpauth.BootstrapVerifier(cfg.OIDC.Issuer, cfg.OIDC.Audience, cfg.OIDC.JWKSURI, cfg.OIDC.Issuer != "" && !cfg.AllowAnonymous)
	if err != nil {
		log.Fatalf("configure oidc: %v", err)
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
